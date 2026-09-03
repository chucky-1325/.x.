# nexus_bridge

Capa técnica compartida del stack NEXUS: rate limiting por bucket, acciones
temporizadas anti-cheat (`beginTimedAction`/`consumeTimedAction`), un check
de acceso por job/gang (`hasAccess`) y helpers de identidad/tema que otros
`nexus_*` consumen en vez de reimplementar su propio rate limit o su propia
validación de "¿cuánto tiempo lleva jugando esta animación?".

## Descripción general

`nexus_bridge` no tiene UI ni base de datos propia: es una librería de
funciones de servidor y cliente expuestas por `exports`. El bloque más
importante es el sistema de acciones temporizadas — `beginTimedAction` emite
un token de un solo uso con una duración acotada
(`timedActions.minimumDuration`/`maximumDuration`), y `consumeTimedAction`
rechaza el token si se reclama demasiado pronto (`too_early`, con un margen
de tolerancia `earlyToleranceMs`), si ya expiró (`expired`), o si el
`subject`/token no coincide — esto es lo que impide que un cliente modificado
dispare el evento de "acción completada" sin esperar la duración real. El
segundo bloque es `NexusRateLimit`, un limitador de ventana deslizante por
`(source, bucket)` con buckets nombrados en `config/config.lua`
(`default`, `tablet`, `crafting`, `admin`, `laundering`, `labs`). El tercer
bloque, `hasAccess`, evalúa si un jugador pertenece a un
`permissionGroups` (por `jobTypes`, `jobs` con grado mínimo, o `gangs` con
grado mínimo) — es un check de **rol de gameplay** (policía/EMS/gobierno),
no del sistema RBAC de `nexus_permissions`.

## Requisitos y Dependencias

`nexus_bridge` **no declara ningún bloque `dependencies {}` ni `dependency`**
en su `fxmanifest.lua`.

### Hallazgo: dependencia dura no declarada

`shared_scripts` incluye `'@ox_lib/init.lua'` de forma incondicional. Esta es
una referencia cross-resource (`@ox_lib/...`) — si `ox_lib` no está
iniciado, FXServer no puede resolver ese archivo y **`nexus_bridge` falla al
arrancar por completo**, aunque el manifiesto no lo liste como dependencia.
En la práctica, `ox_lib` es una dependencia dura de este recurso; solo que no
está declarada donde debería. En código, el único uso real de `lib` está
guardado (`client/main.lua`: `if lib and lib.notify then`), pero eso no evita
el fallo de arranque si el archivo `@ox_lib/init.lua` no se puede cargar.

### Integraciones blandas (`GetResourceState`, opcionales)

| Recurso | Efecto si está ausente |
|---|---|
| `qbx_core` | `hasAccess` y `getPlayerData` (server) devuelven `false`/`nil` de forma controlada — `NexusHasAccess` nunca puede conceder acceso sin datos de jugador reales. |
| `qbx_identity_aaa` | `getIdentity`/`getTheme` (server y cliente) devuelven `nil`/`{}` en vez de crashear. Sin este recurso, cualquier `nexus_*` que pida tema/identidad vía `nexus_bridge` recibe un objeto vacío y debe usar sus propios valores por defecto. |

## Instalación

1. Copia la carpeta `nexus_bridge` a `resources/[custom]/`.
2. **SQL: no aplica.** No se encontró ningún archivo `server/database.lua`,
   ninguna carpeta `sql/`, ni una sola sentencia `CREATE TABLE` en todo el
   recurso — `nexus_bridge` no usa base de datos, todo su estado (buckets de
   rate limit, acciones temporizadas) vive en memoria del proceso y se
   pierde en cada reinicio del recurso (por diseño: no hay nada que
   persistir).
