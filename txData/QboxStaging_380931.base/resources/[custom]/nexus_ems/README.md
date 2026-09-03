# nexus_ems

Sistema clínico y médico de NEXUS para QBox/OX: evaluación primaria y
tratamientos físicos con autoridad 100% server-side, tablet clínica con
estado derivado del paciente, consumo de inventario real y auditoría SQL
antes/después de cada acción.

## Descripción general

Un sanitario evalúa a un paciente cercano (`ox_target` o `/ems`); el
servidor valida job/grado, distancia, que no haya otra acción en curso sobre
ese sanitario o paciente, y rate limit, antes de conceder un **token
temporal** de acción. Cada tratamiento posterior (vendaje, analgesia,
estabilización, reanimación, preparación de traslado) vuelve a revalidar
indicación, rango, materiales y distancia — los materiales se consumen
**después** de completar la acción, nunca al iniciarla, para que una
cancelación no cueste inventario. El resultado queda auditado en
`nexus_medical_events` (estado antes/después en JSON) y otorga progresión al
dominio `ems` si `nexus_progression` está disponible.

Funcionalidades clave:

- 6 acciones configurables: evaluación primaria, vendaje, analgesia,
  estabilización, reanimación avanzada y preparación de traslado.
- Autoridad total en servidor: token temporal por acción, un tratamiento
  concurrente por sanitario/paciente, distancia comprobada al preparar y al
  finalizar.
- Escenas físicas opcionales vía `nexus_scene_core` (animación + prop),
  degrada a resolución instantánea si no está disponible.
- Acceso por job/grado configurable (`config/jobs.lua`), con bypass opcional
  para pruebas administrativas vía `nexus_permissions`.
- Fallback de seguridad vendorizado: si `nexus_bridge` no está corriendo,
  `nexus_ems` sigue aplicando rate limit y ventanas de acción temporizadas
  con su propia copia local (`server/security_fallback.lua`), en vez de
  desactivar la protección.

## Requisitos y Dependencias

### Dependencias duras (`fxmanifest.lua` → `dependencies {}`)

```lua
dependencies {
    'qbx_core',
    'ox_lib',
    'oxmysql',
    'ox_inventory',
    'ox_target',
}
```

Ninguna es otro recurso `nexus_*` — `nexus_ems` es instalable de forma
standalone sobre cualquier base QBox/OX estándar. (La dependencia previa a
`nexus_scene_core` fue retirada: el código ya la trataba como integración
blanda en cada punto de llamada, así que el manifest ahora refleja la
realidad del código.)

### Integraciones blandas (`GetResourceState`, opcionales)

| Recurso | Efecto si está ausente |
|---|---|
| **`nexus_bridge`** | `nexus_ems` cae automáticamente a su **fallback vendorizado** (`server/security_fallback.lua`, valores en paridad con `nexus_bridge/config/config.lua`) — el rate limit y las ventanas de acción temporizada **siguen activos**, no se desactivan. |
| `nexus_scene_core` | Sin él, cada acción se resuelve al instante (sin animación/prop físico) en vez de reproducir la escena configurada (`ems_assessment`, `ems_bandage`, etc.). |
| `nexus_progression` | Sin él, no se otorga XP/reputación al dominio `ems` — el resto del flujo clínico sigue funcionando igual. |
| `nexus_permissions` | Sin él, **no existe** bypass de acceso a médico ni override de grado — el acceso queda estrictamente limitado a los jobs/grados de `config/jobs.lua`. A diferencia de `nexus_territories`/`nexus_crafting`, aquí `nexus_permissions` es un **complemento opcional** (para pruebas admin o overrides puntuales), no la única puerta de acceso: el job sigue siendo el control primario. |
| `nexus_ui` | Si está iniciado, la NUI hereda el design system compartido; si no, usa sus propios estilos. |

## Instalación

1. Copia la carpeta `nexus_ems` a `resources/[custom]/`.
2. Añade en `server.cfg`, después de `ox_lib`, `oxmysql`, `qbx_core`,
   `ox_inventory` y `ox_target`:
   ```cfg
   ensure nexus_ems
   ```
3. Asegura que los jobs de `config/jobs.lua` (`ambulance`, `ems`, `doctor`
   por defecto, o cualquier job con `type = 'ems'`) existen en tu framework.
