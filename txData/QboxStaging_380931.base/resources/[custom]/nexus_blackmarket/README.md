# nexus_blackmarket

Mercado negro NEXUS: contactos clandestinos en el mapa que venden blueprints
raros de crafting ilegal, con heat dinamico por punto de venta, descuento por
reputacion/territorio y riesgo de alerta policial.

## Descripción general

`nexus_blackmarket` coloca PNJs "contacto" en ubicaciones fijas de
`config.lua` donde el jugador puede comprar blueprints (`catalog`) a cambio de
efectivo. Cada punto de venta acumula **heat** propio que decae con el tiempo
y encarece el precio mientras sube; comprar también tiene una probabilidad de
alertar a la policía, que crece con el heat acumulado. El acceso al mercado y
a cada contacto individual depende de reputación criminal o pertenencia a
banda, y los precios se ajustan con descuentos por reputación y, si el
contacto cae dentro de una zona de `nexus_territories` controlada por la
banda del jugador, con un descuento territorial adicional.

Funcionalidades clave:

- Catálogo de blueprints con stock limitado, requisitos de reputación/nivel de crafting y precio dinámico por heat + descuentos.
- Heat por ubicación con decaimiento periódico configurable y alerta a jugadores con `job` policial.
- Integración opcional con `nexus_territories`: descuento si la banda controla la zona, heat/alerta agravados si la zona está en manos rivales, y aporte de influencia territorial tras cada compra.
- Panel de dashboard (`getDashboardMarkets`) para que `nexus_menu` u otro panel externo muestre todos los mercados de un jugador.

## Requisitos y Dependencias

`nexus_blackmarket` **no declara ningún bloque `dependencies {}`** en su
`fxmanifest.lua` — arranca aislado y no falla si ningún otro recurso
`nexus_*` está presente.

### Requeridas para funcionar (no son `nexus_*`, siempre deben estar presentes)

| Recurso | Uso |
|---|---|
| `ox_lib` | `lib.callback`, `lib.registerContext`/`lib.showContext`, `lib.showTextUI`, `lib.notify` de respaldo |
| `oxmysql` | Persistencia de logs de compra y estado de heat |
| `qbx_core` | Identidad de jugador (`GetPlayer`, `citizenid`) — se verifica en runtime, degrada sin crashear si falta |
| `ox_inventory` | Entrega del blueprint comprado (`AddItem`) y validación de espacio (`CanCarryItem`) — sin él, `canCarry` siempre devuelve `false` y ninguna compra puede completarse |

### Integraciones blandas (`GetResourceState`, opcionales)

| Recurso | Efecto si está ausente |
|---|---|
| **`nexus_permissions`** | `hasAccessBypass`/`hasDistanceBypass` (nodos `nexus_blackmarket.access_bypass` y `nexus_blackmarket.distance_bypass`) devuelven siempre `false` para cualquier jugador real — solo la consola del servidor (`source == 0`) conserva el bypass. Sin `nexus_permissions` nadie puede saltarse los requisitos de reputación/distancia; el mercado sigue funcionando con sus reglas normales. |
| **`nexus_bridge`** | El rate limit de `getMarket`/`buy` pasa a **fail-closed**: si `nexus_bridge` no está corriendo, `rateLimit()` devuelve `false` y bloquea la acción en vez de dejarla sin límite. |
| `nexus_territories` | Sin él, no hay descuento territorial ni heat/alerta agravada en zona rival, y las compras no aportan influencia territorial (`addInfluenceAtCoords`) — el mercado funciona igual mecánicamente, solo pierde ese matiz. |
| `nexus_progression` | Sin él, `getProgress` devuelve `{}` (reputación criminal 0, sin nivel de crafting) — los requisitos de catálogo que dependen de progresión nunca se satisfacen, y no se otorga XP/reputación tras comprar. |
| `nexus_gangs` | Sin él, el nombre de banda se obtiene de `PlayerData.gang` nativo de QBox en lugar de la gestión de `nexus_gangs` — sigue funcionando, con menos granularidad. |
| `nexus_ui` | Si está iniciado, las notificaciones del cliente usan `exports.nexus_ui:notify` (design system compartido); si no, cae en `lib.notify` de `ox_lib`. |

## Instalación

