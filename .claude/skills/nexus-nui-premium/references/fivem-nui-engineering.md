# Ingeniería FiveM/NUI — nexus-nui-premium

Reglas técnicas específicas de FiveM que se suman a los principios de diseño de `design-system.md`. Estas reglas son verificables en código y forman parte del checklist de cierre.

## Inspeccionar antes de proponer

Antes de escribir una sola línea de wireframe o código para un HUD:

1. Leer el `fxmanifest.lua` del recurso objetivo — confirmar `ui_page`, `client_scripts`, `dependency` declaradas.
2. Leer el/los archivo(s) cliente que ya envían datos a la NUI (`SendNUIMessage`) — entender qué eventos/statebags ya alimentan el HUD, con qué frecuencia y con qué forma de dato.
3. Leer el HTML/bundle NUI existente — si es un bundle construido (React/Vite minificado, como `qbx_hud_aaa/html/index.html`), identificar el proyecto fuente antes de asumir que hay que reescribir desde cero.
4. Leer `nexus_ui/shared/tokens.lua` y `nexus_ui/config/config.lua` — cualquier color, radio o fuente que se necesite y no exista ahí se propone como adición, no se hardcodea en el HUD.
5. Si el recurso objetivo declara `dependency` de otro producto NEXUS/QBox, registrarlo como hallazgo de auditoría — no es un problema a resolver dentro de esta skill salvo que el usuario lo pida explícitamente, pero debe quedar escrito en el informe de la fase 1.

No proponer una arquitectura nueva de cero si ya existe un patrón funcionando en otro HUD del proyecto (p. ej. el patrón `shallowEqual` + cache `last` de `qbx_hud_aaa/client/main.lua`) — reutilizar o extraer a compartido, no reinventar por HUD.

## Flujo de datos: eventos, no polling

- Toda actualización de la NUI se dispara por un evento discreto: `RegisterNetEvent`, `AddStateBagChangeHandler`, un callback de `lib.callback`, o un `SendNUIMessage` disparado desde un handler de evento — nunca desde un `CreateThread` con `Wait` corto que lee y empuja datos en bucle "por si acaso cambiaron".
- Excepción legítima: un módulo que por naturaleza necesita muestreo continuo mientras está activo (p. ej. velocímetro de vehículo, que sí necesita leer `GetEntitySpeed` en un loop mientras se conduce). En ese caso:
  - El loop solo corre mientras el contexto es relevante (dentro de un vehículo) y se detiene inmediatamente al salir de él — no sigue corriendo en segundo plano.
  - El loop sigue aplicando diff-antes-de-enviar (no manda `SendNUIMessage` en cada tick si el valor redondeado no cambió).
  - El intervalo de muestreo es el mínimo necesario para que se vea fluido (normalmente 100-250ms para velocímetro/RPM), nunca cada frame.

## Actualizar solo si cambió; ocultar lo inactivo

- Antes de cualquier `SendNUIMessage`, comparar contra el último valor enviado (patrón `shallowEqual` ya usado en `qbx_hud_aaa`) y no enviar si no hay cambio relevante. "Relevante" se define en la fase 2 (p. ej. salud redondeada al entero, no cada decimal de un float).
- Un módulo sin datos relevantes en ese momento (cinturón sin vehículo, HUD de helicóptero fuera de un helicóptero, voz sin nadie cerca) se oculta/desmonta en la NUI — no se deja con opacidad 0 ocupando ciclos de render o espacio de layout invisible. Del lado del cliente Lua, tampoco se sigue calculando ese dato si el módulo no es visible, salvo que el cálculo sea trivial y compartido con otro módulo activo.

## Cleanup obligatorio

Al cerrar/ocultar cualquier HUD, panel o modo (ej. salir del vehículo, salir del helicóptero, cerrar una tablet NUI), verificar explícitamente que se limpian:

