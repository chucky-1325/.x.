# nexus_contracts

Contratos civiles trazables para QBox/OX: recogida y entrega física de
paquetes (transporte de suministros), con un subsistema de cuarentena de
crafting/incidencias de lote para el taller mecánico.

## Descripción general

`nexus_contracts` implementa un flujo de contrato civil de un solo tramo
(`civil_mechanic_supply`): el jugador recoge un paquete físico sellado en un
punto de contacto, lo transporta y lo entrega en el taller mecánico, con
acciones temporizadas server-autoritativas (pickup/deliver) y expiración
automática por barrido periódico. Cada lote (`lot`) atraviesa una máquina de
estados persistida en SQL (`reserved` → `picked_up` → `delivery_pending` →
`delivered`/`cancelled`/`expired`/`lost`/`ambiguous`), diseñada para que
ningún fallo a mitad de transacción (crash, desconexión, SQL fallido) pueda
duplicar ni perder materiales sin dejar rastro.

Sobre esa misma base, el recurso expone un **puente de crafting para
`nexus_crafting`**: una estación `mode='mechanic'` (`mechanic_bench`,
receta `repairkit_basic`) reserva stock civil ya entregado, fabrica y
consume el stock a través de exports dedicados
(`reserveMechanicCraft`/`beginMechanicCraft`/`completeMechanicCraft`/
`releaseMechanicCraft`), verificados con `GetInvokingResource() ==
'nexus_crafting'` para que solo ese recurso pueda invocarlos. Cuando el
resultado de una fabricación queda en duda (por ejemplo, el server se
detiene mientras la reserva está `fulfilling`, o `nexus_crafting` reporta
que no puede confirmar si el ítem llegó al inventario), la reserva se marca
**`ambiguous`** — en cuarentena — y solo puede resolverla un administrador
con permiso explícito desde el panel `/craftquarantine`, eligiendo
"Reintegrar" (devuelve el stock reservado al pool disponible, solo permitido
para motivos donde el ítem de salida demostrablemente nunca se entregó) o
"Cerrar" (descarta el stock sin reintegrar). El mismo patrón de cuarentena
existe para incidencias de lote de suministro civil (`/supplyincidents`),
resuelto vía procedimientos almacenados (`sp_recover_craft_quarantine`,
`sp_recover_civil_lot_incident`) que solo aceptan una lista blanca de
`incident_reason` conocidos como seguros.

## Requisitos y Dependencias

### Dependencias declaradas (`fxmanifest.lua` → `dependencies {}`)

| Recurso | Uso |
|---|---|
| `ox_lib` | `lib.callback`, contexto de menús, diálogos de confirmación |
| `oxmysql` | Persistencia de lotes, stock, reservas de crafting y eventos |
| `qbx_core` | Identidad de jugador, `citizenid`, verificado en runtime |
| `ox_inventory` | Añadir/quitar/verificar el ítem físico del paquete (`nexus_contract_package`) |

### Integraciones blandas (`GetResourceState`, opcionales)

| Recurso | Efecto si está ausente |
|---|---|
| **`nexus_bridge`** | Rate limit y acciones temporizadas (pickup/deliver) caen a `server/security_fallback.lua`, un fallback vendorizado con los mismos parámetros (`security.rateLimits`, `security.timedActions` de `config.lua`) — sigue protegido, solo pierde el bucket compartido de `nexus_bridge`. |
| `nexus_ui` | Sin él, las notificaciones de cliente usan `lib.notify` en vez del sistema de notificación propio de NEXUS — misma información, estilo por defecto de `ox_lib`. |
| `nexus_scene_core` | Sin él (o con `sceneCore.enabled = false` en config), las acciones de pickup/deliver se resuelven sin la escena de animación/progreso de `nexus_scene_core`; el flujo de negocio no se ve afectado. |
| `nexus_permissions` | **Obligatorio en la práctica** para el panel de cuarentena y el panel de incidencias de lote: sin él, `hasQuarantineViewPermission`/`hasCraftQuarantineRecoverPermission`/`hasLotIncidentRecoverPermission` devuelven `false` para cualquier jugador real (solo `source == 0`, la consola, conserva acceso). El campo `quarantineAdminAce` de `config.lua` **no se usa en código** — no hay ninguna llamada a `IsPlayerAceAllowed` en el recurso. |

