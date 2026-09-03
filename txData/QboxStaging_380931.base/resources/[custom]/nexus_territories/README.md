# nexus_territories

Control de territorios criminales para QBox/OX: zonas configurables o creadas
in-game, influencia persistente por banda, control disputado, graffiti
territorial, airdrops y beneficios de gameplay (descuentos, cooldowns,
bonus/penalizaciones) para el resto del loop ilegal de NEXUS.

## Descripción general

`nexus_territories` modela un mapa de zonas (`config.lua` o creadas con el
editor in-game) donde las bandas acumulan **influencia** (0-100) mediante
contratos, compras en el mercado negro, crafting ilegal u otorgamiento manual
de administración. La banda con más influencia por encima de
`control.minimumInfluence` y con una ventaja mínima (`control.contestedGap`)
sobre la segunda controla la zona; si no se cumple el margen, la zona queda
**disputada**. El control desbloquea beneficios reales (descuento en
`nexus_blackmarket`, reducción de cooldown en `nexus_contracts`, bonus de
influencia, heat/riesgo extra para bandas rivales) que otros recursos NEXUS
consultan a través de este mismo módulo.

Funcionalidades clave:

- Influencia persistente por zona/banda con decaimiento periódico configurable.
- Editor de zonas in-game (`/territoryeditor`) para crear/mover/eliminar zonas dinámicas sin tocar código.
- Graffiti territorial: pintar, eliminar, límite por banda/zona, snap a superficie real (normal de pared).
- Airdrops territoriales con recompensas de item, cooldown y captura por tiempo.
- Ranking de bandas y jugadores por influencia acumulada.
- API de solo lectura/escritura (`exports`) para que otros recursos consulten o modifiquen influencia sin duplicar lógica.

## Requisitos y Dependencias

`nexus_territories` **no declara ningún bloque `dependencies {}`** en su
`fxmanifest.lua`: arranca de forma aislada y nunca falla por falta de otro
recurso `nexus_*`. Sin embargo, para operar con normalidad necesita lo
siguiente:

### Requeridas para funcionar (no son `nexus_*`, siempre deben estar presentes)

| Recurso | Uso |
|---|---|
| `ox_lib` | Notificaciones, contexto de menú, callbacks (`lib.callback`) |
| `oxmysql` | Persistencia de zonas, influencia, logs y graffiti |
| `qbx_core` | Identidad de jugador (`GetPlayer`, `citizenid`) — verificado en runtime, degrada sin crashear si falta |

### Integraciones blandas (`GetResourceState`, opcionales)

| Recurso | Efecto si está ausente |
|---|---|
| **`nexus_bridge`** | El rate limit de comandos/acciones pasa a **fail-closed** (bloquea en vez de permitir sin límite) — sigue protegido, solo pierde el bucket configurable de `nexus_bridge`. |
| **`nexus_permissions`** | **Todas** las acciones administrativas y el editor de zonas quedan completamente bloqueadas para jugadores reales (solo el propio server console, `source == 0`, conserva acceso). El campo `adminAce` de `config.lua` existe mas no se usa en código — el control de acceso real de este recurso es 100% vía `nexus_permissions`, no ACE. **Para vender/instalar `nexus_territories` de forma standalone con panel de administración funcional, `nexus_permissions` es obligatorio en la práctica**, aunque el recurso arranque sin él. |
| `nexus_gangs` | Sin él, el nombre de banda se obtiene del `PlayerData.gang` nativo de QBox en lugar de la gestión de rangos/permisos propia de NEXUS — sigue funcionando, con menos granularidad. |
| `ox_inventory` | Requerido solo para pintar/quitar graffiti con item físico (`nexus_spraycan`, `nexus_graffiti_remover`); si no está disponible se notifica error controlado, no crashea. |
| `nexus_ui` | Si está iniciado, la NUI hereda el design system compartido; si no, usa sus propios estilos por defecto. |

## Instalación

1. Copia la carpeta `nexus_territories` a `resources/[custom]/`.
2. Añade en `server.cfg`:
   ```cfg
   ensure nexus_territories
   ```
   Colócalo **después** de `ox_lib`, `oxmysql` y `qbx_core`, y después de
   `nexus_permissions`/`nexus_gangs`/`nexus_bridge` si vas a usarlos (el orden
   solo importa para que las integraciones blandas se detecten desde el
   primer arranque; si se inician después, `nexus_territories` las detecta en
   la siguiente llamada sin necesidad de reiniciarlo).
3. Registra los items `nexus_spraycan` y `nexus_graffiti_remover` en
   `ox_inventory/data/items.lua` si vas a usar graffiti.
4. **SQL:** no requiere importar ningún archivo — las tablas
   (`nexus_territory_influence`, `nexus_territory_logs`,
   `nexus_territory_zones`, `nexus_territory_graffiti`) se crean
   automáticamente con `CREATE TABLE IF NOT EXISTS` en el primer arranque del
   recurso (`server/database.lua`, hook `onResourceStart`).
5. Ajusta las zonas por defecto en `config/config.lua` (`zones`) a las
   coordenadas de tu mapa, o bórralas y crea las tuyas con
   `/territoryeditor` una vez el recurso esté corriendo.

