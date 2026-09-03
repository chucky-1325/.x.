# nexus_menu

Menú contextual central de NEXUS (`ox_lib` context menu, tecla `F5` /
comando `/nexus`): punto de entrada único a teléfono, tablets por rol
(policial/EMS/ilegal), bandas, territorios, operaciones, crafting y
progresión, más un panel de administración con herramientas de prueba
(kits de items, boost de XP/reputación, influencia de territorio) para
validar el resto del stack NEXUS sin tocar la base de datos a mano.

## Descripción general

El menú principal se construye dinámicamente en `registerMainMenu()` según
el resultado de `getAccess()` (callback de servidor): las entradas de
policía/EMS/ilegal solo aparecen si el jugador tiene el job/gang
correspondiente (o si es admin, que actúa como bypass universal de
visibilidad), y la entrada "Admin pruebas" solo aparece si `access.admin`
es `true`. La mayoría de las acciones administrativas del panel de pruebas
no llaman a exports directamente, sino que ejecutan comandos de otros
recursos (`ExecuteCommand('territoryeditor')`, `ExecuteCommand('noclip')`,
etc.) — el gate real de esas acciones vive en el recurso dueño de cada
comando, no en `nexus_menu`. Las tres acciones que sí mutan estado
directamente desde este recurso (dar kit de items, otorgar XP/reputación de
`nexus_progression`) pasan por `nexus_permissions` en el servidor antes de
ejecutarse.

## Requisitos y Dependencias

`nexus_menu` **no declara ningún bloque `dependencies {}` ni `dependency`**
en su `fxmanifest.lua`.

### Hallazgo: dependencia dura no declarada

Igual que `nexus_bridge`, `shared_scripts` incluye `'@ox_lib/init.lua'` de
forma incondicional, y el código usa `lib.callback.register`,
`lib.registerContext`, `lib.showContext` y `lib.notify` sin ningún guard en
la mayoría de los casos (solo `isAdmin()`/`getAccess()` envuelven la llamada
en `pcall`, y eso protege contra el fallo del callback, no contra `ox_lib`
ausente). Si `ox_lib` no está iniciado, `nexus_menu` no llega a arrancar —
es una dependencia dura de facto, sin declarar en el manifiesto.

### Integraciones blandas (`GetResourceState`, opcionales)

| Recurso | Efecto si está ausente |
|---|---|
| **`nexus_permissions`** | `hasAdminAccessBypass`/`hasGiveKitBypass`/`hasGrantProgressionBypass` devuelven `false` para cualquier jugador real — **todo el panel de administración queda invisible/bloqueado** (solo `source == 0`, consola, conserva el bypass). Sin él, nadie en el juego puede ver "Admin pruebas" en el menú ni ejecutar `giveAdminKit`/`addCraftingProgress`/`addDomainProgress`. |
| `qbx_core` | `getCitizenId`/`getPlayerData` (servidor) devuelven `nil` — las acciones de otorgar kit/progreso fallan con notificación de error controlada ("CitizenID no disponible") en vez de crashear. |
| `nexus_ui` | La función `notify` (cliente) usa `exports.nexus_ui:notify` si está iniciado; si no, cae a `lib.notify` de `ox_lib` con el mismo payload — degrada de estilo, no de funcionalidad. |
| `nexus_progression` | `openProgression`, `addCraftingProgress` y `addDomainProgress` notifican "Progresión no iniciada" / "nexus_progression no iniciado" y no hacen nada — no crashea. |
| `nexus_territories` | `addNearbyInfluence` y `openInfluenceZoneMenu` notifican "Territorios no iniciado" y abortan. |
| `nexus_gangs` | `addGangReputation` notifica "Bandas no iniciado" y aborta. |
| `nexus_tablet` | Las entradas de tablet (policial/ilegal) en el menú principal verifican `GetResourceState` antes de abrir; si no está, notifican "Tablet NEXUS no iniciada" en vez de intentar el export. |
| `ox_inventory` | `giveAdminKit` (servidor) responde "ox_inventory no iniciado" y no entrega ningún item del kit. |
| `qbx_phone_aaa`, `nexus_crafting`, `nexus_operations`, `nexus_laundering`, `nexus_gangs` (assets), `qbx_item_ui` | Todos estos se abren vía el helper genérico `safeCall(resource, exportName, ...)`, que primero comprueba `GetResourceState` y notifica error si el recurso no está iniciado, y además envuelve la llamada al export en `pcall` para no crashear el cliente si el export falla igualmente. |

## Instalación

1. Copia la carpeta `nexus_menu` a `resources/[custom]/`.
2. **SQL: no aplica.** No existe `server/database.lua`, ninguna carpeta
   `sql/`, ni una sola sentencia `CREATE TABLE` en el recurso — no persiste
   nada; toda la lógica de acceso/kits es config estático + consultas en
   vivo a otros recursos.
