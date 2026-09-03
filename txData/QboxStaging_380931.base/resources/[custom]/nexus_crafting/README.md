# nexus_crafting

Sistema de mesas de fabricación ("crafting") para QBox/OX: mesas públicas,
por job, por varios jobs, ilegales (por banda) o de banda persistente
(`mode = 'job'` + `owner_gang`), con recetas configurables, escenas físicas
opcionales, progresión por nivel/reputación y un editor de bancos in-game con
preview 3D.

## Descripción general

Cada mesa (`station`) define un tipo de acceso, una categoría (civil,
mecánico, EMS, policía o mercado negro) y una lista de recetas permitidas.
El servidor revalida siempre acceso, distancia, nivel, reputación, blueprint
físico, materiales y espacio de inventario antes de entregar cualquier item
— el cliente solo dibuja la interfaz y la animación. Las mesas pueden venir
predefinidas en `config.lua` o crearse/moverse/desactivarse en caliente desde
el editor in-game (`/crafteditor`), que persiste overrides en SQL sin
necesidad de reiniciar el recurso.

Funcionalidades clave:

- 5 tipos de acceso por mesa: `public`, `job`, `jobs` (varios job:grado),
  `illegal` (banda ≠ `none`) y `gang` (banda propietaria específica vía
  `mode = 'job'` + `owner_gang`).
- Recetas con nivel/reputación mínimos, blueprint físico opcional, riesgo de
  alerta policial y logging sensible aparte del log estándar.
- Recetas "clasificadas" ocultas hasta alcanzar nivel/reputación.
- Editor in-game con preview 3D de colocación, rotación y snap al suelo.
- Interfaz 3D de mesa (marcador + texto) con distancia de interacción
  configurable, con o sin `ox_target`.
- Integración opcional con escenas físicas (`nexus_scene_core`), progresión
  (`nexus_progression`), bandas (`nexus_gangs`), territorios
  (`nexus_territories`) y el flujo de mecánica de `nexus_contracts`.

## Requisitos y Dependencias

### Dependencias duras (`fxmanifest.lua` → `dependencies {}`)

```lua
dependencies {
    'ox_lib',
    'oxmysql',
    'qbx_core',
    'ox_inventory',
}
```

Sin cualquiera de estos cuatro, el recurso no arranca. Ninguno es otro
recurso `nexus_*` — `nexus_crafting` es instalable de forma standalone sobre
cualquier base QBox/OX estándar.

### Integraciones blandas (`GetResourceState`, opcionales)

| Recurso | Efecto si está ausente |
|---|---|
| **`nexus_bridge`** | Rate limit de fabricación (`rateLimitBucket = 'crafting'`) pasa a **fail-closed**: bloquea en vez de permitir sin límite. |
| **`nexus_permissions`** | El editor de bancos (`/crafteditor`) queda **completamente bloqueado** para jugadores reales — el `editor.ace = 'nexus.crafting.admin'` de `config.lua` existe pero no se usa en código; el control real es 100% `nexus_permissions` (deny-by-default). |
| `nexus_scene_core` | Sin él, la fabricación se resuelve al instante (sin animación/prop físico) en vez de reproducir la escena configurada en `sceneCore.categories`. |
| `nexus_progression` | Sin él, no se aplican bloqueos por nivel de crafting ni se otorga XP — las recetas con `requiredLevel` quedan siempre accesibles. |
| `nexus_gangs` | Sin él, el nombre de banda para mesas `illegal`/`gang` se obtiene del `PlayerData.gang` nativo de QBox en vez de la gestión propia de NEXUS. |
| `nexus_territories` | Sin él, la fabricación ilegal no reduce el riesgo de alerta policial por control territorial ni suma influencia a la banda. |
| `nexus_contracts` | Solo relevante en mesas `mode = 'mechanic'`: gestiona el flujo de cuarentena/paquete físico de reparación; sin él, ese flujo específico queda deshabilitado (`contracts_unavailable`), el resto de mesas no se ve afectado. |
| `ox_target` | Si no está iniciado, la interacción cae automáticamente al marcador/texto 3D + tecla `E` (`worldUi`) — nunca deja una mesa inalcanzable. |
| `nexus_ui` | Si está iniciado, la NUI hereda el design system compartido; si no, usa sus propios estilos. |

## Instalación

1. Copia la carpeta `nexus_crafting` a `resources/[custom]/`.
2. Añade en `server.cfg`, después de `ox_lib`, `oxmysql`, `qbx_core` y
   `ox_inventory`:
   ```cfg
   ensure nexus_crafting
   ```
3. Registra en `ox_inventory/data/items.lua` cualquier item usado como
   `blueprint` o como ingrediente/output de tus recetas (los de ejemplo,
   `bandage`, `plastic`, `rubber`, `repairkit`, etc., ya existen en un
   inventario QBox/OX estándar).
