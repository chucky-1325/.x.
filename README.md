# NEXUS — Staging Source

Este repositorio es **staging source-only**: contiene unicamente el codigo
fuente de los recursos `nexus_*` tal como viven en el perfil de staging
(`txData/QboxStaging_380931.base/resources/[custom]/nexus_*/`).

**Producción, secretos y datos runtime quedan excluidos** por diseño (ver
`.gitignore`). Explícitamente fuera de este repositorio:

- Cualquier copia de producción (`QboxStable`) o de otros perfiles.
- `server.cfg` y variantes (`sv_licenseKey`, `steam_webApiKey`,
  `mysql_connection_string`, contraseñas de txAdmin).
- Claves y certificados (`*.key`, `*.pem`, `*.crt`).
- Dumps y backups de base de datos (`*.sql` fuera de `nexus_*/sql/`).
- Datos runtime de txAdmin/FXServer (`txData/**` salvo el código fuente
  listado abajo, `logs/`, `backups/`, binarios del servidor).
- Documentación interna y scripts de entorno local (`*.md` de raíz salvo
  este archivo, `*.bat`, `docs/`, `.codex/`).

## Qué SÍ incluye

Todo el árbol de cada recurso `nexus_*` bajo staging: `client/`, `server/`,
`config/`, `shared/`, `html/` (NUI) y `sql/` (schema/migraciones reales del
recurso). El esquema/migraciones SQL propios de cada recurso son la única
excepción a la exclusión general de `.sql`.

## Recursos versionados

`nexus_blackmarket`, `nexus_bridge`, `nexus_contracts`, `nexus_crafting`,
`nexus_dispatch`, `nexus_dutyboard`, `nexus_ems`, `nexus_gangs`,
`nexus_labs`, `nexus_laundering`, `nexus_menu`, `nexus_operations`,
`nexus_progression`, `nexus_scene_core`, `nexus_tablet`, `nexus_territories`,
`nexus_ui`.