1. Copia la carpeta `nexus_blackmarket` a `resources/[custom]/`.
2. Añade en `server.cfg`:
   ```cfg
   ensure nexus_blackmarket
   ```
   Según el orden de arranque validado de la suite NEXUS, `nexus_blackmarket`
   se ubica **después** de `nexus_crafting` y **antes** de `nexus_contracts`:
   ```
   ..., nexus_dutyboard, nexus_crafting, nexus_blackmarket, nexus_contracts, nexus_operations, ...
   ```
   Arranca después de `nexus_territories`, `nexus_permissions`, `nexus_gangs`,
   `nexus_progression` y `nexus_bridge` para que las integraciones blandas se
   detecten desde el primer arranque (si se inician después, se detectan en
   la siguiente llamada sin reiniciar `nexus_blackmarket`).
3. **SQL:** no requiere importar ningún archivo — las tablas
   (`nexus_blackmarket_logs`, `nexus_blackmarket_state`) se crean
   automáticamente con `CREATE TABLE IF NOT EXISTS` en el primer arranque del
   recurso (`server/database.lua`, hook `onResourceStart`). El repo incluye
   además `sql/install.sql` con la definición de `nexus_blackmarket_logs`
   (no de `nexus_blackmarket_state`) como referencia/import manual opcional;
   no hace falta ejecutarlo para que el recurso funcione.
4. Registra los items del catálogo (`blueprint_lockpick`,
   `blueprint_advanced_repairkit`, `blueprint_drill`, `blueprint_thermite`,
   u otros que definas) en `ox_inventory/data/items.lua`.
5. Ajusta `locations` y `catalog` en `config/config.lua` a tu mapa y economía.

## Configuración (`config.lua`)

| Clave | Descripción |
|---|---|
| `debug` | Existe en config pero **no se referencia en ningún otro archivo del recurso** — flag muerto, no activa logging adicional. |
| `command` / `nearestCommand` | Comandos para abrir un contacto por id (`/blackmarket [locationId]`) o el más cercano (`/blackmarketnear`). |
| `adminAce` | **Dead config.** El propio archivo lo marca en comentario: "ya no se usa — el acceso admin ahora lo decide `nexus_permissions`". No se lee en ningún lugar del código. |
| `rateLimitBucket` | Bucket de `nexus_bridge` para `getMarket`/`buy`. |
| `heat.*` | Activación, intervalo/monto de decaimiento, precio por punto de heat, multiplicador máximo de precio, probabilidad base y por-heat de alerta policial, y tabla `policeJobs` que decide qué `job` recibe la alerta. |
| `reputationDiscount.*` | Activación, reputación mínima, porcentaje de descuento por punto de reputación y descuento máximo. |
| `access.requireGangOrCriminalRep` / `access.minimumCriminalReputation` | Si es `true`, exige banda real o reputación criminal mínima para usar cualquier mercado. |
| `worldUi.*` | Distancia de dibujo/interacción del marcador 3D y su color/escala. |
| `locations.*` | Cada contacto: label, coords, heading, escenario/modelo del PNJ y reputación criminal mínima para acceder a ese contacto en particular. |
| `catalog.*` | Cada blueprint: label, item, precio base, tipo de dinero, stock inicial, requisitos (`criminalReputation`/`craftingLevel`/`craftingReputation`) y heat que genera al comprarlo. |

## Exportaciones y Eventos

### Exports de servidor

```lua
exports.nexus_blackmarket:getDashboardMarkets(source)
```

### Exports de cliente

```lua
exports.nexus_blackmarket:openMarket(locationId)
```

### Callbacks de servidor (`lib.callback.register`)

```lua
nexus_blackmarket:server:getMarket
```

### Eventos de servidor (`RegisterNetEvent`)

```lua
nexus_blackmarket:server:buy
```

### Eventos de cliente (`RegisterNetEvent`)

```lua
nexus_blackmarket:client:refresh
nexus_blackmarket:client:policeAlert
```

## Comandos y Permisos

| Comando | Quién | Nota |
|---|---|---|
| `/blackmarket [locationId]` | Cualquier jugador | Abre el contacto indicado (por defecto `rancho_contact`) si cumple los requisitos de acceso/distancia. |
| `/blackmarketnear` | Cualquier jugador | Abre el contacto más cercano dentro de `worldUi.interactDistance + 1.0`. |

Este recurso **no tiene comandos administrativos ni gate de tipo ACE**. El
único control de acceso vía `nexus_permissions` son dos bypasses opcionales
que un rol puede recibir para saltarse los requisitos normales de compra:

```text
nexus_blackmarket.access_bypass
nexus_blackmarket.distance_bypass
```

Sin `nexus_permissions` corriendo, ningún jugador (salvo la consola,
`source == 0`) tiene estos bypasses — el mercado exige sus reglas normales de
reputación/banda y distancia para todos.
