# nexus_labs

Laboratorios ilegales de banda para NEXUS: producción con receta fija por
laboratorio, mejoras de nivel, mantenimiento/condición, sabotaje entre bandas
rivales y control territorial vía `nexus_territories`.

## Descripción general

`nexus_labs` expone un set fijo de laboratorios (`config.lua`), cada uno con
un tipo (`meth`/`packaging`/`weed`), una receta de producción, un riesgo base
y una zona de `nexus_territories` asociada. Solo miembros de una banda real
pueden operarlos: el acceso depende del rango de banda, la reputación
criminal y, si la zona está bajo control de otra banda, de la influencia
propia acumulada en ella. Cada laboratorio tiene nivel (mejorable con
cash+materiales), condición (que decae con el uso y se repara con
mantenimiento) y cooldown por banda. La producción completada deposita en el
stash de banda si `nexus_gangs` está disponible, otorga XP/reputación
criminal, aporta influencia territorial y tiene una probabilidad de alertar a
la policía que escala con el riesgo efectivo del laboratorio.

Funcionalidades clave:

- Producción, mejora de nivel (hasta `upgrades.maxLevel`), reparación de condición y sabotaje contra laboratorios rivales, cada uno con su propia escena física y cooldown/duración.
- Riesgo efectivo por laboratorio calculado a partir de `baseRisk`, nivel, condición y estado territorial (controlado propio, disputado, controlado rival).
- Bypasses administrativos independientes para progresión, requisito territorial y requisito de sabotaje, cada uno con su propio nodo de `nexus_permissions`.
- Log persistente por banda de producción, mejoras, reparaciones y sabotajes.

## Requisitos y Dependencias

`nexus_labs` **no declara ningún bloque `dependencies {}`** en su
`fxmanifest.lua` — arranca aislado y no falla si ningún otro recurso
`nexus_*` está presente.

### Requeridas para funcionar (no son `nexus_*`, siempre deben estar presentes)

| Recurso | Uso |
|---|---|
| `ox_lib` | `lib.callback`, `lib.registerContext`/`lib.showContext`, `lib.showTextUI`, `lib.notify`/`lib.progressBar` de respaldo |
| `oxmysql` | Persistencia de logs, cooldowns y estado (nivel/condición/cola) por banda y laboratorio |
| `qbx_core` | Identidad de jugador (`GetPlayer`, `citizenid`) — se verifica en runtime, degrada sin crashear si falta |
| `ox_inventory` | Consumo de inputs de receta, entrega de outputs, pago de mejoras/reparaciones/sabotaje — sin él, `hasInputs`/`canPayUpgrade`/`canPayCost`/`addOutputs` devuelven `false` y ninguna acción puede completarse |

### Integraciones blandas (`GetResourceState`, opcionales)

| Recurso | Efecto si está ausente |
|---|---|
| **`nexus_permissions`** | `hasProgressionBypass`, `hasTerritoryBypass` y `hasSabotageBypass` (nodos `nexus_labs.progression_bypass`, `nexus_labs.territory_bypass`, `nexus_labs.sabotage_bypass`) devuelven siempre `false` para jugadores reales — solo la consola (`source == 0`) conserva el bypass. Sin `nexus_permissions`, todos los jugadores quedan sujetos a los requisitos normales de rango/reputación/territorio/reputación de sabotaje. |
| **`nexus_bridge`** | El rate limit de todas las acciones (`getLabs`, `produce`, `upgrade`, `repair`, `sabotage`) pasa a **fail-closed**: si `nexus_bridge` no está corriendo, `rateLimit()` devuelve `false` y bloquea la acción en vez de dejarla sin límite. |
| `nexus_territories` | Sin él, `getZoneState` devuelve `nil` — no hay penalización/bonificación de riesgo por control de zona, el requisito de influencia mínima para operar en zona ajena (`production.minimumInfluence`) no se evalúa, y la producción/sabotaje no aportan influencia territorial. |
| `nexus_gangs` | Sin él, la banda/rango del jugador se obtiene de `PlayerData.gang` nativo de QBox; y `depositToGangStash` no puede depositar en stash de banda (`getPrimaryStashId` no existe), por lo que la producción cae al inventario del jugador directamente. |
| `nexus_progression` | Sin él, `getProgress` devuelve `{}` (reputación criminal 0) — los laboratorios con `minCriminalReputation > 0` quedan inaccesibles sin bypass, y no se otorga XP/reputación tras producir. |
| `nexus_dispatch` | Sin él, `sendDispatchAlert` no hace nada — la alerta policial sigue llegando por `TriggerClientEvent` directo a jugadores con `job` policial, solo se pierde la integración con el sistema de despacho. |
| `nexus_scene_core` | Si está iniciado y `sceneCore.enabled` no es `false`, la animación de producción/mejora/reparación/sabotaje usa `exports.nexus_scene_core:play`; si no, cae en `lib.progressBar` de `ox_lib` con animación genérica. |
| `nexus_ui` | Si está iniciado, las notificaciones del cliente usan `exports.nexus_ui:notify`; si no, cae en `lib.notify`. |

