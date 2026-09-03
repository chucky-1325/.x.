# nexus_progression

Núcleo de progresión persistente para QBox/OX: XP, nivel y reputación por
dominio (civil, policía, EMS, criminal, empresas, crafting), consumido como
superficie de integración por el resto de recursos `nexus_*` que otorgan
recompensas de progresión.

## Descripción general

`nexus_progression` mantiene, por `citizenid` y por dominio, una fila de
`xp`/`reputation` en base de datos y deriva el `level` a partir de una curva
exponencial configurable (`xpBase`, `xpGrowth`, `maxLevel`). No tiene UI
propia más allá de un menú de contexto de solo lectura (`ox_lib`
`registerContext`); su función real es servir de **libro de contabilidad
central** que otros recursos (`nexus_crafting`, `nexus_ems`,
`nexus_laundering`, `nexus_blackmarket`, `nexus_labs`, `nexus_operations`)
usan para otorgar XP/reputación tras completar acciones de gameplay, y que
recursos de presentación (`nexus_tablet`) consultan para mostrar progreso.

El control de quién puede escribir progresión no es un permiso de jugador:
es una **lista blanca de recursos** (`config.serverApi.writers`), verificada
con `GetInvokingResource()` — solo un recurso explícitamente listado en
`config.lua`, con un `domain` y unos topes de `maxXp`/`maxReputation`
definidos para él, puede llamar al export `addProgression` con éxito. Esto
evita que cualquier script corriendo en el servidor otorgue progresión
arbitraria simplemente exportando la función.

## Requisitos y Dependencias

`nexus_progression` **no declara ningún bloque `dependencies {}`** en su
`fxmanifest.lua` — arranca de forma aislada y no falla por falta de otro
recurso `nexus_*`.

### Requeridas para funcionar (no son `nexus_*`, siempre deben estar presentes)

| Recurso | Uso |
|---|---|
| `ox_lib` | `@ox_lib/init.lua` en `shared_scripts`; usado para `lib.callback.register`/`lib.callback.await` y el menú `registerContext`/`showContext` del comando `/progreso` — sin él el resource falla al iniciar (script no encontrado), no es opcional. |
| `oxmysql` | `@oxmysql/lib/MySQL.lua` en `server_scripts`; toda la persistencia (`server/database.lua`) depende de `MySQL.query.await`/`MySQL.update.await`/`MySQL.single.await` — sin él el resource falla al iniciar. |
| `qbx_core` | Identidad del jugador (`GetPlayer`, `citizenid`) — verificado en runtime vía `GetResourceState`; si falta, `getCitizenId` devuelve `nil` y el callback `nexus_progression:server:get` devuelve `{}` (el menú `/progreso` muestra todos los dominios en nivel 1 / 0 XP en vez de los datos reales), sin crashear. |

### Integraciones blandas (`GetResourceState`, opcionales)

No se encontró ningún uso de `GetResourceState` en `nexus_progression` más
allá del chequeo de `qbx_core` (listado arriba como requerido, no opcional
en la práctica). Este recurso **no consulta** `nexus_permissions`,
`nexus_bridge`, `nexus_ui` ni ningún otro `nexus_*` para su propia lógica:
es un módulo de datos aislado, consumido por otros vía export, nunca al
revés.

## Instalación

1. Copia la carpeta `nexus_progression` a `resources/[custom]/`.
2. Añade en `server.cfg`:
   ```cfg
   ensure nexus_progression
   ```
   Según el orden validado de arranque de este stack, `nexus_progression` va
   **después** de `nexus_tablet` y **antes** de `nexus_dispatch`,
   `nexus_gangs`, `nexus_territories`, `nexus_dutyboard`, `nexus_crafting`,
   `nexus_blackmarket`, `nexus_contracts`, `nexus_operations`, `nexus_labs` y
   `nexus_laundering`:
   ```
   nexus_bridge, nexus_permissions, nexus_ui, nexus_scene_core, nexus_ems, nexus_tablet,
   nexus_progression, nexus_dispatch, nexus_gangs, nexus_territories, nexus_dutyboard,
   nexus_crafting, nexus_blackmarket, nexus_contracts, nexus_operations, nexus_labs,
   nexus_laundering, nexus_menu
   ```
   Va temprano en el stack porque es un módulo base de datos/API: todos los
   sistemas de gameplay que otorgan XP/reputación (`nexus_crafting`,
   `nexus_ems`, `nexus_laundering`, `nexus_blackmarket`, `nexus_labs`,
   `nexus_operations`, listados en `config.serverApi.writers`) necesitan que
   `nexus_progression` ya esté corriendo para que sus llamadas a
   `exports.nexus_progression:addProgression(...)` tengan efecto — si
   invocan el export antes de que este recurso arranque, la llamada
   simplemente falla (el export no existe todavía); no hay cola de reintento.
