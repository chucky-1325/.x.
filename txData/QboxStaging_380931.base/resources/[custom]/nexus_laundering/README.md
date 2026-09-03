# nexus_laundering

Lavado de dinero NEXUS: convierte dinero sucio (item de inventario) en
efectivo limpio a través de puntos de contacto fijos, con comisión, cooldown
por punto, riesgo de alerta policial y auditoría persistente.

## Descripción general

`nexus_laundering` define uno o más puntos de lavado (`config.lua`), cada uno
con un contacto PNJ, una comisión propia (porcentaje que se queda el
"lavador"), un riesgo base y un requisito opcional de reputación
criminal/pertenencia a banda. El jugador entrega una cantidad de
`dirtyItem` (por defecto `black_money`) y recibe efectivo limpio menos la
comisión del punto; cada lavado individual queda en cooldown por
`citizenid` + punto durante `limits.cooldownSeconds`. El riesgo efectivo de
alerta policial se ajusta según si la zona de `nexus_territories` asociada
está controlada por la banda del jugador, disputada o en manos rivales.

Funcionalidades clave:

- Límite de monto por operación (`limits.minAmount`/`maxAmount`) y cooldown por jugador y punto de lavado.
- Riesgo dinámico por punto, ajustado por el estado de control territorial de la zona asociada (sin que esto otorgue influencia de vuelta a `nexus_territories`, ver nota abajo).
- Lock en memoria por `citizenid:locationId` para evitar que invocaciones concurrentes del mismo evento pasen ambas la validación de cooldown antes de que se persista la actualización.
- Log persistente de cada lavado (sucio, limpio, comisión, riesgo, alerta) consultable por `getDashboardLaundering`.

## Requisitos y Dependencias

`nexus_laundering` **no declara ningún bloque `dependencies {}`** en su
`fxmanifest.lua` — arranca aislado y no falla si ningún otro recurso
`nexus_*` está presente.

### Requeridas para funcionar (no son `nexus_*`, siempre deben estar presentes)

| Recurso | Uso |
|---|---|
| `ox_lib` | `lib.callback`, `lib.registerContext`/`lib.showContext`, `lib.showTextUI`, `lib.notify`, `lib.inputDialog` |
| `oxmysql` | Persistencia de logs de lavado y cooldowns por citizenid/punto |
| `qbx_core` | Identidad de jugador (`GetPlayer`, `citizenid`) — se verifica en runtime, degrada sin crashear si falta |
| `ox_inventory` | Verificación y retiro del `dirtyItem` — si no está corriendo, el evento `nexus_laundering:server:launder` responde de inmediato con "Inventario no disponible" y no procesa el lavado |

### Integraciones blandas (`GetResourceState`, opcionales)

| Recurso | Efecto si está ausente |
|---|---|
| `nexus_bridge` | El rate limit de `getLocations`/`launder` pasa a **fail-closed**: si `nexus_bridge` no está corriendo, `rateLimit()` devuelve `false` y bloquea la acción en vez de dejarla sin límite. |
| `nexus_gangs` | Sin él, la banda del jugador se obtiene de `PlayerData.gang` nativo de QBox; sigue funcionando para el requisito `requiredGang` y el log de banda, solo con menos granularidad. |
| `nexus_progression` | Sin él, `getProgress` devuelve `{}` (reputación criminal 0) — los puntos con `minCriminalReputation > 0` quedan inaccesibles, y no se otorga XP/reputación criminal tras lavar. |
| `nexus_territories` | Sin él, `getZoneState` devuelve `nil` y el riesgo efectivo se calcula solo con `baseRisk` (sin ajuste por control territorial). **Importante:** incluso con `nexus_territories` corriendo, este recurso solo *lee* el estado de la zona para el cálculo de riesgo — a diferencia de `nexus_blackmarket`, `nexus_labs` y `nexus_operations`, `nexus_laundering` **no llama a `addInfluence`/`addInfluenceAtCoords`**, por lo que lavar dinero nunca aporta influencia territorial a la banda. |
| `nexus_dispatch` | Sin él, `sendDispatchAlert` no hace nada — la alerta policial sigue llegando por `TriggerClientEvent` directo a jugadores con `job` policial, solo se pierde la integración con el sistema de despacho. |
| `nexus_ui` | Si está iniciado, las notificaciones del cliente usan `exports.nexus_ui:notify`; si no, cae en `lib.notify`. |

