# nexus_dispatch

Alertas policiales centralizadas para QBox/OX: panel único de incidentes en
vivo, asignación de unidades y cierre con resultado, con enlace opcional a
`ais_core` para abrir un caso de investigación desde una alerta.

## Descripción general

`nexus_dispatch` es un tablón de despacho consumido por otros recursos
NEXUS (crafting ilegal, sabotaje, lavado, operaciones de banda, mercado
negro, BOLOs, etc.) a través de un único export (`createAlert`): cualquier
recurso puede reportar un incidente con tipo, ubicación, riesgo y prioridad,
y el recurso lo persiste, lo transmite en vivo (blip + notificación) a todo
jugador con acceso, y lo mantiene en un panel centralizado donde los
oficiales pueden asignarse, cambiar de estado (`open` → `assigned` →
`enroute` → `closed`), añadir notas operativas y cerrar con un resultado.

El acceso a todo el panel es uniforme: un jugador tiene acceso si su trabajo
está en la lista `policeJobs` de `config.lua` **o** si tiene el permiso
administrativo de `nexus_permissions` — no hay niveles de acceso
intermedios ni comandos separados por rol. Opcionalmente, si `ais_core` está
instalado y habilitado, un oficial puede convertir una alerta en un caso de
investigación formal (`createAisCase`), mapeando el tipo de alerta NEXUS a
un tipo de caso AIS y la prioridad numérica a una etiqueta de severidad.

## Requisitos y Dependencias

### Dependencias declaradas (`fxmanifest.lua` → `dependencies {}`)

**Ninguna.** `nexus_dispatch` no declara ningún bloque `dependencies {}` en
su `fxmanifest.lua`. En la práctica, sin embargo, usa `oxmysql`
(`@oxmysql/lib/MySQL.lua`) de forma incondicional para toda su persistencia,
y **`qbx_core` se referencia de forma hard-coded sin ningún guard de
`GetResourceState`**: `server/main.lua` abre con
`local QBCore = exports.qbx_core` y todas las funciones de jugador
(`getPlayer`, `getOfficer`, `isPolice`) llaman a `QBCore:GetPlayer(...)`
directamente. Si `qbx_core` no está corriendo, el recurso arranca sin error
(los exports proxy son perezosos), pero cualquier callback que necesite
datos de jugador fallará en runtime — a efectos prácticos es una
**dependencia dura no declarada**, a diferencia de otros `nexus_*` que sí
comprueban `GetResourceState('qbx_core')` antes de usarlo.

### Integraciones blandas (`GetResourceState`, opcionales)

| Recurso | Efecto si está ausente |
|---|---|
| `nexus_permissions` | Sin él, `isAdmin()` devuelve `false` para cualquier jugador real (solo `source == 0`, la consola, conserva el bypass) — el acceso al panel sigue disponible para cualquier jugador cuyo trabajo esté en `policeJobs`, pero nadie puede obtener acceso *administrativo* adicional por esta vía. |
| `ais_core` (nombre configurable en `ais.resource`) | Si no está corriendo o `ais.enabled = false`, `createAisCase` devuelve `false, 'ais_not_started'`/`'disabled'` de forma controlada — el resto del panel de despacho funciona igual, simplemente no se puede vincular una alerta a un caso de investigación. |

`nexus_dispatch` **no integra `nexus_bridge`**: no hay ninguna llamada
`GetResourceState('nexus_bridge')` ni fallback vendorizado en este recurso.
El único rate limit es un límite local en memoria de 1 segundo por jugador
(`rateLimit()` con `GetGameTimer()`), independiente del resto del stack.

## Instalación

1. Copia la carpeta `nexus_dispatch` a `resources/[custom]/`.
2. Añade en `server.cfg`, en el orden validado para el stack NEXUS completo:
   ```
   nexus_bridge, nexus_permissions, nexus_ui, nexus_scene_core, nexus_ems, nexus_tablet,
   nexus_progression, nexus_dispatch, nexus_gangs, nexus_territories, nexus_dutyboard,
   nexus_crafting, nexus_blackmarket, nexus_contracts, nexus_operations, nexus_labs,
   nexus_laundering, nexus_menu
   ```
   `nexus_dispatch` arranca **temprano**, antes de `nexus_gangs` y de todos
   los recursos del loop ilegal (`nexus_crafting`, `nexus_blackmarket`,
   `nexus_contracts`, `nexus_operations`, `nexus_labs`,
   `nexus_laundering`), porque todos ellos lo consumen vía `createAlert`
   para reportar incidentes — debe estar arriba y con su tabla creada antes
   de que cualquiera intente despachar una alerta. Colócalo después de
   `nexus_permissions` para que el acceso administrativo se detecte desde
   el primer arranque.
