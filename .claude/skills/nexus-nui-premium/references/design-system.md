# Principios de diseño AAA — nexus-nui-premium

Estos principios se aplican a **toda** NUI construida bajo esta skill. No son sugerencias: son la barra mínima de calidad comercial que separa un HUD "funcional" de un HUD vendible.

## 1. Diseño antes de programar

Ningún componente se escribe antes de que exista, en texto o wireframe, la jerarquía visual, los tokens que va a usar y los estados que debe cubrir. Si al implementar surge una duda de diseño no resuelta en la fase 2/3 del flujo, se para y se resuelve como decisión de diseño — no se improvisa en CSS.

## 2. Jerarquía

Cada módulo del HUD tiene un propósito de lectura claro y un orden de prioridad visual explícito:
- Lo crítico para la supervivencia inmediata (salud, armadura en combate, combustible cerca de cero) tiene el mayor peso visual y la respuesta más rápida.
- Lo informativo pero no urgente (brújula, marcha) es legible pero no compite por atención.
- Lo contextual (voz/proximidad, estados temporales) aparece y desaparece según relevancia — nunca ocupa espacio fijo si no aporta información en ese instante.

La jerarquía se decide en la fase 2 del flujo (ver `workflow.md`) y se documenta antes de maquetar.

## 3. Tokens semánticos

Todo color, tamaño, radio y tipografía sale de un token, nunca de un valor literal en el componente. Este proyecto ya tiene una capa base en `nexus_ui/shared/tokens.lua` y `nexus_ui/config/config.lua` — extenderla, no bifurcarla:

- **Color**: usar `colors.bg/surface/glass/border/text/muted` para superficie y texto; `success/warning/danger/info` únicamente para estado semántico (no como acento decorativo); el `accent` de cada `variant` (civil/police/ems/...) para identidad de contexto, nunca hardcodeado en el componente.
- Si un HUD necesita un token que no existe todavía (p. ej. un `colors.critical` más agresivo que `danger` para alertas de vida <10%), se propone como adición a `nexus_ui/shared/tokens.lua` en la fase 2/3 — no se inventa localmente dentro del HTML del HUD.
- **Radio**: `radius.sm/md/lg` cubren la mayoría de casos; un radio nuevo se justifica, no se improvisa.
- **Tipografía**: `fonts.ui` para toda la interfaz, `fonts.mono` solo para datos tabulares/numéricos donde el alineado importa (velocímetro, RPM, altímetro, coordenadas).

## 4. Escala de espaciado

Define y usa una escala de espaciado consistente (p. ej. base 4px: 4/8/12/16/24/32/48) en vez de valores sueltos. Todo `gap`, `margin`, `padding` sale de esa escala. Si `nexus_ui` no tiene aún una escala de espaciado publicada, la fase 2 debe proponerla como token compartido antes de maquetar, para que el siguiente HUD NEXUS la reutilice en vez de inventar la suya.

## 5. Tipografía

- Escala tipográfica limitada y con propósito (no más de 4-5 tamaños activos en un HUD).
- Pesos usados con intención: el peso no sustituye a la jerarquía de tamaño/color, la refuerza.
- `text-wrap: balance` en textos cortos con salto de línea (labels, títulos de módulo).
- Datos numéricos que cambian en tiempo real (velocidad, RPM, altitud) usan `font-variant-numeric: tabular-nums` o la fuente mono para que el ancho no "baile" en cada actualización.

## 6. Estados completos

Cada componente interactivo o dinámico se diseña en **todos** sus estados relevantes, no solo el estado "todo bien":
- Valor normal / valor de advertencia / valor crítico (p. ej. salud >50 / 20-50 / <20).
- Módulo activo / módulo oculto por falta de contexto (p. ej. cinturón cuando no hay vehículo).
- Dato entrante / dato ausente o con timeout de red (nunca mostrar un `NaN` o un valor congelado sin indicarlo).
- Para controles: default/hover/focus/active/disabled — aplica sobre todo a HUD de admin/configuración, no solo al HUD in-game.

