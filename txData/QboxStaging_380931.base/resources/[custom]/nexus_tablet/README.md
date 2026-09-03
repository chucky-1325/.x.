# nexus_tablet

Shell modular de tablet operativa para QBox/OX: hub NUI que centraliza el
acceso a policia, EMS, red clandestina y empresas, y sirve de punto de
lanzamiento hacia el resto de recursos `nexus_*`.

## Descripción general

`nexus_tablet` es una **shell**, no un sistema con lógica de negocio propia:
define un conjunto de "apps" (`shared/apps.lua`) que se abren con un comando
de teclado (`F7` / `/tablet`), resuelve si el jugador tiene acceso a cada una,
y delega el contenido real a otros recursos, ya sea abriendo su UI (`qbx_mdt`,
`nexus_contracts`, `nexus_gangs`, `nexus_operations`, `nexus_labs`,
`nexus_laundering`, `nexus_blackmarket`, `nexus_territories`,
`nexus_crafting`) o agregando datos de varios de ellos en un único payload
("dashboard") para la app `illegal` (Red Clandestina), la única que renderiza
contenido propio en la NUI (`html/`).

El resto de apps declaradas (`ems`, `illegal`, `business`) están marcadas
`status = 'planned'` salvo `illegal`, que es la única con lógica de dashboard
funcional; `police` no tiene dashboard propio, abre `qbx_mdt` directamente vía
export externo. `nexus_tablet` no persiste nada en base de datos: es
enteramente un agregador en tiempo de ejecución sobre exports de otros
recursos, con fallback local (dashboard vacío) si alguno no responde o no
está iniciado.

## Requisitos y Dependencias

`nexus_tablet` **no declara ningún bloque `dependencies {}`** en su
`fxmanifest.lua` — arranca aislado y nunca falla por falta de otro recurso.

### Requeridas para funcionar (no son `nexus_*`, siempre deben estar presentes)

| Recurso | Uso |
|---|---|
| `ox_lib` | `@ox_lib/init.lua` en `shared_scripts`; usado para `lib.callback.await` (cliente) y `lib.callback.register` (servidor) — sin él el resource falla al iniciar (script no encontrado), no es una integración opcional. |
| `qbx_core` | Identidad del jugador (`GetPlayer`, `citizenid`) — verificado en runtime vía `GetResourceState`; si falta, `getCitizenId` devuelve `nil` y el dashboard de progresión llega vacío, no crashea. |

### Integraciones blandas (`GetResourceState`, opcionales)

| Recurso | Efecto si está ausente |
|---|---|
| `nexus_permissions` | Los dos bypass administrativos (`bypass_illegal_access`, `bypass_app_restriction`) quedan **desactivados para todos salvo la consola** (`source == 0`); el resto de jugadores sigue las reglas normales de acceso por job/banda/reputación, no se bloquea nada adicional. |
| `nexus_bridge` | `rateLimit(source)` devuelve `false` (fail-closed: bloquea la acción) en vez de aplicar límite real — evita abuso ilimitado si `nexus_bridge` cae, pero también bloquea el acceso a apps con `access` definido hasta que vuelva a estar disponible; `canOpen` además exige `nexus_bridge` corriendo explícitamente para resolver `hasAccess(source, app.access)` en apps no ilegales — sin él, esas apps devuelven `no_access`/`bridge_missing`. |
| `nexus_progression` | `getProgress(source)` devuelve `{}` — el dashboard ilegal muestra nivel/reputación criminal y de crafting en 0 en vez de los valores reales. |
| `nexus_gangs` | Sin él, el nombre/rango de banda se obtiene del `PlayerData.gang` nativo de QBox en lugar de la gestión propia de NEXUS; además `assets`, `members` y `gangAudit` del dashboard ilegal quedan en sus valores por defecto (listas vacías). |
| `nexus_operations` | `operations` y `operationLogs` del dashboard ilegal quedan en sus valores por defecto (vacíos); la acción `operations` del menú notifica "Operaciones no iniciado." en vez de abrir la UI. |
| `nexus_labs` | `labs` del dashboard ilegal queda vacío; la acción `labs` notifica error en vez de abrir la UI. |
| `nexus_laundering` | `laundering` del dashboard ilegal queda vacío; la acción `laundering` notifica error en vez de abrir la UI. |
| `nexus_territories` | `territories` (zonas) y `airdrop` del dashboard ilegal quedan vacíos/`nil`; la acción `territories` notifica error en vez de abrir la UI. |
| `nexus_contracts` | La acción `contracts` del menú notifica "Contratos no iniciado." en vez de abrir la UI (el payload `contracts` del dashboard ilegal ya es un placeholder fijo `{ contracts = {}, active = nil }` en el propio código, independientemente de este recurso). |
| `nexus_blackmarket` | La acción `blackmarket` notifica "Mercado negro no iniciado." en vez de ejecutar `blackmarketnear`. |
| `nexus_crafting` | La acción `crafting` notifica "Crafting no iniciado." en vez de abrir `nexus_crafting:openCrafting('illegal_bench')`. |
| `nexus_ui` | Si está iniciado, las notificaciones usan su NUI compartida (`exports.nexus_ui:notify`); si no, cae a `lib.notify` de `ox_lib`. |
| `qbx_mdt` | App `police`: si no está `started`, `openExternal` devuelve `false` y la apertura de la tablet simplemente no hace nada (no hay fallback visual para el MDT). |

## Instalación

