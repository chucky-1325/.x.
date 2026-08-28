# Flujo obligatorio — nexus-nui-premium

Seis fases secuenciales. Cada fase tiene un entregable y un criterio de salida. No se avanza de fase sin cumplir el criterio de salida de la anterior — en particular, **la fase 4 no empieza sin aprobación explícita del usuario sobre la fase 3**.

## Fase 1 — Auditar la UI existente y el flujo de datos

Solo lectura. Cero cambios en disco, cero reinicios de recursos.

Qué producir:
- Inventario del recurso objetivo: `fxmanifest.lua` (scripts, `ui_page`, `dependency`), estructura de carpetas.
- Mapa del flujo de datos actual: qué eventos/statebags alimentan qué módulo, con qué frecuencia, y si ya hay diff-antes-de-enviar o hay polling a corregir.
- Inventario de tokens usados actualmente (¿usa ya `nexus_ui/shared/tokens.lua`? ¿tiene colores/tamaños hardcodeados que deberían migrar a tokens?).
- Lista de hallazgos fuera de alcance (p. ej. una `dependency` dura hacia otro producto NEXUS) — se registran, no se corrigen aquí salvo petición explícita.

Criterio de salida: informe de auditoría entregado al usuario antes de pasar a la fase 2.

## Fase 2 — Definir objetivo, jerarquía, módulos, estados y presupuesto de rendimiento

Documento, no código.

Qué producir:
- Objetivo del rediseño/implementación en una frase (qué problema resuelve, para quién).
- Jerarquía de módulos: qué se ve siempre, qué aparece condicionalmente, y en qué orden de prioridad visual (ver `design-system.md` §2).
- Lista de módulos con su fuente de dato (evento/statebag/loop acotado) y su condición de visibilidad.
- Matriz de estados por módulo (normal/advertencia/crítico/ausente/timeout — ver `design-system.md` §6).
- Presupuesto de rendimiento explícito: objetivo de impacto en frame time, límite de tamaño de bundle si aplica, límite de mensajes NUI/segundo en el peor caso (p. ej. conduciendo).
- Cualquier token nuevo que se necesite y no exista en `nexus_ui` (color, espaciado, radio) — propuesto aquí, no improvisado después.

Criterio de salida: documento de fase 2 aceptado por el usuario (puede pedir ajustes antes de avanzar).

## Fase 3 — Presentar wireframe y dirección visual (puerta de aprobación)

Qué producir:
- Wireframe de baja/media fidelidad (boxes con jerarquía, o un mock visual si aporta más claridad) de cada estado relevante: HUD en reposo, HUD con alerta crítica, HUD de vehículo, HUD de helicóptero si aplica.
- Dirección visual concreta: qué tokens de `nexus_ui` se usan, qué variante/accent aplica según contexto, cómo se diferencian visualmente los estados sin depender solo del color.
- Explicación breve de cómo las transiciones/microinteracciones se comportan (qué aparece/desaparece y cómo).

**Criterio de salida obligatorio: aprobación explícita del usuario.** No se interpreta silencio o "se ve bien en general" como aprobación para pasar a código si hay elementos del wireframe sin confirmar. Si el usuario pide cambios, se itera dentro de la fase 3 — no se avanza a la fase 4 en paralelo.

## Fase 4 — Implementar por componentes y tokens

Solo tras aprobación de fase 3.

Reglas de esta fase:
- Un componente por responsabilidad (ver `design-system.md` §10), reutilizando componentes ya existentes en otros HUDs NEXUS cuando el patrón se repita.
- Todo valor visual sale de un token (`nexus_ui` o el token nuevo ya aprobado en fase 2), no de un literal nuevo introducido a mitad de implementación.
- El flujo de datos sigue las reglas de `fivem-nui-engineering.md` (eventos, diff-antes-de-enviar, ocultar módulos inactivos) desde el primer commit, no como pulido posterior.
- Cleanup (listeners/timers/animaciones/foco/callbacks) se implementa junto con la feature que lo necesita, no se añade al final como parche.

Criterio de salida: implementación completa de los módulos definidos en fase 2, compilando/cargando sin errores en consola de FiveM/CEF.

## Fase 5 — Validar visualmente en juego, responsive, accesibilidad y coste de cliente

En juego, no solo en navegador. Ver `quality-checklist.md` para la lista exhaustiva. Como mínimo:
- Revisión visual en al menos dos condiciones de mundo distintas (día/noche o interior/exterior) para confirmar contraste real.
- Revisión en 16:9, ultrawide, y al menos un escalado de UI distinto de 100%.
- Verificación de `:focus-visible` y navegación por teclado/mando en cualquier panel con foco NUI.
- Verificación de `prefers-reduced-motion`.
- Medición u observación de coste de cliente (frame time, mensajes NUI en el peor caso) contra el presupuesto definido en fase 2.
- Verificación explícita de cleanup: abrir/cerrar el panel o entrar/salir del contexto (vehículo, helicóptero) varias veces seguidas y confirmar que no quedan listeners/timers/foco huérfanos.

Criterio de salida: cada punto de la fase 5 verificado y sin hallazgos bloqueantes, o hallazgos resueltos antes de pasar a fase 6.

## Fase 6 — Cerrar solo tras checklist de calidad AAA y regresión

Qué producir:
- Checklist de `quality-checklist.md` completo, con cada ítem marcado y con evidencia breve de cómo se verificó.
- Pasada de regresión: confirmar que HUDs/NUIs NEXUS coexistentes (otros overlays activos a la vez) no colisionan visualmente ni compiten por foco/rendimiento con el nuevo/modificado.
- Resumen final para el usuario: qué cambió, qué tokens nuevos se añadieron a `nexus_ui` (si alguno), qué quedó fuera de alcance (hallazgos de fase 1 no resueltos) y coste de cliente medido vs. presupuesto.

Criterio de salida: checklist 100% pasado. Si algún ítem no puede verificarse (p. ej. porque no hay acceso a probar en juego en ese momento), se declara explícitamente como pendiente — nunca se marca como cerrado sin verificación real.