3. Añade en `server.cfg`:
   ```cfg
   ensure ox_lib
   ensure nexus_menu
   ```
   `nexus_menu` va **al final** del stack NEXUS: es un agregador que
   integra (siempre de forma blanda) con prácticamente todos los demás
   recursos, así que debe arrancar después de todos ellos para que sus
   chequeos `GetResourceState` los detecten desde el primer render del menú
   (si alguno arranca después, `nexus_menu` lo detecta igual en la siguiente
   interacción, sin necesidad de reiniciarlo):
   ```
   nexus_bridge, nexus_permissions, nexus_ui, nexus_scene_core, nexus_ems, nexus_tablet,
   nexus_progression, nexus_dispatch, nexus_gangs, nexus_territories, nexus_dutyboard,
   nexus_crafting, nexus_blackmarket, nexus_contracts, nexus_operations, nexus_labs,
   nexus_laundering, nexus_menu
   ```
4. Para vender/instalar con panel de administración funcional, `nexus_permissions`
   debe estar corriendo y el operador debe tener el rol/permiso
   `nexus_menu.admin_access` (ver sección de comandos y permisos) — sin él,
   el recurso arranca y el menú principal funciona, pero nadie ve el panel
   de pruebas.

## Configuración (`config.lua`)

| Clave | Descripción |
|---|---|
| `command` | Comando de chat que abre el menú (`/nexus`). |
| `key` | Tecla mapeada (`RegisterKeyMapping`) para abrir el menú (`F5` por defecto). |
| `admin.ace` | **Dead/unused.** El propio archivo lo documenta en un comentario: "ace ya no se usa — el acceso admin ahora lo decide `nexus_permissions`". No se lee en ningún punto de `client/main.lua` ni `server/main.lua` — el backdoor de `identifier` hardcodeado que existía antes fue retirado sin sustituto, y este campo quedó como remanente sin efecto. |
| `admin.kits.<id>.label` / `.items` | Catálogo de kits administrativos entregables con `giveAdminKit(kitId)` — cada item es `{ item, count }` pasado a `exports.ox_inventory:AddItem`. Kits incluidos: `crafting_materials`, `blueprints`, `illegal_test`, `illegal_loop_v1`, `ems_test`. |
| `access.policeJobs` | Mapa de nombres de job que cuentan como "policía" en `getAccess()` (además de cualquier job con `type == 'leo'`). |
| `access.emsJobs` | Igual que `policeJobs`, para EMS (además de `type == 'ems'`). |
| `itemDemos` | Lista de `{ label, kind }` usada solo por el submenú "Fichas de item" (`openItemMenu`), una demo de UI contextual que ejecuta `ficha <kind>` — no otorga ni consulta items reales. |

## Exportaciones y Eventos

### Exports de cliente

```lua
exports.nexus_menu:openMenu()
```

### Exports de servidor

No se encontró ningún `exports(...)` en `server/main.lua`.

### Callbacks de servidor (`lib.callback.register`)

```lua
nexus_menu:server:isAdmin
nexus_menu:server:getAccess
nexus_menu:server:getIllegalValidationStatus
```

### Eventos de servidor (`RegisterNetEvent`)

```lua
nexus_menu:server:giveAdminKit
nexus_menu:server:addCraftingProgress
nexus_menu:server:addDomainProgress
```

### Eventos de cliente

No se encontró ningún `RegisterNetEvent` en `client/main.lua` — el cliente
solo escucha resultados de callbacks (`lib.callback.await`) y dispara
eventos hacia servidor, no al revés.

## Comandos y Permisos

| Comando | Quién | Nodo/gate real |
|---|---|---|
| `/nexus` (o el valor de `config.command`) | Cualquier jugador | Sin restricción — abre el menú principal, cuyo contenido ya varía según `getAccess()`. |

No hay más `RegisterCommand` en este recurso — el resto de la superficie
administrativa se activa por visibilidad de opciones dentro del propio menú
(`lib.registerContext`), no por comandos de texto adicionales.

**Gates reales, vía `exports.nexus_permissions:hasPermission`:**

| Acción | Nodo de `nexus_permissions` | Nota |
|---|---|---|
| Ver "Admin pruebas" en el menú / abrir el panel | `nexus_menu.admin_access` | También cubre el callback `getIllegalValidationStatus` (panel de diagnóstico de estado de recursos, solo lectura) y el flag `access.admin` devuelto por `getAccess`, que a su vez actúa como bypass de visibilidad para las secciones policía/EMS/ilegal del menú principal. |
| `giveAdminKit` (entregar cualquier kit de `config.admin.kits`) | `nexus_menu.give_kit` | Evento `nexus_menu:server:giveAdminKit`. |
| `addCraftingProgress` / `addDomainProgress` (otorgar XP/reputación manualmente) | `nexus_menu.grant_progression` | Eventos `nexus_menu:server:addCraftingProgress` / `...:addDomainProgress`. |

En los tres casos, `source == 0` (consola) siempre está autorizado, y si
`nexus_permissions` no está corriendo (`GetResourceState != 'started'`) el
resultado es `false` para cualquier jugador real — fail-closed, no fail-open.
No se encontró ningún uso de `IsPlayerAceAllowed` en este recurso.