- **Listeners**: cualquier `RegisterNetEvent`/`AddEventHandler` de vida acotada a ese contexto se remueve o dejar de reaccionar (`RemoveEventHandler` si aplica, o guard de estado si el evento es compartido).
- **Timers/loops**: cualquier `CreateThread`/`SetInterval` con `Wait` se termina limpiamente (flag de salida comprobado en el propio loop), no se deja huérfano.
- **Animaciones**: transiciones/animaciones CSS o JS en curso no dejan el DOM en un estado a medias; si el módulo se desmonta a mitad de una transición, se resuelve el estado final antes de desmontar.
- **Foco NUI**: `SetNuiFocus(false, false)` (y `SetNuiFocusKeepInput(false)` si se usó) se llama siempre que un panel con foco se cierra, incluyendo cierres forzados (desconexión, muerte, cambio de escena) — no solo el cierre "feliz" por botón.
- **Callbacks**: `RegisterNUICallback` registrados para un panel temporal se gestionan para no quedar respondiendo a mensajes de un panel que ya no existe (guardado de estado `open`/`token` que el callback valida antes de actuar).

Esto se verifica explícitamente en la fase 5/6 del flujo (ver `quality-checklist.md`), no se asume por "parece que sí".

## El servidor es la única autoridad

- Cualquier dato sensible (dinero, salud real, permisos, resultado de una acción) se calcula y valida en servidor. El cliente/NUI solo presenta lo que el servidor ya decidió.
- Cualquier acción que el jugador dispare desde la NUI (un botón que hace algo, no solo que muestra algo) viaja al servidor vía evento/callback y se revalida ahí — la NUI nunca asume que su propio estado local es correcto o suficiente para ejecutar la acción.
- Un HUD puramente informativo (salud, velocidad, brújula) puede leerse de datos de cliente locales cuando el dato en sí no es sensible ni explotable (p. ej. velocidad del propio vehículo) — la barra de autoridad-en-servidor aplica con más fuerza cuanto más sensible/explotable es el dato, no de forma idéntica a todo.

## Compatibilidad de entrada y pantalla

- Todo control interactivo de una NUI con foco (no el HUD pasivo) debe ser operable por teclado y por mando/gamepad — no asumir mouse-only.
- Validar en al menos una resolución 16:9 estándar, una ultrawide (21:9) y con el escalado de UI de FiveM distinto de 100% — sin overlap, recorte ni desbordamiento horizontal.
- Unidades relativas (`%`, `rem`, `vw`/`vh` con cuidado) sobre unidades absolutas fijas allí donde el layout deba adaptarse; anclas de esquina pixel-fijas son aceptables solo si es una decisión de diseño explícita y documentada.

## Motion, contraste y foco

- Respetar `prefers-reduced-motion: reduce` en CSS (`@media (prefers-reduced-motion: reduce)`) desactivando o reduciendo drásticamente animaciones no esenciales.
- Contraste AA verificado contra el fondo real esperado en juego (ver `design-system.md` §9).
- `:focus-visible` con un estilo visualmente distinto (no solo el outline por defecto del navegador CEF) en todo elemento interactivo con foco NUI.

## Standalone / sin dependencias duras

- Cada HUD/producto `nexus_*` debe arrancar y funcionar en su función principal sin que otro recurso `nexus_*` esté corriendo. Integraciones con otro producto NEXUS (p. ej. leer datos de `nexus_scene_core` o de un sistema de facciones) se implementan como adaptador opcional: se comprueba `GetResourceState('otro_recurso') == 'started'` antes de usarlo, con una ruta de fallback funcional si no está.
- Dependencias de framework (`qbx_core`, `ox_lib`) no cuentan como acoplamiento NEXUS-a-NEXUS y son aceptables como base — la regla es específicamente sobre acoplar un producto `nexus_*` a otro producto `nexus_*`/`qbx_*_aaa` de forma dura.
- Si al auditar un recurso (fase 1) se encuentra una `dependency` dura hacia otro producto NEXUS, se registra como hallazgo — no se corrige automáticamente dentro de esta skill salvo petición explícita, porque puede ser una decisión ya tomada conscientemente.
