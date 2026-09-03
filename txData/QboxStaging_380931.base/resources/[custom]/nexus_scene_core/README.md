# nexus_scene_core

Motor de escenas físicas reutilizable para todo el stack NEXUS: reproduce
animación + props sincronizados + barra de progreso para una escena
predefinida (`config/scenes.lua`), y solo eso. No entrega items, dinero, XP
ni permisos — el recurso de gameplay que lo invoca (`nexus_crafting`,
`nexus_labs`, `nexus_ems`, `nexus_contracts`, etc.) valida la acción en
servidor, dispara la escena en cliente vía `exports.nexus_scene_core:play(...)`
y solo después de recibir `completed == true` procede con su propia lógica de
negocio y su propio protocolo de verificación anti-cheat (típicamente
apoyado en `nexus_bridge:beginTimedAction`/`consumeTimedAction`, no en este
recurso).

## Descripción general

Cada escena es una entrada de `NexusSceneDefinitions` (`config/scenes.lua`)
con una animación (`dict`/`clip`/`flag`), hasta `NexusSceneConstants.MAX_PROPS`
(3) props adjuntos a un hueso del ped, y opcionalmente efectos de partículas.
`NexusSceneRuntime.play(sceneId, context)` valida el `sceneId` contra el
catálogo, carga el diccionario de animación y los modelos de prop con
timeout, gira al ped hacia `context.targetCoords` si `turnToTarget` está
activo, muestra `lib.progressBar` (cancelable salvo que
`context.canCancel == false`) y limpia todo (props, efectos, animación,
estado de red del jugador) al terminar o cancelar. Solo puede haber una
escena activa a la vez por cliente (`busy` si se pide una segunda). El
servidor no ejecuta nada de la escena en sí — solo expone `isRegistered` y
`getMetadata` como consultas de solo lectura sobre el catálogo compartido.

## Requisitos y Dependencias

`nexus_scene_core` declara una única dependencia dura en su `fxmanifest.lua`,
con la sintaxis singular `dependency 'ox_lib'` (equivalente a un
`dependencies { 'ox_lib' }` de una sola entrada):

| Recurso | Uso |
|---|---|
| `ox_lib` | `lib.progressBar` (barra de progreso cancelable) y `lib.cancelProgress` (cancelación forzada desde `NexusSceneRuntime.cancel`). Sin `ox_lib` iniciado, el recurso no arranca. |

**No se encontró ninguna integración blanda.** No hay ni un solo
`GetResourceState(...)` en todo `nexus_scene_core`: no detecta ni degrada
frente a ningún otro `nexus_*`, ni siquiera `nexus_bridge` o
`nexus_permissions` — es intencionalmente un núcleo aislado sin autoridad de
gameplay ni de permisos, tal como documenta el propio recurso en su mensaje
de arranque ("autoridad económica permanece en recursos dueños").

## Instalación

1. Copia la carpeta `nexus_scene_core` a `resources/[custom]/`.
2. **SQL: no aplica.** No existe `server/database.lua`, ninguna carpeta
   `sql/`, ni una sola sentencia `CREATE TABLE` en el recurso — no persiste
   nada, todo el estado de una escena vive en memoria del cliente mientras
   dura la acción.
3. Añade en `server.cfg`:
   ```cfg
   ensure ox_lib
   ensure nexus_scene_core
   ```
   En el stack NEXUS completo se coloca **después de `nexus_ui`** y antes de
   los recursos de gameplay que lo consumen (EMS, tablet, crafting, labs,
   contratos):
   ```
   nexus_bridge, nexus_permissions, nexus_ui, nexus_scene_core, nexus_ems, nexus_tablet,
   nexus_progression, nexus_dispatch, nexus_gangs, nexus_territories, nexus_dutyboard,
   nexus_crafting, nexus_blackmarket, nexus_contracts, nexus_operations, nexus_labs,
   nexus_laundering, nexus_menu
   ```
   El orden respecto a `nexus_bridge`/`nexus_permissions` no importa en la
   práctica (no hay integración entre ellos), pero debe arrancar **antes**
   que cualquier recurso que llame a `exports.nexus_scene_core:play(...)`.
