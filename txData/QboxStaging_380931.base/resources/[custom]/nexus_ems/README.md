# nexus_ems

Base clinica fisica de NEXUS para QBox, ox_lib, ox_target, ox_inventory y
nexus_bridge.

## Flujo

1. Un sanitario usa ox_target sobre un jugador o ejecuta `/ems`.
2. El servidor valida trabajo, distancia, bloqueo del paciente y rate limit.
3. Se completa una evaluacion fisica mediante nexus_scene_core.
4. La tablet clinica muestra el estado derivado del ped y metadata persistente.
5. Cada tratamiento vuelve a validar indicacion, rango, materiales y distancia.
6. Los materiales se consumen al completar la accion, nunca al iniciarla.
7. El resultado se registra en `nexus_medical_events` y concede progresion EMS.

## Acciones v1

- evaluacion primaria;
- vendaje;
- analgesia;
- estabilizacion;
- reanimacion;
- preparacion para traslado.

La preparacion de traslado no adjunta jugadores ni crea una camilla ficticia. El
transporte cooperativo persistente queda reservado para un futuro `nexus_carry_core`.

## Comandos

- `/ems`: evalua al paciente mas cercano.

Los administradores ACE pueden usar el acceso de pruebas desde `nexus_menu`.

## Dependencias

- `ox_lib`
- `ox_target`
- `ox_inventory`
- `qbx_core`
- `nexus_bridge`
- `nexus_scene_core`
- `nexus_progression` para progresion, con degradacion controlada si no esta iniciado.

## Seguridad

- autoridad server-side;
- token temporal por accion;
- distancia comprobada al preparar y finalizar;
- un tratamiento concurrente por sanitario y paciente;
- consumo de inventario posterior a la escena;
- permisos por job y grado;
- cooldowns y limpieza al desconectar;
- auditoria SQL antes/despues.

## Prueba Rapida

```text
restart nexus_bridge
restart nexus_scene_core
restart nexus_ems
restart nexus_menu
```

Con dos jugadores:

1. Asignar `ambulance` al sanitario o usar un administrador de pruebas.
2. Dar el kit sanitario desde `NEXUS > Admin pruebas`.
3. Acercarse al paciente y usar `/ems`.
4. Completar la evaluacion y comprobar que abre la tablet.
5. Probar tratamiento indicado, cancelacion, distancia y doble accion.
6. Confirmar consumo de item, cambio de estado y registro SQL.

