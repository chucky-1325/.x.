# Checklist de cierre AAA + regresión — nexus-nui-premium

Se completa en la fase 6 del flujo. Todo ítem debe verificarse con evidencia real (en juego, en código, o medición), no darse por hecho. Un ítem no verificable se marca como pendiente explícito, nunca como aprobado por defecto.

## Diseño y visual

- [ ] Jerarquía visual coincide con la definida en fase 2 (lo crítico pesa más, lo contextual no ocupa espacio fijo).
- [ ] Todo color/tamaño/radio/tipografía sale de un token de `nexus_ui` o de un token nuevo explícitamente aprobado en fase 2/3 — cero literales sueltos.
- [ ] Escala de espaciado respetada en todos los componentes nuevos/modificados.
- [ ] Todos los estados definidos en la matriz de fase 2 están implementados (normal/advertencia/crítico/ausente/timeout, según aplique por módulo).
- [ ] Microinteracciones presentes solo donde comunican algo (cambio de valor, aparición/desaparición, alerta) y con duración corta (~≤250ms salvo justificación).
- [ ] Revisión visual hecha en juego con fondo real (no solo en navegador) y en al menos dos condiciones de mundo distintas (día/noche o interior/exterior).
- [ ] Sin señales de "AI slop UI" (ver `design-system.md` §13): sin gradientes/sombras sin función, sin iconografía inconsistente, sin espaciado arbitrario, sin paleta ajena a los tokens NEXUS.
- [ ] Ningún asset, layout o composición copiado literalmente de un HUD de referencia de terceros.

## Responsive y accesibilidad

- [ ] Validado en 16:9 estándar sin recortes ni solapes.
- [ ] Validado en ultrawide (21:9) sin huecos ni elementos mal anclados.
- [ ] Validado con al menos un escalado de UI de FiveM distinto de 100%.
- [ ] Contraste AA verificado contra el fondo real esperado en juego (no solo contra un mock limpio).
- [ ] `:focus-visible` presente y visualmente claro en todo elemento interactivo con foco NUI.
- [ ] `prefers-reduced-motion: reduce` implementado y verificado (animaciones no esenciales desactivadas/reducidas).
- [ ] Ningún estado se comunica solo por color (hay forma/icono/texto de apoyo).
- [ ] Navegación por teclado y por mando/gamepad probada en cualquier panel con foco NUI.

## Ingeniería FiveM/NUI

- [ ] Flujo de datos basado en eventos/statebags/callbacks — sin polling continuo salvo el caso justificado (loop acotado al contexto, con diff-antes-de-enviar) documentado en `fivem-nui-engineering.md`.
- [ ] `SendNUIMessage` no se dispara si el valor relevante no cambió (diff verificado, patrón `shallowEqual` o equivalente).
- [ ] Módulos inactivos se ocultan/desmontan, no quedan invisibles-pero-vivos.
- [ ] Cleanup verificado explícitamente: abrir/cerrar el panel o entrar/salir del contexto (vehículo, helicóptero) varias veces seguidas sin dejar listeners, timers, animaciones, foco NUI o callbacks huérfanos.
- [ ] Ningún dato o acción sensible se confía al cliente — validación server-side confirmada para toda acción disparada desde la NUI.
- [ ] El recurso funciona en su función principal sin depender en caliente de otro producto `nexus_*` (integraciones opcionales verificadas con `GetResourceState` + fallback).
- [ ] Coste de cliente medido/observado (frame time, mensajes NUI en el peor caso) y comparado contra el presupuesto de la fase 2 — dentro de presupuesto o desviación justificada y aceptada por el usuario.

## Configurabilidad

- [ ] Logo, colores (variants/accent), módulos activables y umbrales de visibilidad configurables sin tocar el componente visual.
- [ ] Config nueva sigue el patrón existente (`nexus_ui/config/config.lua` / `shared/tokens.lua`), no un sistema paralelo.

## Regresión

- [ ] Otros HUDs/overlays NEXUS activos simultáneamente revisados — sin colisión visual (superposición, competencia de espacio) ni competencia de foco/rendimiento con el HUD nuevo/modificado.
- [ ] Ningún recurso hot-restarteado con jugadores conectados durante la validación (regla general del proyecto — ver memoria `feedback-no-hot-restart-core-during-play`); toda prueba en vivo se coordina como ventana de mantenimiento si requiere reinicio de recurso.
- [ ] Resumen final entregado al usuario: qué cambió, qué tokens nuevos se añadieron (si alguno), qué hallazgos de la fase 1 quedaron fuera de alcance, coste de cliente medido vs. presupuesto.

## Cierre

- [ ] Todos los ítems anteriores están marcados con evidencia, o explícitamente declarados como pendientes (nunca asumidos).
- [ ] El usuario ha confirmado el cierre — esta skill no se autodeclara "terminada" sin esa confirmación.