4. Confirma en `ox_inventory/data/items.lua` que los items usados como
   `items` de cada acción (`bandage`, `painkillers`, `firstaid`, `ifaks`)
   están registrados.
5. **SQL:** no requiere importar ningún archivo — la tabla
   `nexus_medical_events` se crea automáticamente con
   `CREATE TABLE IF NOT EXISTS` en el primer arranque
   (`server/database.lua`).
6. Ajusta el punto de hospital (`hospital` en `config.lua`) a la coordenada
   real de tu mapa.

## Configuración (`config.lua` / `jobs.lua`)

| Clave | Descripción |
|---|---|
| `command` | Comando para evaluar al paciente más cercano (`/ems`). |
| `adminAce` | Presente en config por convención de proyecto pero **no se usa en código** — el acceso real se controla por job (`jobs.lua`) y, opcionalmente, por `nexus_permissions`. |
| `maxPatientDistance` | Distancia máxima al preparar y al finalizar una acción. |
| `actionExpiryGraceMs` | Tolerancia antes de expirar un token de acción abandonado. |
| `hospital` | Coordenada de destino usada por `prepare_transport`. |
| `rateLimitBucket` | Bucket de rate limit (usado tanto por `nexus_bridge` como por el fallback vendorizado). |
| `security.*` | Valores usados **solo** por el fallback local cuando `nexus_bridge` no está corriendo; deben mantenerse en paridad con `nexus_bridge/config/config.lua` si cambias uno de los dos. |
| `scenes.enabled` | Activa/desactiva el uso de `nexus_scene_core` globalmente. |
| `progression.domain` | Dominio de `nexus_progression` que recibe la XP (`ems`). |
| `actions.<id>` | Cada acción: `label`, `description`, `duration`, `scene`, `items` (consumidos al completar), `xp`, `reputation`, y opcionalmente `minGrade` (grado mínimo de job, salvo bypass). |
| `effects.<id>` | Efecto aplicado al paciente al completar cada acción (`bleeding`, `health`, `pain`, `stabilized`, `revive`, `transportReady`). |
| `jobs.lua` → `jobTypes` | Tipos de job (`QBCore` `job.type`) tratados como personal médico sin listar cada nombre. |
| `jobs.lua` → `jobs` | Mapa `job = gradoMinimo` de jobs médicos reconocidos individualmente. |

## Exportaciones y Eventos

`nexus_ems` no expone `exports()` — toda su superficie pública es por
callbacks de `ox_lib` (request/response) y eventos de red, pensada para
integrarse desde la NUI propia o desde otro recurso vía `TriggerEvent`.

### Callbacks de servidor (`lib.callback`)

```text
nexus_ems:server:canUse()                       -- ¿el jugador es personal medico?
nexus_ems:server:prepareAction(target, actionId) -- inicia una accion, devuelve token
nexus_ems:server:finishAction(actionToken)       -- valida y aplica el resultado
nexus_ems:server:getPatient(target)              -- estado derivado del paciente para la tablet
```

### Eventos de servidor (`RegisterNetEvent`)

`nexus_ems:server:cancelAction` (cancela una acción en curso, llamado
también automáticamente al desconectar/reiniciar desde `onResourceStop`).

### Eventos de cliente

`nexus_ems:client:applyTreatment` (aplica el resultado visual/estado del
tratamiento recibido del servidor).

## Comandos y Permisos

| Comando | Quién | Nota |
|---|---|---|
| `/ems` | Job en `jobs.lua` (`ambulance`, `ems`, `doctor` por grado, o cualquier job `type = 'ems'`) | Evalúa al paciente más cercano dentro de `maxPatientDistance`. |
| Acceso desde `ox_target` | Mismo control de job que `/ems` | Verificado en servidor en cada `prepareAction`, no solo al mostrar la opción de target. |

El acceso de administración de pruebas (usar EMS sin tener el job) y el
override puntual de grado mínimo (por ejemplo, para probar `resuscitate` sin
ser grado 1) se conceden vía `nexus_permissions`, no vía comando ni ACE:

```text
nexus_ems.medic_access_bypass   -- trata al jugador como medico sin serlo
nexus_ems.grade_override        -- ignora minGrade de una accion concreta
```

Sin `nexus_permissions` corriendo, ninguno de los dos bypass existe — el
acceso queda estrictamente ligado al job real del jugador, que es el
comportamiento correcto para producción.