## Configuración (`config.lua`)

| Clave | Descripción |
|---|---|
| `command` / `editorCommand` | Comando para abrir el panel de territorios (`/territorios`) y el editor de zonas (`/territoryeditor`). |
| `rateLimitBucket` | Bucket de `nexus_bridge` usado para limitar acciones repetidas. |
| `control.minimumInfluence` | Influencia mínima para que una banda controle una zona. |
| `control.contestedGap` | Diferencia mínima sobre el segundo lugar para evitar estado "disputada". |
| `control.independentKey` | Clave usada cuando un jugador no tiene banda real (`independent`) — nunca puede sumar/controlar influencia. |
| `decay.*` | Activa/desactiva y parametriza la pérdida periódica de influencia. |
| `benefits.*` | Porcentajes de descuento/cooldown/bonus/heat que consumen `nexus_blackmarket`, `nexus_contracts` y `nexus_crafting` cuando una zona está controlada. |
| `editor.defaultRadius` / `minimumRadius` / `maximumRadius` | Límites del editor de zonas in-game. |
| `graffiti.*` | Item de pintado/removido, influencia por acción, límite de marcas activas por banda/zona, distancias de interacción/dibujo y duración de la animación. |
| `airdrop.*` | Activación, comando, ventana activa, cooldown, distancia/duración de captura, modelo del prop y tabla de recompensas. |
| `zones` | Mapa de zonas por defecto (`id = { label, coords, radius, heatMultiplier }`); puedes dejarlo vacío y crear todo desde el editor in-game. |

## Exportaciones y Eventos

### Exports de servidor (para que otros recursos consulten/modifiquen territorios)

```lua
exports.nexus_territories:addInfluence(source, zoneId, amount, reason)
exports.nexus_territories:addInfluenceAtCoords(source, coords, amount, reason)
exports.nexus_territories:getZoneState(zoneId)
exports.nexus_territories:getZoneAtCoords(coords)
exports.nexus_territories:getControlContext(source, coords)
exports.nexus_territories:getDashboardZones()
exports.nexus_territories:getActiveAirdrop()
```

`addInfluence`/`addInfluenceAtCoords` rechazan sumar influencia a jugadores
sin banda real (devuelven `false, 'no_real_gang'`) — este es el punto donde
otros recursos (`nexus_contracts`, `nexus_blackmarket`, `nexus_crafting`)
reportan sus acciones ilegales completadas.

### Exports de cliente

```lua
exports.nexus_territories:openTerritories()
exports.nexus_territories:openTerritoryEditor()
```

### Callbacks de servidor (`lib.callback`, consumidos por la NUI propia)

`nexus_territories:server:getGraffiti`, `...:getAirdrop`,
`...:getEditorZones`, `...:getRankings`, `...:getZones`.

### Eventos de servidor (`RegisterNetEvent`, disparados desde cliente)

`...:server:saveZone`, `...:server:deleteZone`, `...:server:sprayGraffiti`,
`...:server:removeGraffiti`, `...:server:adminRemoveGraffiti`,
`...:server:adminAddNearbyInfluence`, `...:server:adminAddZoneInfluence`,
`...:server:claimAirdrop`.

### Eventos de cliente (para integrarte desde otro recurso)

`...:client:open`, `...:client:openEditor`, `...:client:zonesUpdated`,
`...:client:graffitiUpdated`, `...:client:setAirdrop`, `...:client:useSpray`,
`...:client:useGraffitiRemover`.

## Comandos y Permisos

| Comando | Quién | Nota |
|---|---|---|
| `/territorios` | Cualquier jugador | Abre el panel de zonas/influencia/ranking. |
| `/territoryeditor` | Requiere `nexus_permissions.nexus_territories.editor_view` | Sin `nexus_permissions` corriendo, nadie (salvo consola) puede abrirlo. |
| `/spray` | Cualquier jugador con `nexus_spraycan` en inventario | Pinta graffiti en la pared que mira la cámara. |
| `/cleangraffiti` | Cualquier jugador con `nexus_graffiti_remover` | Elimina la marca más cercana propia/de su banda según reglas de zona. |
| `/graffitirefresh` | Cualquier jugador | Refresca el render local de marcas. |
| `/graffitiadminclean` | Requiere `nexus_permissions.nexus_territories.graffiti_admin` | Elimina cualquier marca cercana sin gastar item. |
| `/territoryairdrop [zona]` | Requiere `nexus_permissions.nexus_territories.airdrop_admin` | `airdrop.adminOnly = true` por defecto en config. |
| `/airdroprefresh` | Cualquier jugador | Refresca el estado del airdrop activo en cliente. |

Los permisos de guardado/eliminado de zona (`zone_save`, `zone_delete`) y de
otorgamiento manual de influencia (`influence_grant`) se validan en los
eventos correspondientes, no en comandos de texto — se accede a ellos desde
la NUI del editor y desde el panel de administración de `nexus_menu`.

**Nodos de permiso completos que debe declarar tu integración de
`nexus_permissions`:**

```text
nexus_territories.editor_view
nexus_territories.zone_save
nexus_territories.zone_delete
nexus_territories.graffiti_admin
nexus_territories.influence_grant
nexus_territories.airdrop_admin
```