## Instalación

1. Copia la carpeta `nexus_labs` a `resources/[custom]/`.
2. Añade en `server.cfg`:
   ```cfg
   ensure nexus_labs
   ```
   Según el orden de arranque validado de la suite NEXUS, `nexus_labs` va
   **después** de `nexus_operations` y **antes** de `nexus_laundering`:
   ```
   ..., nexus_blackmarket, nexus_contracts, nexus_operations, nexus_labs, nexus_laundering, nexus_menu
   ```
   Arranca después de `nexus_territories`, `nexus_permissions`, `nexus_gangs`,
   `nexus_progression`, `nexus_dispatch`, `nexus_scene_core` y `nexus_bridge`
   para que las integraciones blandas se detecten desde el primer arranque
   (si se inician después, se detectan en la siguiente llamada sin reiniciar
   `nexus_labs`).
3. **SQL:** no requiere importar ningún archivo — las tablas
   (`nexus_lab_logs`, `nexus_lab_cooldowns`, `nexus_lab_state`) se crean
   automáticamente con `CREATE TABLE IF NOT EXISTS` en el primer arranque del
   recurso (`server/database.lua`, hook `onResourceStart`). El repo incluye
   además `sql/install.sql` con la misma definición como referencia/import
   manual opcional; no hace falta ejecutarlo para que el recurso funcione.
4. Registra los items de receta e insumos de mejora/mantenimiento/sabotaje
   (`plastic`, `glass`, `metalscrap`, `electronickit`, `steel`, `lockpick`,
   `meth`, `cokebaggy`, `weed_brick`, etc.) en `ox_inventory/data/items.lua`.
5. Ajusta `labs`, `upgrades`, `maintenance` y `sabotage` en
   `config/config.lua` a tu mapa, recetas y economía.

## Configuración (`config.lua`)

| Clave | Descripción |
|---|---|
| `command` | Comando para abrir el panel de laboratorios (`/labs`). |
| `rateLimitBucket` | Bucket de `nexus_bridge` usado para limitar acciones repetidas. |
| `interactDistance` | Distancia de interacción con el prop del laboratorio. |
| `adminAce` | **Dead config.** No se referencia en ningún otro archivo del recurso — el control de acceso administrativo real pasa por los tres bypasses de `nexus_permissions`, no por ACE. |
| `policeJobs` | Tabla de `job` que reciben la alerta policial al producir/sabotear. |
| `sceneCore.*` | Activa la integración con `nexus_scene_core` y mapea cada acción (`production` por tipo de laboratorio, `upgrade`, `repair`, `sabotage`) a un id de escena. |
| `production.*` | Duración base, cooldown, influencia mínima requerida en zona ajena, si solo el dueño de la zona puede producir, y si el output va al stash de banda. |
| `upgrades.*` | Activación, duración, nivel máximo, reducción de duración/riesgo por nivel, bonus de output por nivel, desgaste de condición por producción, y coste (cash + materiales) de cada nivel. |
| `maintenance.*` | Activación, duración, cantidad de condición reparada y coste (cash + materiales). |
| `sabotage.*` | Activación, rango mínimo, reputación criminal mínima, daño a la condición rival, duración, probabilidad de alerta policial, influencia otorgada y materiales consumidos. |
| `labs.*` | Cada laboratorio: label, tipo, zona de `nexus_territories`, coordenadas/modelo del prop, rango/reputación mínimos, riesgo base, influencia otorgada y receta (`inputs`/`outputs`/`xp`/`reputation`). |

## Exportaciones y Eventos

### Exports de servidor

```lua
exports.nexus_labs:getDashboardLabs(source)
```

### Exports de cliente

```lua
exports.nexus_labs:openLabs()
```

### Callbacks de servidor (`lib.callback.register`)

```lua
nexus_labs:server:getLabs
```

### Eventos de servidor (`RegisterNetEvent`)

```lua
nexus_labs:server:produce
nexus_labs:server:upgrade
nexus_labs:server:repair
nexus_labs:server:sabotage
```

### Eventos de cliente (`RegisterNetEvent`)

```lua
nexus_labs:client:startScene
nexus_labs:client:startProgress
nexus_labs:client:policeAlert
```

## Comandos y Permisos

| Comando | Quién | Nota |
|---|---|---|
| `/labs` | Cualquier jugador | Abre el panel de laboratorios; cada laboratorio individual se bloquea/desbloquea según banda, rango, reputación, territorio y cooldown. |

Este recurso **no tiene comandos administrativos ni gate de tipo ACE**. El
control de acceso administrativo son tres bypasses independientes de
`nexus_permissions` (comentado explícitamente en el código: cada uno cubre un
requisito distinto y **ninguno** afecta a los demás — en particular, el
requisito de rango del propio sabotaje nunca tiene bypass, solo su requisito
de reputación criminal):

```text
nexus_labs.progression_bypass
nexus_labs.territory_bypass
nexus_labs.sabotage_bypass
```

Sin `nexus_permissions` corriendo, ningún jugador (salvo la consola,
`source == 0`) tiene estos bypasses.