`nexus_crafting` **no aparece como dependencia ni como `GetResourceState`
check**: el puente de crafting se autoriza exclusivamente verificando
`GetInvokingResource() == 'nexus_crafting'` en cada export de fabricación,
así que si `nexus_crafting` no está instalado esos exports simplemente
nunca son invocados por nadie — no hay comprobación de arranque.

## Instalación

1. Copia la carpeta `nexus_contracts` a `resources/[custom]/`.
2. Añade en `server.cfg`, en el orden validado para el stack NEXUS completo:
   ```
   nexus_bridge, nexus_permissions, nexus_ui, nexus_scene_core, nexus_ems, nexus_tablet,
   nexus_progression, nexus_dispatch, nexus_gangs, nexus_territories, nexus_dutyboard,
   nexus_crafting, nexus_blackmarket, nexus_contracts, nexus_operations, nexus_labs,
   nexus_laundering, nexus_menu
   ```
   `nexus_contracts` arranca **después** de `nexus_dutyboard` (que consulta
   `getDutyboardSnapshot` de este recurso si está corriendo) y **antes** de
   `nexus_crafting` no es estrictamente necesario en este orden — la
   autorización del puente de crafting es por invocación en tiempo de
   ejecución, no por orden de arranque — pero mantener el orden de la lista
   evita falsos negativos de las integraciones blandas en el primer
   arranque (`nexus_ui`, `nexus_scene_core`, `nexus_permissions`,
   `nexus_bridge` ya estarán activos).
3. **SQL — importación manual obligatoria.** A diferencia de otros recursos
   `nexus_*` de este stack, `nexus_contracts` **no crea sus tablas
   automáticamente** en `onResourceStart`; `server/database.lua` solo
   *verifica* el esquema (`NexusContractsSchemaReady`,
   `NexusContractsCraftingSchemaReady`) contra `information_schema` y, si
   falta algo, **desactiva** el flujo correspondiente e imprime un error en
   consola (`migration_002_incomplete` / `migration_003_incomplete`) sin
   crashear el recurso. Debes aplicar manualmente, en orden, con el recurso
   detenido:
   - `sql/migrations/002_mechanic_supply.sql` (tablas de lotes de
     suministro civil — requerido para el flujo de contrato civil)
   - `sql/migrations/003_mechanic_crafting.sql` (tablas de reservas de
     fabricación del mecánico — requerido para el puente con
     `nexus_crafting`)
   - `sql/migrations/004_quarantine_recovery_procedure.sql` (procedimiento
     `sp_recover_craft_quarantine`)
   - `sql/migrations/005_civil_lot_recovery_procedure.sql` (procedimiento
     `sp_recover_civil_lot_incident`)
   - `sql/migrations/006_craft_quarantine_reintegrar_guard.sql` (guardas de
     seguridad sobre la ruta "reintegrar" del procedimiento 004)

   `sql/install.sql` (tabla `nexus_contract_logs`) es un artefacto legado:
   ninguna consulta del recurso lee o escribe esa tabla actualmente — no es
   necesario importarlo para que el recurso funcione.
4. Registra el ítem `nexus_contract_package` en `ox_inventory/data/items.lua`.
5. Ajusta `config/config.lua` (coordenadas de contacto, estación del
   mecánico, contenidos del paquete) a tu mapa/economía.

## Configuración (`config.lua`)

| Clave | Descripción |
|---|---|
| `debug` | Activa logging adicional (no auditado exhaustivamente en este README). |
| `command` | Comando de cliente para abrir el panel de contratos (`/contracts`). |
| `quarantineAdminCommand` | Comando de cliente para el panel de cuarentena de crafting (`/craftquarantine`). |
| `quarantineAdminAce` | **No usado en código.** No hay ninguna llamada a `IsPlayerAceAllowed` en el recurso; el acceso real al panel es 100% vía `nexus_permissions`. |
| `lotIncidentsCommand` | Comando de cliente para el panel de incidencias de lote (`/supplyincidents`). |
| `rateLimitBucket` | Bucket de `nexus_bridge`/fallback usado para limitar acciones repetidas. |
| `interactDistance` | Distancia de interacción con los puntos de contacto. |
| `security.*` | Parámetros usados **solo** por `server/security_fallback.lua` cuando `nexus_bridge` no está corriendo; en paridad con `nexus_bridge/config/config.lua`. |
| `packageItem` | Nombre del ítem físico de paquete (`ox_inventory`). |
| `expirySweepSeconds` | Frecuencia del barrido que expira lotes vencidos. |
| `actionDurations.pickup` / `.deliver` | Duración en ms de las acciones temporizadas de recogida/entrega. |
| `sceneCore.enabled` / `.pickup` / `.deliver` | Activa la integración con `nexus_scene_core` y los IDs de escena a reproducir. |
| `supply.*` | Configuración del contrato civil: tipo, clave de stock, destino, máximo de lotes simultáneos, contenidos del paquete. |
| `mechanicCrafting.*` | Configuración de la estación de fabricación del mecánico consumida por `nexus_crafting`: estación, receta, ítem/cantidad de salida, grado mínimo de trabajo, duración de reserva, coordenadas, distancia máxima, contenidos consumidos. |
| `contacts.*` | NPCs de contacto (posición, heading, modelo, escenario de animación). |
| `contracts.*` | Definición de cada tipo de contrato (label, descripción, coordenadas de pickup/dropoff, destino, duración). |

