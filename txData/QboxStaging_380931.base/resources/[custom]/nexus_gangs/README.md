# nexus_gangs

Gestión de bandas/organizaciones para QBox/OX: miembros, rangos con permisos
configurables, reputación, y activos compartidos (stash y garaje) por banda.

## Descripción general

`nexus_gangs` reemplaza la gestión de bandas nativa de QBox con un sistema
propio persistido en SQL: bandas con nombre único, tag, color y reputación;
miembros con un `rank_level` numérico que se resuelve contra una tabla de
rangos definida en `config.lua` (cada rango declara sus propios permisos
booleanos — `invite`, `kick`, `promote`, `manage` — y un flag `isBoss` que
otorga todos los permisos implícitamente). Cuando `syncQboxRuntime` está
activo, cada cambio de banda se refleja también en el `PlayerData.gang`
nativo de QBox, para que otros recursos que todavía leen el campo nativo
(en vez de los exports de este recurso) sigan funcionando.

Sobre esa base de membresía, el recurso añade **activos de banda**: un
stash compartido (`ox_inventory`) y un garaje con flota limitada por modelo,
ambos restringidos por ubicación (`assets.locations`, cada una atada a una
lista de nombres de banda) y por rango mínimo. Existe un segundo modelo de
permisos, independiente del de rango: el bypass administrativo global, que
no vive en `config.lua` sino que se resuelve en runtime contra
`nexus_permissions` (ver más abajo) — el rango de banda decide qué puede
hacer un miembro *dentro* de su banda, mientras que `nexus_permissions`
decide qué puede hacer un administrador *por encima* de cualquier banda.

## Requisitos y Dependencias

### Dependencias declaradas (`fxmanifest.lua` → `dependencies {}`)

**Ninguna.** `nexus_gangs` no declara ningún bloque `dependencies {}` en su
`fxmanifest.lua` — arranca de forma aislada y nunca falla por falta de otro
recurso, ni siquiera de `qbx_core` u `oxmysql`. En la práctica, sin embargo,
usa `oxmysql` (`@oxmysql/lib/MySQL.lua` en `server_scripts`) de forma
incondicional para toda su persistencia — si no está disponible, las
consultas SQL fallarán en runtime aunque el recurso arranque sin error.

### Integraciones blandas (`GetResourceState`, opcionales)

| Recurso | Efecto si está ausente |
|---|---|
| **`nexus_bridge`** | El rate limit de acciones (`rateLimit()`) es **fail-closed**: si `nexus_bridge` no está corriendo, la función devuelve directamente `false` (bloquea) en vez de permitir sin límite — el comentario en el código deja explícito que este fue un fix deliberado sobre un comportamiento previo "fail-open". No hay fallback vendorizado propio como en otros `nexus_*`: sin `nexus_bridge`, ninguna acción sujeta a `rateLimit()` puede ejecutarse. |
| `qbx_core` | Verificado en runtime (`GetResourceState('qbx_core') ~= 'started'`) antes de resolver jugador o sincronizar banda — sin él, `getPlayer()` devuelve `nil` y `syncQboxGang()` no hace nada; el resto de la lógica de banda (SQL) sigue operando para llamadas que no dependen de un `source` activo. |
| `nexus_permissions` | Sin él, **todo** el bypass administrativo global queda desactivado para jugadores reales (`hasGangCreateBypass`, `hasMemberManageOverride`, `hasGangMemberAdminBypass`, `hasReputationGrantBypass` devuelven `false`) — solo la consola del servidor (`source == 0`) conserva ese bypass. El sistema interno de permisos por rango (`rank.isBoss`/`rank.permissions`) sigue funcionando de forma completamente independiente: los líderes de banda pueden seguir gestionando su banda sin `nexus_permissions`. |
| `ox_inventory` | Requerido solo para el stash de banda: si no está corriendo, `registerGangStash` devuelve `false` y `openStash` falla con `'inventory_offline'` — el resto del recurso (rangos, garaje, reputación) no se ve afectado. |
| `nexus_ui` | Si está iniciado, las notificaciones de cliente usan el sistema propio de NEXUS; si no, caen a `lib.notify` de `ox_lib`. |

## Instalación

1. Copia la carpeta `nexus_gangs` a `resources/[custom]/`.
2. Añade en `server.cfg`, en el orden validado para el stack NEXUS completo:
   ```
   nexus_bridge, nexus_permissions, nexus_ui, nexus_scene_core, nexus_ems, nexus_tablet,
   nexus_progression, nexus_dispatch, nexus_gangs, nexus_territories, nexus_dutyboard,
   nexus_crafting, nexus_blackmarket, nexus_contracts, nexus_operations, nexus_labs,
   nexus_laundering, nexus_menu
   ```
   `nexus_gangs` arranca relativamente temprano porque `nexus_territories`
   (control de zonas por banda) lo consulta como integración blanda para
   resolver el nombre de banda con granularidad de rango; colócalo después
   de `nexus_bridge`/`nexus_permissions` para que el bypass administrativo
   y el rate limit se detecten desde el primer arranque (si se inician
   después, `nexus_gangs` los detecta en la siguiente llamada sin necesidad
   de reiniciarlo — salvo el rate limit fail-closed, que bloqueará acciones
   hasta que `nexus_bridge` esté arriba).
3. **SQL:** no requiere importar ningún archivo — las tablas
   (`nexus_gangs`, `nexus_gang_members`, `nexus_gang_logs`,
   `nexus_gang_vehicles`) se crean automáticamente con
   `CREATE TABLE IF NOT EXISTS` en el primer arranque del recurso
   (`server/database.lua`, hook `onResourceStart`).
