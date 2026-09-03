# nexus_permissions

Infraestructura RBAC (control de acceso basado en roles) para el stack NEXUS:
catálogo centralizado de permisos granulares por recurso/acción, roles
asignables por `citizenid`, grant/revoke auditado y una API de solo lectura
(`hasPermission` / `hasAnyPermission`) que el resto de recursos `nexus_*`
consultan en vez de mantener sus propios checks ACE o listas de identifiers
hardcodeadas.

## Descripción general

`nexus_permissions` reemplaza los bypasses de administrador dispersos
(ACE sueltas, `identifier` hardcodeado en config, chequeos de job) por un
único catálogo (`config.lua` → `PermissionCatalog`) donde cada entrada es un
string exacto (`recurso.accion`) que un recurso consumidor pasa a
`hasPermission`/`hasAnyPermission`. Los roles (`admin`, `moderator`,
`support`, `developer` por semilla inicial) se asignan a un `citizenid` con
los comandos de consola `grantrole`/`revokerole`, y cada rol tiene cero o más
permisos otorgados en `nexus_permission_role_grants`. Toda concesión,
revocación e intento denegado queda registrado en
`nexus_permission_audit_log` con actor, objetivo, motivo y resultado.

El diseño es explícitamente **fail-closed**: si el recurso no ha terminado de
poblar su caché al arrancar, si el permiso consultado no existe en el
catálogo, o si el `source` no tiene un `citizenid` cacheado, `hasPermission`
devuelve `false` — nunca `true` por defecto ni por error. Solo un permiso
listado explícitamente en `PermissionCatalog` puede llegar a evaluarse como
concedido, aunque algún rol lo tenga otorgado en base de datos.

## Requisitos y Dependencias

`nexus_permissions` declara dependencias duras reales en su
`fxmanifest.lua` (bloque `dependencies {}`):

| Recurso | Uso |
|---|---|
| `oxmysql` | Toda la persistencia: roles, grants, asignaciones y auditoría. Se carga vía `@oxmysql/lib/MySQL.lua` en `server_scripts`. |
| `qbx_core` | Identidad del jugador conectado — `citizenid` se obtiene de `player.PlayerData.citizenid` en el evento `QBCore:Server:PlayerLoaded` y, para jugadores ya conectados al reiniciar el recurso, vía `exports.qbx_core:GetPlayer(source)` en `onResourceStart`. |

**No hay integraciones blandas.** No se encontró ningún `GetResourceState(...)`
en todo el recurso — `nexus_permissions` no detecta ni degrada frente a
ningún otro `nexus_*`; es un recurso base que otros consultan, no al revés.

## Instalación

1. Copia la carpeta `nexus_permissions` a `resources/[custom]/`.
2. **SQL — importación manual obligatoria.** A diferencia de la mayoría de
   `nexus_*`, este recurso **no** tiene `server/database.lua` ni ningún
   `CREATE TABLE IF NOT EXISTS` en tiempo de ejecución: las tablas
   (`nexus_permission_roles`, `nexus_permission_role_grants`,
   `nexus_character_roles`, `nexus_permission_audit_log`) y la semilla de
   roles (`admin`, `moderator`, `support`, `developer`) se crean importando
   a mano, **en orden**, los archivos de `sql/`:
   ```
   001_init.sql
   002_permission_catalog_seed.sql
   003_tablet_permission_split.sql
   004_crafting_permission_split.sql
   005_contracts_permission_split.sql
   006_phase4_permission_seed.sql
   007_territories_permission_split.sql
   008_gangs_permission_split.sql
   ```
   Cada uno tiene su `*.rollback.sql` correspondiente para revertirlo. Estos
   scripts pueblan `nexus_permission_role_grants` con los nodos que ya vienen
   migrados (ver sección de configuración); si vendes el recurso de forma
   standalone sin el resto del stack NEXUS, igual necesitas correr `001` y
   `002` como mínimo para que existan las tablas y los roles base.
3. Añade en `server.cfg`:
   ```cfg
   ensure nexus_permissions
   ```
   Va **justo después de `nexus_bridge`** en el stack NEXUS (ver el orden
   validado de arranque completo abajo): no depende de `nexus_bridge` en
   código, pero casi todos los recursos `nexus_*` que arrancan después
   consultan `nexus_permissions` vía `GetResourceState`/`hasPermission` para
   sus propios paneles de administración, así que debe estar arriba en el
   `server.cfg` para que esas integraciones se detecten desde el primer
   arranque.
   ```
   nexus_bridge, nexus_permissions, nexus_ui, nexus_scene_core, nexus_ems, nexus_tablet,
   nexus_progression, nexus_dispatch, nexus_gangs, nexus_territories, nexus_dutyboard,
   nexus_crafting, nexus_blackmarket, nexus_contracts, nexus_operations, nexus_labs,
   nexus_laundering, nexus_menu
   ```
