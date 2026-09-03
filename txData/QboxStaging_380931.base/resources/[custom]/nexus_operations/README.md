# nexus_operations

Operaciones de banda NEXUS: misiones de suministro (recoger/entregar paquete)
y extorsión, con rutas aleatorias por operación, riesgo/influencia
modificados por control territorial, y recompensas para el jugador y/o el
stash de la banda.

## Descripción general

`nexus_operations` define un catálogo fijo de operaciones (`config.lua`), de
tipo `supply` (recoger un paquete físico en un punto y entregarlo en otro,
con el item `nexus_contract_package` como prueba física en el inventario) o
`extortion` (cobrar en un único punto). Cada operación puede tener varias
`routes` — el servidor elige una al azar al iniciar, cada una con su propio
modificador de riesgo e influencia — y un requisito de rango de banda y
reputación criminal. Cada paso físico (recogida, entrega, cobro) pasa por un
sistema de "acción cronometrada" (timed action) que evita que el cliente
dispare el evento de finalización antes de que transcurra la duración real de
la animación/escena. Al completarse, la operación paga al jugador
(cash/XP/reputación), opcionalmente deposita recompensas en el stash de la
banda, aporta influencia a la zona de `nexus_territories` asociada y tiene
una probabilidad de alertar a la policía.

Funcionalidades clave:

- Dos tipos de operación (`supply`/`extortion`) con rutas aleatorias, cooldown por banda y expiración (`durationSeconds`) que fuerza a completar la operación a tiempo o perderla.
- Sistema de timed actions con token de un solo uso por etapa (`pickup`/`dropoff`/`extort`), consumido en el servidor tras verificar duración mínima transcurrida — no confía en el timer del cliente.
- Riesgo e influencia ajustados por el estado de la zona territorial asociada: bonus de riesgo/influencia si la zona es rival o disputada, reducción de riesgo si la banda propia la controla.
- Fallback de seguridad vendorizado (`server/security_fallback.lua`) que reemplaza rate limit y timed actions de `nexus_bridge` cuando este no está disponible, en vez de bloquear o dejar sin límite.

## Requisitos y Dependencias

`nexus_operations` **sí declara un bloque `dependencies {}`** en su
`fxmanifest.lua` — a diferencia de `nexus_blackmarket`, `nexus_labs` y
`nexus_laundering`, que no declaran ninguno:

```lua
dependencies {
    'ox_inventory',
}
```

### Dependencia dura (`fxmanifest.lua`)

| Recurso | Uso |
|---|---|
| `ox_inventory` | Manejo del item de paquete físico (`GetSlotsWithItem`, `CanCarryItem`, `AddItem`, `RemoveItem`) durante todo el ciclo de una operación `supply`. Al estar en `dependencies {}`, FiveM impide que `nexus_operations` arranque si `ox_inventory` no está presente. |

### Requeridas para funcionar (no son `nexus_*`, no están en `dependencies {}` pero deben estar presentes igualmente)

| Recurso | Uso |
|---|---|
| `ox_lib` | `lib.callback`, `lib.registerContext`/`lib.showContext`, `lib.showTextUI`, `lib.notify`/`lib.progressBar` de respaldo |
| `oxmysql` | Persistencia de logs y cooldowns por banda/operación |
| `qbx_core` | Identidad de jugador (`GetPlayer`, `citizenid`) — se verifica en runtime, degrada sin crashear si falta |

### Integraciones blandas (`GetResourceState`, opcionales)

| Recurso | Efecto si está ausente |
|---|---|
| **`nexus_bridge`** | A diferencia de los otros tres recursos NEXUS ilegales (que fallan cerrado sin más), `nexus_operations` trae un **fallback vendorizado** (`server/security_fallback.lua`, copia adaptada de `nexus_bridge/server/security.lua`, con hash documentado en cabecera) que replica localmente `rateLimit`, `beginTimedAction`, `consumeTimedAction` y `cancelTimedAction` usando `NexusOperationsConfig.security`. Si `nexus_bridge` no está corriendo, este fallback se activa automáticamente (con un aviso de consola una sola vez) y el recurso sigue funcionando con rate limit y tokens de acción física aislados a esta instancia, en vez de bloquear o quedar sin límite. |
| `nexus_gangs` | Sin él, la banda/rango del jugador se obtiene de `PlayerData.gang` nativo de QBox; y las recompensas de tipo `stash` no pueden depositarse (`getPrimaryStashId` no existe) — `completeOperation` responde con error y no completa la operación si la operación tiene recompensas de stash configuradas. |
| `nexus_progression` | Sin él, `getProgress` devuelve `{}` (reputación criminal 0) — las operaciones con `minCriminalReputation > 0` quedan inaccesibles, y no se otorga XP/reputación tras completar. |
| `nexus_territories` | Sin él, `getZoneState` devuelve `nil` — no hay ajuste de riesgo/influencia por control territorial (`territorialModifiers` devuelve `0, 0, 'neutral'`), y completar una operación no aporta influencia a la zona. |
| `nexus_dispatch` | Sin él, `sendDispatchAlert` no hace nada — la alerta policial sigue llegando por `TriggerClientEvent` directo a jugadores con `job` policial, solo se pierde la integración con el sistema de despacho. |
| `nexus_scene_core` | Si está iniciado y `sceneCore.enabled` no es `false`, cada etapa física usa `exports.nexus_scene_core:play`; si no, cae en `lib.progressBar` de `ox_lib` con animación genérica. |
| `nexus_ui` | Si está iniciado, las notificaciones del cliente usan `exports.nexus_ui:notify`; si no, cae en `lib.notify`. |

