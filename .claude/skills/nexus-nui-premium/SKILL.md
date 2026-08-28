---
name: nexus-nui-premium
description: "Use when designing, auditing, or implementing any FiveM/NEXUS NUI or HUD interface — player HUD, vehicle HUD, helicopter HUD, or any nexus_*/qbx_*_aaa UI — that must reach AAA commercial polish: refined visuals, very low client cost, accessibility, and modular sellable architecture. Trigger: `/nexus-nui-premium`."
---

# /nexus-nui-premium

Diseña e implementa NUI/HUD de FiveM con nivel de pulido comercial AAA para el ecosistema NEXUS — funcionalmente inspirado en HUDs de rol modernos de alto pulido (p. ej. Prodigy RP) **sin copiar assets ni diseño literal de ningún producto de terceros**.

Esta skill cubre HUD de jugador, HUD de vehículo, HUD de helicóptero (activación condicional), y cualquier NUI NEXUS futura que quiera el mismo nivel de calidad. No es una skill de "hazme un HUD rápido" — es un proceso de diseño+ingeniería con puertas de aprobación explícitas.

## Alcance y anclaje en el proyecto (leer primero, siempre)

Antes de proponer nada, esta skill asume que **ya existe** un design system compartido en este repo y que debe extenderse, no duplicarse ni reinventarse:

- [`nexus_ui/shared/tokens.lua`](../../../txData/QboxStaging_380931.base/resources/%5Bcustom%5D/nexus_ui/shared/tokens.lua) — tokens base: `radius`, `colors` (bg/surface/glass/border/text/muted/success/warning/danger/info), `fonts` (ui = Inter/system-ui, mono = JetBrains Mono).
- [`nexus_ui/config/config.lua`](../../../txData/QboxStaging_380931.base/resources/%5Bcustom%5D/nexus_ui/config/config.lua) — `variants` por facción/contexto (civil/police/ems/illegal/gov/business/mafia) con su `accent`, más config de sonido.
- [`qbx_hud_aaa/client/main.lua`](../../../txData/QboxStaging_380931.base/resources/%5Bcustom%5D/qbx_hud_aaa/client/main.lua) — patrón de referencia ya en producción para "no reenviar si no cambió" (`shallowEqual` + cache `last`), sincronización por `RegisterNetEvent`/`AddStateBagChangeHandler`, no polling.
- `qbx_hud_aaa/html/index.html` — bundle NUI existente (revisar antes de proponer un rediseño; puede ser el propio objeto de la reforma).

Cualquier trabajo bajo esta skill empieza leyendo estos archivos reales del recurso objetivo, no asumiendo estructura genérica. Ver [references/fivem-nui-engineering.md](references/fivem-nui-engineering.md) §"Inspeccionar antes de proponer".

## Reglas no negociables

**Diseño y calidad visual** — detalle completo en [references/design-system.md](references/design-system.md):
- Diseño antes que código: jerarquía, tokens semánticos, escala de espaciado y tipografía definidos y aprobados antes de escribir un componente.
- Todo estado se diseña completo (default/hover/focus/active/disabled/loading/error/empty), no solo el "happy path".
- Microinteracciones sutiles y con propósito; nunca decorativas o ruidosas.
- Responsive real: 16:9, 21:9/ultrawide, distintos `sv_maxclients`-independientes escalados de UI, distintas resoluciones.
- Accesibilidad no opcional: contraste AA mínimo, `:focus-visible` en todo control interactivo, `prefers-reduced-motion` respetado.
- Prohibido el "AI slop UI": sin gradientes genéricos sin propósito, sin iconografía inconsistente, sin espaciado arbitrario no ligado a la escala, sin componentes que no se integran con los tokens NEXUS ya existentes.

**Ingeniería FiveM/NUI** — detalle completo en [references/fivem-nui-engineering.md](references/fivem-nui-engineering.md):
- La NUI recibe datos por eventos/cambios de estado (`SendNUIMessage`, statebags, `RegisterNetEvent`). Prohibido el polling continuo o el render en bucle sin condición de cambio.
- Actualizar solo cuando cambie un dato relevante (diff antes de enviar, como ya hace `qbx_hud_aaa`); ocultar/desmontar módulos inactivos en vez de dejarlos invisibles pero vivos.
- Cleanup obligatorio y verificado: listeners, timers/`SetInterval`, animaciones en curso, foco NUI (`SetNuiFocus`), callbacks (`RegisterNUICallback`) — nada debe sobrevivir a un cierre de HUD o un resource stop.
- Toda validación de dato o acción sensible ocurre en servidor. La NUI nunca es autoridad — solo presenta lo que el servidor ya validó.
- Compatible con teclado y mando, con distintas resoluciones, ultrawide y escalado de UI.
- Cada HUD/producto `nexus_*` debe funcionar sin dependencia dura de otro producto NEXUS — solo adaptadores opcionales/soft (ver memoria del proyecto: sistemas vendibles standalone).

## Flujo obligatorio (6 fases, con puertas de aprobación)

Detalle completo, entregables y criterios de salida de cada fase en [references/workflow.md](references/workflow.md). Resumen:

1. **Auditar** la UI existente y el flujo de datos del HUD objetivo — solo lectura, sin cambios.
2. **Definir** objetivo, jerarquía, módulos, estados y presupuesto de rendimiento — documento, sin código.
3. **Presentar** wireframe y dirección visual — **puerta de aprobación explícita del usuario antes de tocar código**.
4. **Implementar** por componentes y tokens — solo tras la aprobación de la fase 3.
5. **Validar** en juego: visual, responsive, accesibilidad y coste de cliente.
6. **Cerrar** solo tras pasar el checklist de calidad AAA y una pasada de regresión — ver [references/quality-checklist.md](references/quality-checklist.md).

No saltar fases. No empezar la fase 4 sin que el usuario haya aprobado explícitamente el wireframe/dirección de la fase 3.

## Especificación funcional de los módulos NEXUS

Ver [references/module-specs.md](references/module-specs.md) para el desglose completo de:
- HUD de jugador (salud, armadura, hambre, sed, estrés, voz/proximidad, brújula, estados relevantes)
- HUD de vehículo (velocidad, RPM, marcha, combustible, motor, cinturón)
- HUD de helicóptero (altitud, rumbo, rotor, datos de vuelo — activación condicional solo en el contexto correcto)
- Configurabilidad (logo, colores, módulos, visibilidad) y reglas de contexto adaptativo (no saturar pantalla, ocultar lo irrelevante)

## Cómo invocar esta skill

`/nexus-nui-premium <objetivo>` — por ejemplo: `/nexus-nui-premium auditar y proponer rediseño del HUD de jugador en qbx_hud_aaa`. La skill siempre entra por la fase 1 (auditoría), salvo que el usuario indique explícitamente que ya se hizo y quiere retomar en una fase posterior.
