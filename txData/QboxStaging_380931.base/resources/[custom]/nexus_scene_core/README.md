# nexus_scene_core

Nucleo visual reutilizable para acciones fisicas NEXUS. Gestiona animaciones, props sincronizados, efectos opcionales, controles, cancelacion y limpieza.

El recurso no entrega items, dinero, XP ni permisos. El recurso de gameplay valida la accion en servidor, ejecuta la escena en cliente y solo despues solicita la finalizacion usando su propio protocolo seguro.

## Export cliente

```lua
local completed, reason = exports.nexus_scene_core:play('craft_mechanic', {
    duration = 8500,
    label = 'Montando kit de reparacion',
    targetCoords = station.coords,
})
```

Exports: `play`, `cancel`, `isPlaying`, `getDefinition`.

## Export servidor

Exports: `isRegistered`, `getMetadata`. Son de consulta y no ejecutan acciones de gameplay.

## Escenas iniciales

- Crafting: `craft_civil`, `craft_mechanic`, `craft_illegal`, `craft_medical`, `craft_police`.
- Laboratorios: `lab_chemistry`, `lab_packaging`, `lab_processing`, `lab_maintenance`, `lab_sabotage`.
- Logistica criminal: `package_pickup`, `package_delivery`, `extortion_collection`.

Total actual: 13 escenas registradas.