## Exportaciones y Eventos

### Exports de servidor

Contrato civil / panel:
```lua
exports.nexus_contracts:getDashboardContracts(source)
exports.nexus_contracts:getDutyboardSnapshot(source)
```

Puente de crafting para `nexus_crafting` (autorizados exclusivamente vía
`GetInvokingResource() == 'nexus_crafting'`):
```lua
exports.nexus_contracts:isMechanicCraftingReady()
exports.nexus_contracts:isMechanicCraftQuarantined(citizenid)
exports.nexus_contracts:getMechanicStockSnapshot(source)
exports.nexus_contracts:reserveMechanicCraft(source, stationId, recipeId)
exports.nexus_contracts:getMechanicCraftReservation(source, reservationId)
exports.nexus_contracts:beginMechanicCraft(source, reservationId)
exports.nexus_contracts:completeMechanicCraft(source, reservationId)
exports.nexus_contracts:releaseMechanicCraft(source, reservationId, reason)
exports.nexus_contracts:markMechanicCraftAmbiguous(source, reservationId, reason)
exports.nexus_contracts:queueMechanicCraftAmbiguousFromCraftingStop(reservationId, citizenid, reason)
```

### Exports de cliente

```lua
exports.nexus_contracts:openContracts()
exports.nexus_contracts:openQuarantinePanel()
exports.nexus_contracts:openLotIncidentsPanel()
```

### Callbacks de servidor (`lib.callback.register`)

```
nexus_contracts:server:getContracts
nexus_contracts:server:prepareAction
nexus_contracts:server:listCraftQuarantines
nexus_contracts:server:recoverCraftQuarantine
nexus_contracts:server:listLotIncidents
nexus_contracts:server:recoverLotIncident
```

### Eventos de servidor (`RegisterNetEvent`)

```
nexus_contracts:server:start
nexus_contracts:server:pickup
nexus_contracts:server:deliver
nexus_contracts:server:cancelPreparedAction
nexus_contracts:server:cancel
```

### Eventos de cliente (`RegisterNetEvent`)

```
nexus_contracts:client:setActive
nexus_contracts:client:clearActive
```

## Comandos y Permisos

| Comando | Quién | Nodo/gate real |
|---|---|---|
| `/contracts` | Cualquier jugador | Sin gate — abre el panel de contrato civil. |
| `/craftquarantine` | Requiere `nexus_permissions.nexus_contracts.quarantine_view` para listar, `nexus_permissions.nexus_contracts.craft_quarantine_recover` para resolver | Sin `nexus_permissions` corriendo, nadie salvo consola (`source == 0`) puede ver ni resolver cuarentenas. |
| `/supplyincidents` | Requiere `nexus_permissions.nexus_contracts.quarantine_view` para listar, `nexus_permissions.nexus_contracts.lot_incident_recover` para resolver | Misma gate que arriba, nodo distinto para la acción de recuperación. |

**Nodos de permiso completos que debe declarar tu integración de
`nexus_permissions`:**

```text
nexus_contracts.quarantine_view
nexus_contracts.craft_quarantine_recover
nexus_contracts.lot_incident_recover
```

El campo `quarantineAdminAce = 'nexus.crafting.admin'` de `config.lua` es
**vestigial**: no existe ninguna llamada a `IsPlayerAceAllowed` en el
recurso, así que ese ACE no gatea nada por sí mismo.
