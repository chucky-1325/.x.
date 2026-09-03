# nexus_dutyboard

Punto de fichaje (clock-in/clock-out) neutral para el trabajo `mechanic`, con
una integración opcional de resumen de tareas activas de `nexus_contracts`.

## Descripción general

`nexus_dutyboard` es un recurso deliberadamente pequeño: coloca un punto de
interacción físico (`ox_target`, zona esférica) donde cualquier jugador con
el trabajo configurado (`mechanic` por defecto) puede fichar entrada/salida
de servicio. El fichaje alterna el `onduty` nativo de QBox
(`exports.qbx_core:SetJobDuty`) tras una comprobación de distancia
server-autoritativa independiente del radio del `ox_target` del cliente, más
un cooldown local y un rate limit compartido con el resto del stack NEXUS.

Si `nexus_contracts` está corriendo, el panel de fichaje también muestra un
resumen de solo lectura de las tareas activas del jugador (lote de
suministro civil en curso, reserva de fabricación en curso, o incidencia de
cuarentena pendiente) para que el mecánico sepa si tiene trabajo abierto
antes de fichar salida — pero `nexus_dutyboard` nunca modifica ese estado,
solo lo consulta y lo muestra.

## Requisitos y Dependencias

### Dependencias declaradas (`fxmanifest.lua` → `dependencies {}`)

| Recurso | Uso |
|---|---|
| `ox_lib` | `lib.callback`, contexto de menú del panel |
| `qbx_core` | Identidad de jugador, trabajo/grado, `SetJobDuty` |
| `ox_target` | Zona de interacción física en el punto de fichaje |

A pesar de declararse como dependencias duras, el recurso **también**
comprueba en runtime `GetResourceState('qbx_core') == 'started' and
GetResourceState('ox_target') == 'started'` (`dependenciesReady()`) antes de
resolver cualquier callback — si cualquiera de los dos se reinicia o cae en
caliente, los callbacks devuelven `nil`/`false` en vez de lanzar un error.

### Integraciones blandas (`GetResourceState`, opcionales)

| Recurso | Efecto si está ausente |
|---|---|
| **`nexus_bridge`** | El rate limit de fichaje (`toggleDuty`) cae a `server/security_fallback.lua`, un fallback vendorizado con los mismos parámetros de `config.security.rateLimits` — sigue protegido, solo pierde el bucket compartido de `nexus_bridge`. Nota: `'dutyboard'` no es un bucket propio dentro de `nexus_bridge` tampoco, así que ambos caminos terminan usando el mismo límite `default`. |
| `nexus_ui` | Sin él, las notificaciones de fichaje usan `lib.notify` en vez del sistema de notificación propio de NEXUS. |
| `nexus_contracts` | Sin él, el panel de fichaje omite el resumen de lote/fabricación activa (`status.lot`/`status.craft` quedan `nil`) — el fichaje en sí funciona igual. |

## Instalación

1. Copia la carpeta `nexus_dutyboard` a `resources/[custom]/`.
2. Añade en `server.cfg`, en el orden validado para el stack NEXUS completo:
   ```
   nexus_bridge, nexus_permissions, nexus_ui, nexus_scene_core, nexus_ems, nexus_tablet,
   nexus_progression, nexus_dispatch, nexus_gangs, nexus_territories, nexus_dutyboard,
   nexus_crafting, nexus_blackmarket, nexus_contracts, nexus_operations, nexus_labs,
   nexus_laundering, nexus_menu
   ```
   `nexus_dutyboard` arranca **antes** de `nexus_contracts`: si lo inicias
   después, el resumen de tareas activas simplemente no aparece hasta que
   `nexus_contracts` arranque (se detecta por llamada, no requiere
   reiniciar `nexus_dutyboard`).
3. **SQL:** no aplica — este recurso no tiene `server/database.lua` ni
   ejecuta ninguna consulta SQL; todo su estado vive en el `onduty` nativo
   de QBox y en memoria (cooldowns).
4. Ajusta `point`, `radius` y `job` en `config/config.lua` a tu mapa y
   trabajo.

## Configuración (`config.lua`)

| Clave | Descripción |
|---|---|
| `debug` | Debug de la zona `ox_target` (pasado directo como `debug` al `addSphereZone`). |
| `job` | Nombre del trabajo QBox habilitado para fichar en este punto. |
| `point` | Coordenadas del punto de fichaje. |
| `radius` | Radio de la zona `ox_target` en el cliente. |
| `targetLabel` / `targetIcon` | Label e icono de la opción de interacción de `ox_target`. |
| `maxServerDistance` | Distancia máxima aceptada por el servidor al validar `GetEntityCoords` del jugador — independiente del radio de `ox_target` de arriba, es la comprobación autoritativa real. |
| `rateLimitBucket` | Bucket de `nexus_bridge`/fallback usado para limitar el fichaje repetido. |
| `localCooldownMs` | Cooldown local adicional (en memoria) entre fichajes del mismo jugador. |
| `security.*` | Parámetros usados **solo** por `server/security_fallback.lua` cuando `nexus_bridge` no está corriendo. |

## Exportaciones y Eventos

Este recurso **no expone ningún export**, ni de servidor ni de cliente.

### Callbacks de servidor (`lib.callback.register`)

```
nexus_dutyboard:server:getStatus
nexus_dutyboard:server:toggleDuty
```

### Eventos de servidor

Ninguno (`RegisterNetEvent`) — toda la interacción del cliente pasa por los
dos callbacks de arriba.

### Eventos de cliente (`RegisterNetEvent`)

```
nexus_dutyboard:client:notify
```

## Comandos y Permisos

Este recurso **no registra ningún comando** (`RegisterCommand`) — la única
vía de interacción es la zona física de `ox_target` en `config.point`.

El acceso **no está routeado por `nexus_permissions`** en absoluto: el
único gate es el trabajo del jugador (`job.name == NexusDutyboardConfig.job`,
verificado en ambos callbacks de servidor). Cualquier jugador con el trabajo
`mechanic` (por defecto) puede fichar; no existe ningún nodo de permiso, ACE
ni check `source == 0` en este recurso.
