# DEPLOYMENT — Pack Turnkey NEXUS

Manual de despliegue del stack NEXUS sobre una base QBox/OX ya funcional.
Modalidad de entrega: **Source-Available** — código fuente `.lua` sin
encriptar, amparado legalmente por [`LICENSE.md`](LICENSE.md). No requiere
Asset Escrow ni cuenta Keymaster para instalarse.

## Alcance de este pack

Este documento cubre **solo los recursos `nexus_*`** de este repositorio.
Asume que ya tienes una base QBox/OX estándar funcionando (`qbx_core`,
`ox_lib`, `oxmysql`, `ox_target`, `ox_inventory` como mínimo). Recursos
como garajes, banco, apariencia, teléfono o MDT policial **no están
incluidos** — instálalos según la documentación estándar de QBox o tus
propias alternativas; NEXUS se integra con ellos de forma blanda donde
aplica (ver cada `README.md` de recurso, sección "Integraciones blandas").

## 1. Requisitos de infraestructura

- Windows/Linux con FXServer actualizado (build ≥ 3258 recomendado, el mismo validado durante el desarrollo de este pack).
- MySQL o MariaDB **10.4+** activo y accesible.
- Licencia de servidor válida (Keymaster) y Steam Web API Key (opcional, requerida solo para funciones dependientes de Steam).
- Base QBox/OX estándar ya instalada y arrancando sin errores **antes** de añadir NEXUS.

### Base de datos — verificación previa obligatoria

Antes de apuntar `mysql_connection_string` a cualquier instancia:

1. Confirma que la instancia arranca limpio (`mysqld --version` y un `SELECT 1` de prueba).
2. Si reutilizas una instancia con historial de incidentes o corrupción previa, valida con `mysqlcheck --all-databases` (InnoDB) o `aria_chk --datadir=<ruta>` (Aria/MyISAM) **antes** de importar nada — no asumas que "arranca" significa "sana".
3. Crea una base de datos y un usuario dedicados para el servidor, con privilegios acotados a esa base (no uses `root` en producción).

## 2. Importación SQL

Ningún recurso `nexus_*` requiere importar un archivo `.sql` manualmente
— cada uno crea sus propias tablas con `CREATE TABLE IF NOT EXISTS` en su
primer arranque (`server/database.lua` de cada recurso). Lo único que
necesitas hacer:

1. Tener importado el SQL base de tu framework QBox/OX (`qbx_core.sql` y el de tus recursos de inventario/target/etc.) — **esto es requisito previo de tu base, no de NEXUS**.
2. Registrar en `ox_inventory/data/items.lua` los items que usan las recetas/acciones de NEXUS (bandage, painkillers, firstaid, lockpick, nexus_spraycan, nexus_graffiti_remover, nexus_contract_package, etc. — ver la sección "Instalación" de cada `README.md` de recurso para la lista exacta que usa).
3. Arrancar el servidor una vez con todos los `nexus_*` en `ensure`: las tablas se crean solas. No hace falta ningún paso SQL manual adicional.

`nexus_workorders` es la única excepción: solo trae migraciones SQL
(`sql/001` a `007`) sin código de recurso todavía — **no lo actives**, no
está listo para producción (ver auditoría comercial).

## 3. Puesta en marcha

1. Copia `server.cfg.example` a `server.cfg` dentro de tu perfil de datos y completa los placeholders (`YOUR_CFX_KEY`, `YOUR_STEAM_KEY`, `YOUR_DB_USER`, `YOUR_DB_PASSWORD`).
2. Copia la carpeta de cada recurso `nexus_*` a `resources/[custom]/` de tu base.
3. Arranca FXServer apuntando a tu perfil (vía txAdmin o `+set serverProfile <perfil> +set txDataPath <ruta>`).
4. Confirma en consola que los 18 recursos `nexus_*` arrancan sin `SCRIPT ERROR` (ver la lista completa en `server.cfg.example` — nota que corrige dos omisiones encontradas en la configuración de referencia interna: **`nexus_permissions` y `nexus_dutyboard` no estaban en el `ensure` de producción original**, aunque ambos son recursos reales, implementados y validados; este pack sí los incluye).

### Permisos — paso obligatorio de primer arranque

`nexus_permissions` no concede nada por defecto. Sin al menos un rol
asignado, **todos los paneles de administración/editor de los 11 recursos
migrados a RBAC quedan completamente inaccesibles**, incluso para el grupo
`admin` de ACE. Desde la consola del servidor (siempre autorizada,
`source == 0`, no necesita ACE):

```text
grantrole <tu_citizenid> admin "setup inicial"
```

Verifica el resultado con el jugador correspondiente conectado antes de dar
por cerrado el despliegue. `revokerole <citizenid> <role>` revierte.

## 4. Reglas Operativas

### P0 — `nexus_ems` y hot-restarts

> **Comportamiento mitigado mediante secuencia de arranque inicial. Se
> prohíbe realizar hot-restarts (`restart nexus_ems`) con usuarios en
> sesión debido a una desincronización de la capa NUI/CEF del motor de
> FiveM.**

En la práctica: usa `ensure nexus_ems` únicamente durante el arranque
completo del servidor, con cero jugadores conectados. Para aplicar cambios
de configuración con el servidor en producción, programa un reinicio
completo del proceso FXServer (no un `restart` en caliente del recurso) en
una ventana de mantenimiento anunciada. Esta regla aplica en general a
cualquier recurso `nexus_*` con jugadores conectados — no solo a
`nexus_ems`, que es donde el disparador se reprodujo de forma
determinística.

### Nota operativa — cambios de `cfgPath` en txAdmin

Cambiar el parámetro `cfgPath` en `txData/default/config.json` (o el
`config.json` de tu propio perfil) **requiere reiniciar por completo el
proceso ejecutable `FXServer.exe`**. El botón de reinicio básico de la
interfaz web de txAdmin ("Restart Server") solo reinicia la capa interna del
juego dentro del proceso ya corriendo — **no relee las rutas de
configuración del JSON**. Verificado en vivo durante el smoke test de este
pack: tras editar `cfgPath`, el "Restart Server" siguió arrancando el
perfil anterior; solo tomó efecto tras matar el proceso `FXServer.exe`
completo y relanzarlo desde cero.

### Orden de arranque

Respeta el orden de `ensure` de `server.cfg.example`. `nexus_bridge` y
`nexus_permissions` van primero porque el resto de recursos los detecta en
caliente vía `GetResourceState` — si arrancan después, no rompen nada, pero
degradan (rate limit fail-closed sin `nexus_bridge`; paneles de admin
bloqueados sin `nexus_permissions`) hasta que ambos estén corriendo.

## 5. Modelo de entrega

Este pack se entrega en modalidad **Source-Available**: código fuente
completo, editable, sin protección técnica de Asset Escrow — la protección
es exclusivamente legal, vía `LICENSE.md`. Queda expresamente prohibida su
redistribución, reventa o publicación no autorizada (ver `LICENSE.md`,
Sección 2). Para venta individual de módulos sueltos protegidos con Asset
Escrow (Tier Tebex), ver la estrategia dual documentada en la Fase C de la
auditoría comercial — ese canal usa `escrow_ignore` sobre `config/*.lua` y
`locales/*.lua` de cada recurso, no este documento.