4. Otorga a quien vaya a ejecutar `grantrole`/`revokerole` la ACE
   `nexus.permissions.manage` (o ejecuta esos comandos desde la consola del
   servidor, `source == 0`, que siempre está autorizada). Este es el único
   punto de bootstrap del sistema: sin él nadie puede asignar el primer rol
   `admin`.

## Configuración (`config.lua`)

| Clave | Descripción |
|---|---|
| `SensitiveResourceWhitelist` | **Dead/unused.** Declarada vacía (`{}`) con un comentario "vacía hasta que se migre realmente un recurso existente" — no se lee en ningún punto de `server/main.lua` ni de ningún otro archivo del recurso. No tiene efecto alguno en tiempo de ejecución. |
| `PermissionCatalog` | El catálogo real. Cada clave es el string exacto (`recurso.accion`) que un recurso consumidor pasa a `hasPermission`/`hasAnyPermission`; el valor (`{ resource, label }`) es metadata informativa. **Solo** los permisos aquí listados pueden evaluarse como `true` — cualquier otro string falla cerrado aunque un rol lo tenga otorgado en base de datos. A fecha de este README incluye nodos migrados para `qbx_mdt`, `handling_lab`, `nexus_dispatch`, `nexus_tablet`, `nexus_crafting`, `nexus_contracts`, `nexus_blackmarket`, `nexus_ems`, `nexus_labs`, `nexus_territories`, `nexus_gangs` y `nexus_menu` (ver el archivo para la lista completa y las notas de fase de cada bloque). |

## Exportaciones y Eventos

### Exports de servidor

```lua
exports.nexus_permissions:hasPermission(source, permission)
exports.nexus_permissions:hasAnyPermission(source, { permission1, permission2, ... })
```

`hasPermission` evalúa un único string contra el catálogo y la caché del
`citizenid` asociado al `source`. `hasAnyPermission` recibe una tabla y
devuelve `true` si al menos una entrada matchea (una entrada con un permiso
no catalogado simplemente no puede matchear, no aborta la evaluación de las
demás). `source == 0` (consola) siempre devuelve `true` sin consultar caché.

No se encontraron exports de cliente, callbacks `lib.callback.register`, ni
`RegisterNetEvent` en este recurso — toda la superficie pública es server-side
vía `exports` y los dos comandos de consola de abajo.

## Comandos y Permisos

**El gating de este recurso NO pasa por `nexus_permissions` mismo** (sería
circular: es el propio recurso que provee ese sistema). El control de acceso
real es **ACE**, vía `IsPlayerAceAllowed`.

| Comando | Quién | Nota |
|---|---|---|
| `grantrole <citizenid> <role> [motivo]` | `source == 0` (consola) o `IsPlayerAceAllowed(source, 'nexus.permissions.manage')` | Valida formato de `citizenid`/`role`, existencia del `citizenid` en `players` y del `role` en `nexus_permission_roles` antes de escribir. Rate-limit interno de 3000 ms (hardcodeado, no viene de `config.lua`) por `source`. Escritura + entrada de auditoría en una única transacción SQL. |
| `revokerole <citizenid> <role> [motivo]` | Igual que `grantrole` | Requiere que la asignación exista (`nexus_character_roles`) antes de borrar. Mismo rate-limit y misma transacción atómica con auditoría. |

Todo intento — autorizado o no, exitoso o rechazado por validación — se
escribe en `nexus_permission_audit_log` (`result`: `success` / `denied` /
`error`).

**Nodos de permiso completos del catálogo actual** (consumidos por otros
recursos `nexus_*`, no por comandos de este propio recurso):

```text
qbx_mdt.admin_access
handling_lab.use
nexus_dispatch.admin_access
nexus_tablet.bypass_illegal_access
nexus_tablet.bypass_app_restriction
nexus_crafting.editor_view
nexus_crafting.editor_mutate
nexus_contracts.quarantine_view
nexus_contracts.craft_quarantine_recover
nexus_contracts.lot_incident_recover
nexus_blackmarket.access_bypass
nexus_blackmarket.distance_bypass
nexus_ems.medic_access_bypass
nexus_ems.grade_override
nexus_labs.progression_bypass
nexus_labs.territory_bypass
nexus_labs.sabotage_bypass
nexus_territories.editor_view
nexus_territories.zone_save
nexus_territories.zone_delete
nexus_territories.graffiti_admin
nexus_territories.influence_grant
nexus_territories.airdrop_admin
nexus_gangs.gang_create
nexus_gangs.member_manage_override
nexus_gangs.gang_member_admin
nexus_gangs.reputation_grant
nexus_menu.admin_access
nexus_menu.give_kit
nexus_menu.grant_progression
```