1. Copia la carpeta `nexus_tablet` a `resources/[custom]/`.
2. Añade en `server.cfg`:
   ```cfg
   ensure nexus_tablet
   ```
   Según el orden validado de arranque de este stack, `nexus_tablet` va
   **después** de `nexus_bridge`, `nexus_permissions`, `nexus_ui`,
   `nexus_scene_core` y `nexus_ems`, y **antes** de `nexus_progression` y el
   resto de sistemas de gameplay (`nexus_dispatch`, `nexus_gangs`,
   `nexus_territories`, `nexus_dutyboard`, `nexus_crafting`,
   `nexus_blackmarket`, `nexus_contracts`, `nexus_operations`, `nexus_labs`,
   `nexus_laundering`, `nexus_menu`):
   ```
   nexus_bridge, nexus_permissions, nexus_ui, nexus_scene_core, nexus_ems, nexus_tablet,
   nexus_progression, nexus_dispatch, nexus_gangs, nexus_territories, nexus_dutyboard,
   nexus_crafting, nexus_blackmarket, nexus_contracts, nexus_operations, nexus_labs,
   nexus_laundering, nexus_menu
   ```
   Arranca temprano porque es solo una shell de UI: no depende de datos de los
   sistemas de gameplay para iniciar, y como consume sus exports únicamente en
   el momento en que el jugador abre la app correspondiente (no al arrancar),
   el orden relativo con `nexus_gangs`, `nexus_territories`, `nexus_operations`,
   `nexus_labs`, `nexus_laundering`, `nexus_blackmarket`, `nexus_contracts` y
   `nexus_crafting` no es crítico — todos se resuelven vía `GetResourceState`
   en tiempo de uso.
3. **SQL:** `nexus_tablet` **no usa base de datos**. No hay `server/database.lua`
   ni tablas propias — es puramente un agregador de exports de otros recursos
   en tiempo de ejecución, no persiste nada. No se requiere ningún import SQL.

## Configuración (`config.lua`)

| Clave | Descripción |
|---|---|
| `command` | Comando de texto para abrir la tablet (`/tablet`); también usado como `RegisterKeyMapping` (tecla por defecto `F7`). |
| `defaultApp` | App que se abre si no se especifica argumento (`home`). |
| `illegalAccess.minimumCriminalReputation` | Reputación criminal mínima (de `nexus_progression`) que permite abrir la app `illegal` a un jugador sin banda. |
| `enabled` | **Dead/no usado** — no aparece referenciado en ningún archivo `.lua` del recurso fuera de `config.lua`; no activa ni desactiva nada en el código actual. |
| `adminAce` | **Dead/no usado** — no aparece referenciado en ningún archivo `.lua` del recurso; el control de acceso real es 100% vía `nexus_permissions` (bypasses) y jobs/reputación, no ACE. |
| `access.police` / `access.ems` / `access.illegal` / `access.business` / `access.gov` | **Dead/no usado como tabla** — el código nunca lee `NexusTabletConfig.access`; las claves de acceso reales están hardcodeadas como strings literales en `shared/apps.lua` (`access = 'police'`, `access = 'ems'`, etc.), que casualmente coinciden en nombre con esta tabla pero no la referencian. `access.gov` ni siquiera tiene una app equivalente en `shared/apps.lua`. |

`shared/apps.lua` (no es "config.lua" pero define el catálogo de apps) sí se
lee en su totalidad: cada entrada controla `label`, `variant` (tema visual),
`access` (string de job/flag requerido o `false` para acceso público),
`external` (resource+export a invocar en vez de abrir la app localmente) y
`status` (`'planned'` marca apps sin dashboard implementado todavía).

## Exportaciones y Eventos

### Exports de servidor

```lua
exports.nexus_tablet:canOpen(source, appId)
```

### Exports de cliente

```lua
exports.nexus_tablet:openTablet(appId)
exports.nexus_tablet:closeTablet()
```

### Callbacks de servidor (`lib.callback.register`)

```
nexus_tablet:server:canOpen
nexus_tablet:server:getIllegalDashboard
nexus_tablet:server:getIllegalFallback
```

### RegisterNetEvent

No se encontró ningún `RegisterNetEvent` en `server/` ni `client/`. La
comunicación cliente↔servidor de este recurso pasa exclusivamente por
`lib.callback` (arriba) y por `RegisterNUICallback` (mensajes NUI↔cliente,
`close` y `action`, que no son eventos de red).

## Comandos y Permisos

| Comando | Quién | Nota |
|---|---|---|
| `/tablet [app]` | Cualquier jugador | Abre la tablet en la app indicada (o `defaultApp` si se omite). El acceso real a cada app se resuelve en el callback `canOpen`, no en el comando. |

El gating de acceso por app **no usa ACE** en ningún punto (`adminAce` de
`config.lua` es dead code, ver sección de Configuración). El modelo real es:

- Apps con `access = false` (p. ej. `home`): acceso público, sin chequeo.
- Apps con `access` definido (`police`, `ems`, `business`): requieren
  `exports.nexus_bridge:hasAccess(source, app.access)` — si `nexus_bridge` no
  está iniciado, el acceso se deniega (`bridge_missing`).
- App `illegal`: requiere banda real (`gang.name ~= 'none'`) **o**
  reputación criminal (`nexus_progression`) ≥
  `illegalAccess.minimumCriminalReputation`.
- Dos bypasses administrativos separados, verificados vía
  `exports.nexus_permissions:hasPermission(source, ...)` — **si
  `nexus_permissions` no está iniciado, ningún jugador real recibe el
  bypass** (solo `source == 0`, es decir la consola del servidor):

```text
nexus_tablet.bypass_illegal_access
nexus_tablet.bypass_app_restriction
```

No se encontró ningún uso de `IsPlayerAceAllowed` en el recurso.