## 7. Microinteracciones

Transición sutil al cambiar de valor o aparecer/desaparecer un módulo (fade/slide corto, nunca >200-250ms salvo justificación), nunca animación continua o llamativa sin motivo funcional. Una microinteracción que no comunica nada (cambio de estado, entrada de dato nuevo, alerta) no se añade. Todas las animaciones deben tener una vía de apagado vía `prefers-reduced-motion` (ver engineering doc).

## 8. Responsive

El HUD se valida en al menos: 16:9 estándar, ultrawide (21:9), y con el escalado de UI de FiveM en 90%/100%/110%. Ningún módulo se recorta, solapa o queda ilegible en ninguno de esos casos. Layout con flex/grid y `gap`, nunca posicionamiento absoluto pixel-perfect atado a una sola resolución salvo que sea deliberado y documentado (p. ej. anclas de esquina que sí deben ser absolutas).

## 9. Accesibilidad

- Contraste mínimo AA (4.5:1 texto normal, 3:1 texto grande/iconografía) contra el fondo real que va a tener detrás en juego, no contra un fondo de mockup limpio.
- `:focus-visible` obligatorio y visualmente claro en cualquier elemento con el que se pueda interactuar por teclado/mando (esto incluye tablets/paneles NUI con foco, no solo el HUD pasivo).
- `prefers-reduced-motion: reduce` desactiva o reduce drásticamente toda animación no esencial.
- Nunca se comunica un estado solo por color (añadir forma/icono/texto — un jugador con daltonismo debe poder leer "crítico" sin depender del rojo).

## 10. Arquitectura por componentes

El HUD se construye como componentes pequeños y reutilizables con una responsabilidad clara (p. ej. `StatBar`, `CompassStrip`, `VehicleGauge`, `FlightDataPanel`), no como una página monolítica. Cada componente:
- Recibe datos ya validados/formados, no lógica de negocio.
- No sabe de dónde vienen los datos (evento NUI vs. mock local) — eso vive en la capa de estado/bridge, no en el componente visual.
- Es reutilizable entre HUDs NEXUS cuando el patrón se repite (p. ej. una barra de estado sirve para salud, armadura, combustible con distinta config, no tres implementaciones separadas).

## 11. Rendimiento

Presupuesto de rendimiento definido en la fase 2 y verificado en la fase 5 (ver `quality-checklist.md`): impacto de frame time en cliente, tamaño del bundle NUI, número de repaints/reflows por actualización de dato. Un HUD que cuesta frames notables en cliente no pasa el checklist de cierre, sin importar cuánto haya mejorado visualmente.

## 12. Revisión visual

Antes de cerrar (fase 6), revisión visual explícita en juego (no solo en navegador/mock): con fondo real del mundo, con HUD, con otros overlays NEXUS activos simultáneamente (evitar colisión visual entre HUDs), y en al menos un escenario de estrés (de noche, con lluvia, en interior oscuro) para confirmar que el contraste y la legibilidad se sostienen fuera del caso ideal.

## 13. Prohibición de "AI slop UI"

Señales explícitas de rechazo — si aparece cualquiera de estas, no se cierra el trabajo:
- Gradientes o sombras genéricas sin función (glow porque sí, blur porque sí).
- Iconografía mezclando varios estilos/librerías sin coherencia.
- Espaciado que no cae en la escala definida (valores como `13px`, `7px` sin razón).
- Paleta que ignora los tokens NEXUS existentes y reinventa colores "parecidos".
- Componentes que no tienen estado vacío/error definido y simplemente no se sabe qué pasa si el dato no llega.
- Texto genérico de relleno (placeholders tipo "Lorem" o etiquetas sin sentido en el dominio de rol NEXUS).
- Cualquier elemento visual copiado literalmente (asset, composición, iconografía distintiva) de un HUD de referencia de terceros — la inspiración es de **nivel de pulido y de qué información se muestra**, nunca de assets ni de layout calcado.