**Este recurso no tiene ninguna integración con `nexus_permissions`** (no hay
ninguna llamada a `hasPermission`/`hasAnyPermission` en todo el código). No
existe ningún bypass administrativo de reputación, cooldown o distancia.

## Instalación

1. Copia la carpeta `nexus_laundering` a `resources/[custom]/`.
2. Añade en `server.cfg`:
   ```cfg
   ensure nexus_laundering
   ```
   Según el orden de arranque validado de la suite NEXUS, `nexus_laundering`
   va **después** de `nexus_labs` y **antes** de `nexus_menu`:
   ```
   ..., nexus_operations, nexus_labs, nexus_laundering, nexus_menu
   ```
   Arranca después de `nexus_territories`, `nexus_gangs`, `nexus_progression`,
   `nexus_dispatch` y `nexus_bridge` para que las integraciones blandas se
   detecten desde el primer arranque (si se inician después, se detectan en
   la siguiente llamada sin reiniciar `nexus_laundering`).
3. **SQL:** no requiere importar ningún archivo — las tablas
   (`nexus_laundering_logs`, `nexus_laundering_cooldowns`) se crean
   automáticamente con `CREATE TABLE IF NOT EXISTS` en el primer arranque del
   recurso (`server/database.lua`, hook `onResourceStart`). El repo incluye
   además `sql/install.sql` con la misma definición como referencia/import
   manual opcional; no hace falta ejecutarlo para que el recurso funcione.
4. Registra el item `black_money` (o el que configures en `dirtyItem`) en
   `ox_inventory/data/items.lua`.
5. Ajusta `locations` y `limits` en `config/config.lua` a tu mapa y economía.

## Configuración (`config.lua`)

| Clave | Descripción |
|---|---|
| `command` | Comando para abrir el panel de lavado (`/launder`). |
| `rateLimitBucket` | Bucket de `nexus_bridge` usado para limitar acciones repetidas. |
| `interactDistance` | Distancia de interacción con el contacto de lavado. |
| `dirtyItem` | Item de inventario que representa el dinero sucio a lavar. |
| `limits.minAmount` / `maxAmount` | Monto mínimo exigido y monto máximo permitido por operación (el monto se recorta a `maxAmount` si se excede, no se rechaza). |
| `limits.cooldownSeconds` | Cooldown por `citizenid` + punto de lavado tras completar una operación. |
| `policeJobs` | Tabla de `job` que reciben la alerta policial al completarse un lavado. |
| `locations.*` | Cada punto: label, zona de `nexus_territories`, coordenadas del contacto, comisión, riesgo base, reputación criminal mínima, si requiere banda (`requiredGang`), y modelo/escenario del PNJ. |

## Exportaciones y Eventos

### Exports de servidor

```lua
exports.nexus_laundering:getDashboardLaundering(source)
```

### Exports de cliente

```lua
exports.nexus_laundering:openLaundering()
```

### Callbacks de servidor (`lib.callback.register`)

```lua
nexus_laundering:server:getLocations
```

### Eventos de servidor (`RegisterNetEvent`)

```lua
nexus_laundering:server:launder
```

### Eventos de cliente (`RegisterNetEvent`)

```lua
nexus_laundering:client:policeAlert
```

## Comandos y Permisos

| Comando | Quién | Nota |
|---|---|---|
| `/launder` | Cualquier jugador | Abre el panel de puntos de lavado; cada punto se bloquea/desbloquea según reputación criminal, pertenencia a banda (si `requiredGang`) y cooldown propio. |

**Este recurso no está enrutado por `nexus_permissions` en absoluto** — no
declara ni consume ningún nodo de permiso. No hay comandos administrativos,
ni gate por ACE, ni `source == 0` especial: el único control de acceso es el
que ya aplica a cualquier jugador (reputación criminal, banda si el punto lo
exige, y cooldown). Si necesitas un bypass administrativo para este recurso
tendrás que añadirlo tú — no existe en el código actual.