3. **SQL:** no requiere importar ningún archivo — las tablas
   (`nexus_dispatch_alerts`, `nexus_dispatch_units`) se crean
   automáticamente con `CREATE TABLE IF NOT EXISTS` en el primer arranque
   del recurso (`server/database.lua`, función `NexusDispatchEnsureDatabase`
   llamada desde el hook `onResourceStart`), incluyendo migraciones
   incrementales de columnas/índices vía `ensureColumn`/`ensureIndex` para
   instalaciones que vienen de una versión anterior de la tabla.
   `sql/install.sql` es una copia estática de referencia del mismo esquema,
   no es necesario importarla a mano.
4. Ajusta `policeJobs`, `types` y la integración `ais.*` de
   `config/config.lua` a tus trabajos policiales y catálogo de incidentes.

## Configuración (`config.lua`)

| Clave | Descripción |
|---|---|
| `command` | Comando de cliente para abrir el panel de despacho (`/dispatch`). |
| `maxRecent` | Número de alertas recientes devueltas por el panel. |
| `blipSeconds` | Duración en segundos del blip de mapa creado por cada alerta nueva. |
| `adminAce` | **No usado en código.** No hay ninguna llamada a `IsPlayerAceAllowed` en el recurso; el acceso administrativo real es 100% vía `nexus_permissions.nexus_dispatch.admin_access`. |
| `statuses` | Catálogo de estados válidos de una alerta (`open`, `assigned`, `enroute`, `closed`) con su label. |
| `ais.enabled` / `.resource` | Activa la integración con el recurso de casos de investigación y su nombre (por defecto `ais_core`, configurable). |
| `ais.typeMap` | Mapeo de tipo de alerta NEXUS → `case_type` de AIS. |
| `policeJobs` | Tabla de trabajos QBox considerados "policía" a efectos de acceso al panel. |
| `types` | Catálogo de tipos de incidente (label, prioridad, sprite y color de blip). |

## Exportaciones y Eventos

### Exports de servidor

```lua
exports.nexus_dispatch:createAlert(data)
```

Este es el único punto de entrada para que otro recurso reporte un
incidente; internamente normaliza y persiste la alerta y la retransmite a
todo jugador con acceso.

### Exports de cliente

```lua
exports.nexus_dispatch:openDispatch()
```

### Callbacks de servidor (`lib.callback.register`)

```
nexus_dispatch:server:getRecent
nexus_dispatch:server:updateAlert
nexus_dispatch:server:setUnitStatus
nexus_dispatch:server:closeAlert
nexus_dispatch:server:addNote
nexus_dispatch:server:createAisCase
```

Los seis callbacks exigen `hasAccess(source)` (policía **o** admin de
`nexus_permissions`) como primera comprobación.

### Eventos de servidor

Ninguno (`RegisterNetEvent`) — toda la escritura desde el cliente pasa por
los callbacks de arriba.

### Eventos de cliente (`RegisterNetEvent`)

```
nexus_dispatch:client:alert
nexus_dispatch:client:updated
```

## Comandos y Permisos

| Comando | Quién | Nota |
|---|---|---|
| `/dispatch` | Cualquier jugador | Abre el panel de cliente; el contenido real que ve depende de `hasAccess` al pedir datos al servidor — un jugador sin acceso simplemente no recibe alertas. |

No hay comandos de servidor ni de consola en este recurso. Todo el control
de acceso pasa por una única función, `hasAccess(source)`:

```lua
hasAccess(source) = isPolice(source) OR isAdmin(source)
```

- `isPolice(source)`: el trabajo actual del jugador (`PlayerData.job.name`)
  está en `NexusDispatchConfig.policeJobs`.
- `isAdmin(source)`: `source == 0` (consola), **o**
  `exports.nexus_permissions:hasPermission(source, 'nexus_dispatch.admin_access')`
  si `nexus_permissions` está corriendo; `false` en caso contrario.

**Nodo de permiso completo que debe declarar tu integración de
`nexus_permissions`:**

```text
nexus_dispatch.admin_access
```