3. **SQL:** a diferencia de la mayoría de recursos `nexus_*`, este **no**
   crea su tabla en `onResourceStart` desde `server/database.lua` — el
   `CREATE TABLE IF NOT EXISTS` vive en un archivo de migración aparte,
   `sql/migrations/001_initial_schema.sql`, que crea la tabla `nexus_progression`
   (`citizenid`, `domain`, `xp`, `reputation`, `level`, `updated_at`, clave
   primaria compuesta `citizenid + domain`). Revisa si tu instalación importa
   migraciones automáticamente al arrancar recursos `nexus_*`; si no,
   **importa manualmente** `sql/migrations/001_initial_schema.sql` en tu base
   de datos antes de poner este recurso en producción — no se auto-crea al
   iniciar el resource como sí ocurre en otros módulos NEXUS.

## Configuración (`config.lua`)

| Clave | Descripción |
|---|---|
| `debug` | Si es `true`, imprime en consola cada intento de `addProgression` rechazado (`rejectAward`) con el recurso invocante y el motivo. |
| `domains.*` | Catálogo de dominios de progresión (`civil`, `police`, `ems`, `criminal`, `business`, `crafting`), cada uno con `label`, `icon` y `color` usados en el menú de contexto del cliente y en el payload devuelto por `getProgressionByCitizen`. |
| `maxLevel` | Nivel máximo alcanzable; `resolveLevel` deja de sumar niveles al llegar aquí. |
| `xpBase` | XP requerida para pasar del nivel 1 al 2 (base de la curva exponencial). |
| `xpGrowth` | Factor de crecimiento por nivel (`xpBase * xpGrowth ^ (nivel - 1)`). |
| `serverApi.writers.<resource>.<domain>.maxXp` / `.maxReputation` | Whitelist real de quién puede llamar `addProgression`: solo un recurso listado aquí, para el dominio indicado, puede otorgar progresión, y cada llamada queda topada a estos máximos por invocación. |
| `testCommandEnabled` | **Dead/no usado** — no aparece referenciado en ningún archivo `.lua` fuera de `config.lua`; no existe ningún comando de prueba condicionado por este flag en el código actual. |
| `activity.enabled` | **Dead/no usado** — no aparece referenciado en ningún archivo `.lua` fuera de `config.lua`; no hay lógica de "actividad" implementada en este recurso. |

## Exportaciones y Eventos

Esta es la superficie de integración principal que el resto de recursos de
gameplay NEXUS consume para otorgar XP/reputación.

### Exports de servidor

```lua
-- Lectura: progreso completo (todos los dominios) de un citizenid
exports.nexus_progression:getProgressionByCitizen(citizenid)

-- Escritura: otorgar XP/reputación en un dominio
-- Solo funciona si el recurso invocante (GetInvokingResource()) está
-- listado en config.serverApi.writers[<tu_recurso>][domain], y xp/reputation
-- son enteros >= 1 y <= los topes maxXp/maxReputation configurados para ese
-- writer+dominio. Devuelve true en éxito, false (silencioso) si se rechaza.
exports.nexus_progression:addProgression(citizenid, domain, xp, reputation)
```

`addProgression(citizenid, domain, xp, reputation)`:
- `citizenid` (`string`, 1-64 caracteres) — identificador del jugador.
- `domain` (`string`) — debe existir en `config.domains` (`civil`, `police`,
  `ems`, `criminal`, `business`, `crafting`).
- `xp` (`integer`) — entre `1` y el `maxXp` configurado para
  `[GetInvokingResource()][domain]`.
- `reputation` (`integer`) — entre `1` y el `maxReputation` configurado para
  ese mismo par recurso+dominio.
- Retorno: `true` si se aplicó (incrementa `xp`/`reputation` en la fila
  `citizenid+domain`, con `INSERT ... ON DUPLICATE KEY UPDATE`, y
  recalcula/persiste el `level`); `false` si el recurso invocante no está
  autorizado para ese dominio o cualquier validación falla.

No hay ningún export para *restar* o fijar XP/reputación directamente —
solo incremento validado.

### Exports de cliente

```lua
exports.nexus_progression:openProgression()
```

Abre el menú de contexto de solo lectura (`ox_lib`) con el progreso del
jugador local en todos los dominios.

### Callbacks de servidor (`lib.callback.register`)

```
nexus_progression:server:get
```

Devuelve el progreso normalizado (todos los dominios, incluso en nivel 1/0
si no hay fila en BD) del jugador que invoca.

### RegisterNetEvent

No se encontró ningún `RegisterNetEvent` en `server/` ni `client/`. Toda la
comunicación cliente↔servidor pasa por el callback `nexus_progression:server:get`
de `ox_lib`.

## Comandos y Permisos

| Comando | Quién | Nota |
|---|---|---|
| `/progreso` | Cualquier jugador | Abre el menú de progreso propio (`openProgression`, cliente). Sin restricción de permiso alguna — cualquiera puede consultar su propio progreso. |

`nexus_progression` **no enruta ninguna lógica a través de
`nexus_permissions`** — no se encontró ningún `hasPermission`/
`hasAnyPermission`/`IsPlayerAceAllowed` en el recurso. El único control de
acceso que existe es la whitelist de recursos escritores
(`config.serverApi.writers`, ver sección de Configuración), verificada
puramente a nivel de servidor con `GetInvokingResource()`; no hay ningún
gate de administración ni de job pensado para jugadores, porque este recurso
no expone ninguna acción destructiva o sensible a un comando de jugador.
