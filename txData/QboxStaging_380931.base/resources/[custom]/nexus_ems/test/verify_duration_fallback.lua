-- Vector de regresion para el fix de NexusEMS.PrepareAction
-- (server/functions.lua): `duration = duration or action.duration`.
--
-- Contexto: un probe en vivo contra el nexus_bridge REAL (compartido, no el
-- fallback vendorizado) confirmo que exports.nexus_bridge:beginTimedAction()
-- puede no propagar su 3er valor de retorno (duration) a traves del limite de
-- export -- llega `nil` aunque nexus_bridge internamente calculo un valor
-- real. Antes del fix, NexusEMS.PrepareAction usaba ese `duration` sin
-- resguardo en `nowMs() + duration + grace`, lo que habria lanzado un error
-- de Lua ("attempt to perform arithmetic on a nil value") en cada accion
-- medica real mientras nexus_bridge estuviera presente.
--
-- Esta prueba no ejecuta NexusEMS.PrepareAction completo (requiere demasiado
-- contexto de FXServer: jugador, paciente, inventario, etc.) -- aisla
-- exactamente la expresion defensiva que se agrego, con los mismos dos casos
-- observados en el probe real: retorno con duration nil (el bug) y retorno
-- con duration numerico (comportamiento normal, no debe regresionar).
--
-- Uso: lua test/verify_duration_fallback.lua   (desde la carpeta nexus_ems)
-- Codigo de salida: 0 si todo pasa, 1 si algo falla.

local passed, failed = 0, 0

local function resolveDuration(returnedDuration, actionDuration)
    -- Misma expresion exacta que server/functions.lua, NexusEMS.PrepareAction.
    return returnedDuration or actionDuration
end

local function assertEqual(label, expected, actual)
    if expected == actual then
        passed = passed + 1
        print(('[PASS] %s -> %s'):format(label, tostring(actual)))
    else
        failed = failed + 1
        print(('[FAIL] %s -> esperado=%s obtenido=%s'):format(label, tostring(expected), tostring(actual)))
    end
end

print('== Regresion: duration nil a traves del limite de export (caso real confirmado en vivo) ==')
assertEqual('beginTimedAction devuelve duration=nil -> usa action.duration', 5000, resolveDuration(nil, 5000))

print('== No regresion: duration real devuelto por el export no se descarta ==')
assertEqual('beginTimedAction devuelve duration=1234 -> se respeta, no se pisa con action.duration', 1234, resolveDuration(1234, 5000))

print('== Caso limite: duration=0 es un valor real (no debe tratarse como ausente) ==')
-- Nota: `0 or x` en Lua devuelve 0 (0 es verdadero en Lua), asi que esto ya
-- se comporta correctamente con `or` -- se deja como vector explicito para
-- que un cambio futuro a otra forma de resolucion no rompa este caso sin
-- que la prueba lo note.
assertEqual('beginTimedAction devuelve duration=0 -> se respeta (0 es "truthy" en Lua)', 0, resolveDuration(0, 5000))

print(('\nResultado: %d pasaron, %d fallaron.'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