4. **SQL:** no requiere importar ningún archivo — `nexus_crafting_logs`,
   `nexus_crafting_workbenches` y `nexus_crafting_sensitive_logs` se crean
   automáticamente con `CREATE TABLE IF NOT EXISTS` en el primer arranque
   (`server/database.lua`).
5. Ajusta `config.lua` → `stations` a las coordenadas de tu mapa, o deja solo
   las que necesites y crea el resto con `/crafteditor` una vez el recurso
   esté corriendo.

## Configuración (`config.lua`)

| Clave | Descripción |
|---|---|
| `command` / `nearestCommand` / `editorCommand` | `/crafting [id]`, `/craftnear` (mesa más cercana) y `/crafteditor`. |
| `interactDistance` | Distancia máxima para interactuar con una mesa. |
| `rateLimitBucket` | Bucket de `nexus_bridge` para limitar fabricaciones repetidas. |
| `illegalAccess.minimumCriminalReputation` | Reputación criminal mínima para usar una mesa `illegal` sin banda. |
| `criminalProgression.*` | Ajusta cuánta XP/reputación criminal otorgan las recetas sensibles. |
| `sceneCore.categories` | Mapea categoría de mesa → escena física de `nexus_scene_core`; `sceneCore.fallback` se usa si la categoría no tiene escena propia. |
| `sensitiveAlert.*` | Activa alerta policial en recetas `sensitive = true`, jobs que la reciben y cooldown entre alertas. |
| `defaultAccess` | Valores por defecto que usa el editor al crear una mesa nueva. |
| `editor.models` | Modelos 3D seleccionables en el editor de bancos. |
| `worldUi.*` | Marcador/texto 3D de interacción cuando `ox_target` no está disponible (o como complemento). |
| `stations` | Mesas predefinidas: `label`, `type` (`public`/`job`/`jobs`/`illegal`/`gang`), `category`, `coords`, `size`, `heading`, `recipes`, y para tipo `gang`: `mode = 'job'` + `owner_gang`. |
| `recipes` | Cada receta: `output`, `ingredients`, `duration`, `requiredLevel`, `xp`, `reputation`, y opcionalmente `blueprint`, `hiddenUntilLevel`, `hiddenUntilReputation`, `risk.policeAlertChance`, `sensitive`. Ver `CONFIG_GUIDE.md` del repositorio para el detalle de estos campos avanzados. |

## Exportaciones y Eventos

### Exports de cliente

```lua
exports.nexus_crafting:openCrafting(stationId)
```

Abre la interfaz de una mesa concreta (o la del Vertical Slice por defecto
si se omite `stationId`).

### Callbacks de servidor (`lib.callback`)

```text
nexus_crafting:server:getStation(stationId)
nexus_crafting:server:getStations()
nexus_crafting:server:canCraft(stationId, recipeId)
nexus_crafting:server:finishCraft(stationId, recipeId, sessionToken)
nexus_crafting:server:cancelCraft(sessionToken)
nexus_crafting:server:editorList()
nexus_crafting:server:getStationJob(stationId)
nexus_crafting:server:startJob(stationId, recipeId)
nexus_crafting:server:collectJob(jobKey)
nexus_crafting:server:cancelJob(jobKey)
```

### Eventos de servidor (`RegisterNetEvent`)

`nexus_crafting:server:saveWorkbench` (crear/editar mesa dinámica, requiere
`editor_mutate`), `nexus_crafting:server:deleteWorkbench` (requiere
`editor_mutate`).

### Eventos de cliente

`nexus_crafting:client:refreshWorkbenches` (sincroniza mesas dinámicas tras
un cambio del editor), `nexus_crafting:client:sensitiveAlert` (recibido por
jobs policiales cuando una receta sensible dispara alerta).

## Comandos y Permisos

| Comando | Quién | Nota |
|---|---|---|
| `/crafting [id]` | Cualquier jugador | El servidor valida acceso real a la mesa igualmente. |
| `/craftnear` | Cualquier jugador | Abre la mesa habilitada más cercana dentro de `interactDistance`. |
| `/craftreload` | Cualquier jugador | Refresca la caché local de mesas dinámicas. |
| `/craftclose` | Cualquier jugador | Cierra la interfaz de crafting. |
| `/crafteditor` | Requiere `nexus_permissions.nexus_crafting.editor_view` (lectura) / `...editor_mutate` (crear, mover, activar/desactivar, eliminar) | Sin `nexus_permissions` corriendo, nadie salvo consola (`source == 0`) puede abrirlo ni mutar mesas. |

**Nodos de permiso completos que debe declarar tu integración de
`nexus_permissions`:**

```text
nexus_crafting.editor_view
nexus_crafting.editor_mutate
```