3. Añade en `server.cfg`:
   ```cfg
   ensure ox_lib
   ensure nexus_bridge
   ```
   `nexus_bridge` va **primero** en el stack NEXUS —- es la base técnica de
   la que dependen (formal o informalmente, vía `exports`) prácticamente
   todos los demás `nexus_*`:
   ```
   nexus_bridge, nexus_permissions, nexus_ui, nexus_scene_core, nexus_ems, nexus_tablet,
   nexus_progression, nexus_dispatch, nexus_gangs, nexus_territories, nexus_dutyboard,
   nexus_crafting, nexus_blackmarket, nexus_contracts, nexus_operations, nexus_labs,
   nexus_laundering, nexus_menu
   ```
4. Ajusta `config/config.lua` — en particular los buckets de `rateLimits` si
   vas a vender `nexus_laundering` o `nexus_labs` por separado, ya que ambos
   referencian buckets propios (`laundering`, `labs`) que deben existir aquí
   o caen en el bucket `default`, mucho más permisivo.

## Configuración (`config.lua`)

| Clave | Descripción |
|---|---|
| `debug` | Activa logs adicionales vía `NexusBridgeUtils.log`. |
| `rateLimits.<bucket>` | `{ window, limit }` por bucket — ventana en ms y número máximo de llamadas permitidas dentro de esa ventana, consultado por `NexusRateLimit(source, bucket)`. Si un recurso pide un bucket que no existe aquí, cae silenciosamente en `default` (8 llamadas/10 s) — ya ocurrió con `laundering` y `labs` antes de añadirse explícitamente, según los comentarios del propio archivo. |
| `timedActions.minimumDuration` / `maximumDuration` | Rango en el que se acota cualquier duración pedida a `beginTimedAction`, sin importar lo que pida el llamador. |
| `timedActions.graceMs` | Tiempo extra tras `duration` antes de que el token expire (margen para latencia/lag del cliente). |
| `timedActions.earlyToleranceMs` | Margen de tolerancia bajo el cual `consumeTimedAction` aún acepta un reclamo "casi a tiempo" en vez de rechazarlo como `too_early`. |
| `permissionGroups.<grupo>.jobTypes` | Tipos de job (`leo`, etc.) que conceden acceso al grupo sin importar el nombre exacto del job. |
| `permissionGroups.<grupo>.jobs` | Mapa `job = gradoMinimo` — acceso si el grado del jugador es ≥ al mínimo. |
| `permissionGroups.<grupo>.gangs` | Mismo criterio que `jobs`, pero para bandas nativas de QBox. |

## Exportaciones y Eventos

### Exports de servidor

```lua
exports.nexus_bridge:rateLimit(source, bucket)
exports.nexus_bridge:beginTimedAction(source, scope, subject, durationMs)
exports.nexus_bridge:consumeTimedAction(source, scope, subject, token)
exports.nexus_bridge:cancelTimedAction(source, scope, token)
exports.nexus_bridge:hasAccess(source, permissionGroup)
exports.nexus_bridge:getPlayerData(source)
exports.nexus_bridge:getIdentity()
exports.nexus_bridge:getTheme()
```

### Exports de cliente

```lua
exports.nexus_bridge:getIdentity()
exports.nexus_bridge:getTheme()
exports.nexus_bridge:notify(data)
```

### Callbacks de servidor (`lib.callback.register`)

No se encontró ningún `lib.callback.register` en este recurso.

### Eventos de servidor (`RegisterNetEvent`)

`nexus_bridge:server:securityFlag` (constante `NexusBridge.events.securityFlag`)
— recibe un `reason` de texto desde el cliente, lo pasa por rate limit
(`bucket = 'default'`) y lo registra como advertencia; no ejecuta ninguna
acción de gameplay, es solo logging de seguridad.

### Eventos de cliente

No se encontró ningún `RegisterNetEvent` en `client/main.lua`.

## Comandos y Permisos

**No hay comandos (`RegisterCommand`) en este recurso.** Toda su superficie
es `exports` y un único evento de servidor. En consecuencia tampoco hay
ningún nodo de `nexus_permissions` ni chequeo `IsPlayerAceAllowed` en
`nexus_bridge` — el control de acceso (`hasAccess`) que expone es un filtro
de gameplay por job/gang, no un gate administrativo, y queda a criterio del
recurso que lo consuma decidir qué hacer con el resultado.