4. Revisa `config/scenes.lua` y reemplaza/añade entradas si tu servidor usa
   modelos de prop o diccionarios de animación distintos a los 19 incluidos
   por defecto (crafting civil/mecánico/ilegal/médico/policial, labs de
   química/empaquetado/procesado/mantenimiento/sabotaje, logística de
   paquetes/extorsión, y evidencia/EMS).

## Configuración (`config.lua`)

| Clave | Descripción |
|---|---|
| `debug` | Si es `true`, registra el comando de cliente `/scenetest [sceneId]` para reproducir cualquier escena del catálogo con 5000 ms fijos, sin invocar ningún recurso de gameplay. |
| `networkedProps` | Si los props creados (`CreateObjectNoOffset`) se sincronizan en red (`true`) o son puramente locales al cliente que ejecuta la escena. |
| `turnToTarget` | Si la escena gira al ped hacia `context.targetCoords` antes de reproducir la animación. |
| `turnTimeout` | Tiempo máximo (ms) que se espera a que termine el giro (`TaskTurnPedToFaceCoord`). |
| `progressPosition` | Posición en pantalla de la barra `lib.progressBar` (p. ej. `'bottom'`). |
| `controls.move` / `car` / `combat` / `mouse` / `sprint` | Qué controles se deshabilitan mientras la barra de progreso está activa (pasado directo a `lib.progressBar({ disable = ... })`). |

`config/scenes.lua` (`NexusSceneDefinitions`) no son claves de configuración
en el sentido de comportamiento del motor, sino el catálogo de datos de cada
escena — no se documentan como tabla de config aquí porque su contenido es
enteramente específico del contenido visual, no de la lógica del recurso.

## Exportaciones y Eventos

### Exports de cliente

```lua
exports.nexus_scene_core:play(sceneId, context)
exports.nexus_scene_core:cancel()
exports.nexus_scene_core:isPlaying()
exports.nexus_scene_core:getDefinition(sceneId)
```

`play` devuelve `completed (boolean), reason (string)` — `reason` es
`'completed'`, `'cancelled'`, `'busy'`, `'invalid_scene'`, `'invalid_ped'` o
`'animation_failed'`. `context` acepta `duration`, `label`, `targetCoords` y
`canCancel`.

### Exports de servidor

```lua
exports.nexus_scene_core:isRegistered(sceneId)
exports.nexus_scene_core:getMetadata(sceneId)
```

Ambos son de solo lectura sobre el catálogo compartido (`shared_scripts`); no
ejecutan ni verifican ninguna acción de gameplay.

### Callbacks (`lib.callback.register`)

No se encontró ninguno — este recurso no tiene comunicación cliente-servidor
propia, ni siquiera para reportar el resultado de una escena (eso es
responsabilidad exclusiva del recurso consumidor).

### Eventos de servidor / cliente (`RegisterNetEvent`)

No se encontró ningún `RegisterNetEvent` en ningún lado del recurso.

## Comandos y Permisos

| Comando | Quién | Nota |
|---|---|---|
| `/scenetest [sceneId]` | Cualquier jugador, **solo si `config.debug == true`** (por defecto `false`) | Comando registrado únicamente del lado cliente, sin ningún gate de permisos ni de servidor — es una herramienta de depuración visual, no de gameplay: no otorga nada, solo reproduce la escena localmente. |

**Este recurso no gatea nada a través de `nexus_permissions`, ACE, ni chequeo
de job/consola.** No hay `hasPermission`, `hasAnyPermission` ni
`IsPlayerAceAllowed` en todo el código — es coherente con su rol de motor
puramente visual sin autoridad de negocio: la única superficie sensible
(`/scenetest`) se controla apagando `config.debug` en producción, no con un
permiso.