4. Ajusta `config/config.lua`: rangos y sus permisos, ubicaciones de
   stash/garaje por banda (cada una debe listar los nombres de banda que
   pueden usarla), y catálogo de vehículos del garaje.

## Configuración (`config.lua`)

| Clave | Descripción |
|---|---|
| `debug` | Reservado para logging adicional. |
| `command` | Comando de cliente para abrir el panel de banda (`/gangs`). |
| `adminAce` | **No usado en código.** No hay ninguna llamada a `IsPlayerAceAllowed` en el recurso; el propio comentario en `config.lua` lo confirma ("adminAce ya no se usa") — el bypass administrativo real es 100% vía `nexus_permissions`. |
| `rateLimitBucket` | Bucket de `nexus_bridge` usado para limitar acciones repetidas (fail-closed sin `nexus_bridge`). |
| `defaultColor` | Color por defecto asignado a una banda nueva si no se especifica uno. |
| `defaultReputation` | Reputación inicial de una banda recién creada. |
| `syncQboxRuntime` | Si está activo, cada cambio de banda se refleja también en el `PlayerData.gang` nativo de QBox. |
| `assets.command` | Comando de cliente para abrir el panel de activos de banda (`/gangassets`). |
| `assets.interactDistance` / `.drawDistance` | Distancia de interacción y de dibujo de los marcadores de stash/garaje. |
| `assets.stash.enabled` / `.slots` / `.weight` / `.minRank` | Configuración del stash compartido de `ox_inventory`. |
| `assets.garage.enabled` / `.minRank` / `.platePrefix` / `.maxPerModel` | Configuración del garaje: rango mínimo, prefijo de matrícula generada, límite de unidades por modelo. |
| `assets.garage.vehicles` | Catálogo de vehículos disponibles por banda (modelo, label, rango mínimo). |
| `assets.locations` | Ubicaciones físicas de stash/garaje, cada una atada a una lista de nombres de banda autorizados. |
| `ranks` | Tabla de rangos (`[nivel] = { label, isBoss, permissions = { invite, kick, promote, manage } }`) — base del sistema interno de permisos por rango. |

## Exportaciones y Eventos

### Exports de servidor

```lua
exports.nexus_gangs:getPlayerGang(source)
exports.nexus_gangs:isGangMember(source, gangName)
exports.nexus_gangs:getGangRank(source)
exports.nexus_gangs:hasGangPermission(source, permission)
exports.nexus_gangs:getDashboardAssets(source)
exports.nexus_gangs:getPrimaryStashId(source)
exports.nexus_gangs:getDashboardMembers(source)
exports.nexus_gangs:getDashboardAudit(source)
```

`hasGangPermission` expone directamente el sistema interno de permisos por
rango (`rank.isBoss`/`rank.permissions`) — **sin** el bypass administrativo
de `nexus_permissions.member_manage_override`, que solo se aplica en los
call sites internos que lo necesitan (invitar, gestionar miembros).

### Exports de cliente

```lua
exports.nexus_gangs:openGangs()
exports.nexus_gangs:openGangAssets()
exports.nexus_gangs:openGangManagement()
```

### Callbacks de servidor (`lib.callback.register`)

```
nexus_gangs:server:getGang
nexus_gangs:server:getAssets
nexus_gangs:server:openStash
nexus_gangs:server:requestVehicle
nexus_gangs:server:storeVehicle
```

### Eventos de servidor (`RegisterNetEvent`)

```
nexus_gangs:server:adminAddGangReputation
nexus_gangs:server:invite
nexus_gangs:server:setMemberRank
nexus_gangs:server:kickMember
nexus_gangs:server:acceptInvite
nexus_gangs:server:leave
```

### Eventos de cliente (`RegisterNetEvent`)

```
nexus_gangs:client:open
```

## Comandos y Permisos

| Comando | Quién | Nota |
|---|---|---|
| `/gangs` | Cualquier jugador | Abre el panel de banda propio. |
| `/gangaccept` | Cualquier jugador con invitación pendiente | Acepta la invitación activa. |
| `/gangassets` | Cualquier jugador | Abre el panel de activos de banda (stash/garaje). |
| `/gangassetsrefresh` | Cualquier jugador | Recarga la caché local de activos en el cliente. |
| `/ganginvite <id>` | Miembro con permiso `invite` (por rango) o bypass admin | Internamente pasa por `hasMemberManageOverride` **o** `hasPermission(src, 'invite')`. |
| `/gangcreate <nombre> <label> <tag> [color]` | Requiere `nexus_permissions.nexus_gangs.gang_create` | Sin `nexus_permissions`, nadie salvo consola puede usarlo. |
| `/gangadd <id> <gang> <rank>` | Requiere `nexus_permissions.nexus_gangs.gang_member_admin` | Asigna un jugador a una banda/rango directamente, saltándose el flujo de invitación. |
| `/gangremove <id>` | Requiere `nexus_permissions.nexus_gangs.gang_member_admin` | Expulsa a un jugador de su banda actual. |

Las acciones de gestión de miembros dentro de la banda (expulsar, ascender —
`setMemberRank`/`kickMember`) no son comandos: se disparan desde la NUI y se
validan con `canManageTarget`, que exige **o** el rango del actor tenga el
permiso correspondiente (`kick`/`promote`) sobre un objetivo de rango
inferior en la misma banda, **o** el actor tenga
`nexus_permissions.nexus_gangs.member_manage_override`. El evento
`adminAddGangReputation` (otorgar/quitar reputación manualmente) requiere
`nexus_permissions.nexus_gangs.reputation_grant`.

**Nodos de permiso completos que debe declarar tu integración de
`nexus_permissions`:**

```text
nexus_gangs.gang_create
nexus_gangs.member_manage_override
nexus_gangs.gang_member_admin
nexus_gangs.reputation_grant
```