**Este recurso no tiene ninguna integración con `nexus_permissions`** (no hay
ninguna llamada a `hasPermission`/`hasAnyPermission` en todo el código). No
existe ningún bypass administrativo de rango, reputación o cooldown.

## Instalación

1. Copia la carpeta `nexus_operations` a `resources/[custom]/`. Asegúrate de
   que `ox_inventory` esté instalado y arrancando antes — es dependencia
   dura declarada en `fxmanifest.lua`, el recurso no arranca sin él.
2. Añade en `server.cfg`:
   ```cfg
   ensure nexus_operations
   ```
   Según el orden de arranque validado de la suite NEXUS, `nexus_operations`
   va **después** de `nexus_contracts` y **antes** de `nexus_labs`:
   ```
   ..., nexus_blackmarket, nexus_contracts, nexus_operations, nexus_labs, nexus_laundering, nexus_menu
   ```
   Arranca después de `nexus_territories`, `nexus_gangs`, `nexus_progression`,
   `nexus_dispatch`, `nexus_scene_core` y, si vas a usarlo, `nexus_bridge`
   (opcional en la práctica gracias al fallback vendorizado, pero recomendado
   para compartir buckets de rate limit con el resto de la suite).
3. **SQL:** no requiere importar ningún archivo — este recurso **no incluye
   una carpeta `sql/`** (a diferencia de `nexus_blackmarket`/`nexus_labs`/
   `nexus_laundering`, que sí traen un `install.sql` de referencia). Las
   tablas (`nexus_operation_logs`, `nexus_operation_cooldowns`) se crean
   automáticamente con `CREATE TABLE IF NOT EXISTS` en el primer arranque del
   recurso (`server/database.lua`, hook `onResourceStart`).
4. Registra el item `nexus_contract_package` (o el que configures en
   `supplyPackageItem`) y los items de recompensa de stash
   (`metalscrap`, `plastic`, `nexus_spraycan`, etc.) en
   `ox_inventory/data/items.lua`.
5. Si modificas la lógica de negocio del fallback de seguridad, edita primero
   el canónico en `nexus_bridge/server/security.lua`, re-vendoriza y
   actualiza el hash documentado en la cabecera de
   `server/security_fallback.lua`; valida con `test/verify_security_fallback.lua`
   y `test/verify_vendored_hash.sh` antes de publicar una release.

## Configuración (`config.lua`)

| Clave | Descripción |
|---|---|
| `debug` | Existe en config pero **no se referencia en ningún otro archivo del recurso** — flag muerto, no activa logging adicional. |
| `command` | Comando para abrir el panel de operaciones (`/operations`). |
| `rateLimitBucket` | Bucket de `nexus_bridge` (o del fallback local) usado para limitar acciones repetidas. |
| `interactDistance` | Distancia de interacción con puntos de recogida/entrega/cobro. |
| `abandonCooldownSeconds` | Cooldown aplicado a la banda cuando una operación expira o se cancela sin completarse. |
| `security.*` | **Solo la usa `server/security_fallback.lua`** cuando `nexus_bridge` no está corriendo — límites de rate limit y ventanas de timed action en paridad con `nexus_bridge/config/config.lua`, para que el fallback se comporte igual que el módulo compartido. |
| `policeJobs` | Tabla de `job` que reciben la alerta policial al completar una operación. |
| `actionDurations.*` | Duración de las escenas físicas de `pickup`, `deliver` y `extort`. |
| `sceneCore.*` | Activa la integración con `nexus_scene_core` y mapea cada etapa a un id de escena. |
| `supplyPackageItem` | Item de inventario usado como prueba física del paquete de suministro en curso. |
| `npcDefaults.*` | Modelo/escenario de PNJ por defecto para cada tipo de operación, usado si la ruta elegida no define su propio `npc`. |
| `operations.*` | Cada operación: label, tipo, descripción, rango/reputación mínimos, zona de `nexus_territories`, coordenadas base (`pickup`/`dropoff`/`point`), lista de `routes` (cada una con su propio modificador de riesgo/influencia y NPC), duración, cooldown, probabilidad de alerta policial, influencia base y recompensas (`rewards.stash` / `rewards.player`). |

## Exportaciones y Eventos

### Exports de servidor

```lua
exports.nexus_operations:getDashboardOperations(source)
exports.nexus_operations:getDashboardOperationsLite(source)
exports.nexus_operations:getDashboardOperationLogs(source)
```

### Exports de cliente

```lua
exports.nexus_operations:openOperations()
```

### Callbacks de servidor (`lib.callback.register`)

```lua
nexus_operations:server:getOperations
nexus_operations:server:prepareAction
```

### Eventos de servidor (`RegisterNetEvent`)

```lua
nexus_operations:server:start
nexus_operations:server:pickup
nexus_operations:server:deliver
nexus_operations:server:extort
nexus_operations:server:cancelPreparedAction
nexus_operations:server:cancel
```

### Eventos de cliente (`RegisterNetEvent`)

```lua
nexus_operations:client:setActive
nexus_operations:client:clearActive
nexus_operations:client:policeAlert
```

## Comandos y Permisos

| Comando | Quién | Nota |
|---|---|---|
| `/operations` | Cualquier jugador | Abre el panel de operaciones; cada operación se bloquea/desbloquea según pertenencia a banda, rango, reputación criminal y cooldown propio de la banda. |

**Este recurso no está enrutado por `nexus_permissions` en absoluto** — no
declara ni consume ningún nodo de permiso, no hay comandos administrativos,
y no hay gate por ACE. El único control de acceso es el que ya aplica a
cualquier jugador (pertenencia a banda, rango, reputación criminal y
cooldown). Si necesitas un bypass administrativo para este recurso tendrás
que añadirlo tú — no existe en el código actual.
