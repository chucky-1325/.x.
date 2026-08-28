# Especificación funcional de módulos — nexus-nui-premium

Referencia funcional (qué se muestra y cuándo), no diseño visual todavía — el visual se decide en la fase 3 del flujo para cada caso concreto. Inspiración de **nivel de pulido** en HUDs de rol modernos (p. ej. Prodigy RP), nunca de asset ni layout literal.

## HUD de jugador

Siempre visible en el mundo (fuera de menús/paneles con foco), salvo que el propio jugador esté en un estado que lo oculte (ej. character select, loading).

| Módulo | Dato | Regla de visibilidad/estado |
|---|---|---|
| Salud | `health` (0-100 normalizado) | Siempre visible. Estado crítico (<20-25%) con tratamiento visual diferenciado, no solo color. |
| Armadura | `armor` | Oculto o atenuado si es 0 y no se ha tenido armadura recientemente; visible con valor si >0. |
| Hambre | `hunger` | Siempre visible o visible por debajo de un umbral alto, según decisión de fase 2 (evitar saturar si siempre está en 90-100%). |
| Sed | `thirst` | Igual criterio que hambre. |
| Estrés | `stress` | Visible solo si >0 o por encima de un umbral bajo — no ocupar espacio si el jugador no tiene estrés. |
| Voz/proximidad | canal de voz activo, rango (susurro/normal/grito), indicador de quién está hablando cerca | Visible solo mientras hay actividad de voz relevante (el propio jugador hablando, o alguien cerca hablando) — no un icono estático permanente sin información. |
| Brújula | rumbo cardinal, calle/zona actual si aplica | Visible de forma discreta, no invasiva; puede integrarse con la franja de datos de vuelo cuando el HUD de helicóptero esté activo en vez de duplicarse. |
| Estados relevantes | efectos temporales (sangrado, esposado, lesión, etc. — los que ya existan en el framework/QBox) | Solo los estados activos en ese momento, como iconos/badges con label accesible, nunca una lista fija de "todos los estados posibles" con los inactivos atenuados. |

## HUD de vehículo

Visible solo mientras el jugador está dentro de un vehículo con motor/controlable (no en un vehículo puramente decorativo/sin control). Se retira inmediatamente al salir del vehículo — sin fade largo que deje datos obsoletos visibles.

| Módulo | Dato | Regla de visibilidad/estado |
|---|---|---|
| Velocidad | `GetEntitySpeed` convertido a km/h o mph según config | Siempre visible mientras el HUD de vehículo está activo. Fuente tipográfica tabular para que no "salte" el ancho. |
| RPM | RPM del motor (`GetVehicleCurrentRpm` o equivalente) | Visible; puede compartir componente visual con marcha (`VehicleGauge` reutilizable). |
| Marcha | marcha actual (`GetVehicleCurrentGear`) | Visible junto a RPM. |
| Combustible | nivel de combustible | Siempre visible; estado crítico (umbral bajo, a definir en fase 2) con tratamiento diferenciado no solo por color. |
| Motor | estado del motor (encendido/apagado, dañado) | Visible como estado, no como número crudo — icono/badge con label accesible. |
| Cinturón | abrochado/no abrochado | Visible como estado binario claro; si el framework ya gestiona penalización por no llevarlo, el HUD solo refleja el estado, no decide nada. |

## HUD de helicóptero

Módulo adicional que se activa **solo** cuando el jugador está a los mandos de una aeronave de tipo helicóptero — nunca en vehículo terrestre/acuático, nunca como pasajero sin control. Convive con (no sustituye a) el HUD de vehículo base si comparten datos (velocidad); no duplicar el mismo dato en dos componentes distintos simultáneamente.

| Módulo | Dato | Regla de visibilidad/estado |
|---|---|---|
| Altitud | altura sobre el suelo y/o sobre el nivel del mar, según lo que sea más útil para vuelo | Siempre visible mientras el HUD de helicóptero está activo. |
| Rumbo | heading/compass de vuelo | Puede compartir componente visual con la brújula del HUD de jugador si el patrón visual encaja, evitando redundancia. |
| Rotor | RPM del rotor / estado del motor de la aeronave | Visible; estado crítico (motor apagado en vuelo, autorrotación) con tratamiento diferenciado claro. |
| Datos de vuelo | velocidad vertical (ascenso/descenso), velocidad horizontal | Visible mientras el HUD está activo; velocidad vertical con indicación clara de signo (subiendo/bajando), no solo un número que hay que interpretar. |

Activación/desactivación: debe engancharse a un evento de entrada/salida de vehículo + comprobación de tipo de aeronave (clase de vehículo helicóptero), no a un polling que compruebe "¿sigo en un helicóptero?" en bucle corto. Al salir, cleanup inmediato del módulo (ver `fivem-nui-engineering.md` §Cleanup).

## Configurabilidad

Todo lo siguiente debe ser configurable sin tocar el componente visual, vía config Lua (siguiendo el patrón de `nexus_ui/config/config.lua`) y/o tokens (`nexus_ui/shared/tokens.lua`):

- **Logo**: espacio reservado y configurable por producto/servidor, no hardcodeado como imagen fija en el bundle si el objetivo es que el HUD sea vendible a otro servidor NEXUS.
- **Colores**: accent por variante/contexto ya existe en `nexus_ui/config/config.lua` (`variants`) — reutilizar, no crear un sistema de color paralelo.
- **Módulos**: cada módulo (salud, armadura, hambre, sed, estrés, voz, brújula, vehículo, helicóptero) debe poder activarse/desactivarse por config, para servidores que no quieran todos los sistemas de rol asociados (p. ej. un servidor sin sistema de estrés).
- **Visibilidad**: reglas de umbral (a partir de qué % se muestra hambre/sed, qué tan crítico es "crítico") configurables, no fijas en el componente.

## Contexto adaptativo — no saturar pantalla

Regla general transversal a todos los módulos: un dato solo ocupa espacio en pantalla mientras es relevante. "Relevante" se define explícitamente por módulo en la fase 2 (ver `workflow.md`), pero el principio por defecto es:
- Si el valor está en su rango normal/esperado y no ha cambiado recientemente, se muestra de forma mínima/discreta.
- Si el valor entra en rango de advertencia o crítico, gana peso visual temporalmente.
- Si el módulo no aplica al contexto actual (cinturón sin vehículo, HUD de helicóptero sin helicóptero, voz sin nadie hablando), no se reserva espacio para él — se retira del layout, no solo se atenúa.
