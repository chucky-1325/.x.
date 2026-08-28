-- Prueba de equivalencia determinista entre nexus_bridge/server/security.lua
-- (canonico) y nexus_ems/server/security_fallback.lua (vendorizado).
--
-- No requiere FXServer: carga ambos modulos en un entorno Lua aislado, con un
-- reloj falso compartido y sin dependencias externas (RegisterNetEvent,
-- AddEventHandler, exports, print quedan como no-ops). Corre bajo cualquier
-- interprete Lua 5.1+ (probado con Lua 5.1 -- CitizenFX usa 5.4 en runtime;
-- esta prueba valida equivalencia logica/de ramas, no paridad bit-a-bit de
-- funciones numericas especificas de 5.4).
--
-- Uso: lua test/verify_security_fallback.lua   (desde la carpeta nexus_ems)
-- Codigo de salida: 0 si todo pasa, 1 si algo falla.

local function scriptDir()
    local src = debug.getinfo(1, 'S').source
    src = src:match('^@(.*)$') or src
    return src:match('^(.*)[/\\][^/\\]+$') or '.'
end

local baseDir = scriptDir()
local canonicalPath = baseDir .. '/../../nexus_bridge/server/security.lua'
local vendoredPath = baseDir .. '/../server/security_fallback.lua'

local fakeNow = 0
local function GetGameTimerMock() return fakeNow end

local function noop() end

local function makeEnv(overrides)
    local env = setmetatable({}, { __index = _G })
    for k, v in pairs(overrides) do env[k] = v end
    return env
end

local function loadInEnv(path, env)
    local chunk, err = loadfile(path)
    if not chunk then
        io.stderr:write(('No se pudo cargar %s: %s\n'):format(path, tostring(err)))
        os.exit(1)
    end
    setfenv(chunk, env)
    local ok, runErr = pcall(chunk)
    if not ok then
        io.stderr:write(('Error ejecutando %s: %s\n'):format(path, tostring(runErr)))
        os.exit(1)
    end
    return env
end

local testRateLimits = { test_vector = { window = 1000, limit = 3 } }
local testTimedActions = { minimumDuration = 500, maximumDuration = 120000, graceMs = 2000, earlyToleranceMs = 250 }

local canonicalEnv = loadInEnv(canonicalPath, makeEnv({
    GetGameTimer = GetGameTimerMock,
    RegisterNetEvent = noop,
    AddEventHandler = noop,
    exports = setmetatable({}, { __call = function() return {} end, __index = function() return noop end }),
    NexusBridgeUtils = { log = noop, trim = function(v, n) return tostring(v or ''):sub(1, n or 96) end },
    NexusBridgeConfig = { rateLimits = testRateLimits, timedActions = testTimedActions },
    NexusBridge = { events = { securityFlag = 'nexus_bridge:server:securityFlag' } },
}))

local vendoredEnv = loadInEnv(vendoredPath, makeEnv({
    GetGameTimer = GetGameTimerMock,
    AddEventHandler = noop,
    print = noop,
    NexusEMSConfig = { security = { rateLimits = testRateLimits, timedActions = testTimedActions } },
}))

local canonical = {
    rateLimit = canonicalEnv.NexusRateLimit,
    beginTimedAction = canonicalEnv.NexusBeginTimedAction,
    consumeTimedAction = canonicalEnv.NexusConsumeTimedAction,
    cancelTimedAction = canonicalEnv.NexusCancelTimedAction,
}
local vendored = vendoredEnv.NexusEMSSecurityFallback

local passed, failed = 0, 0

local function eq(a, b)
    if a == nil and b == nil then return true end
    return a == b
end

local function assertSame(label, a1, a2, a3, b1, b2, b3)
    local ok = eq(a1, b1) and eq(a2, b2) and eq(a3, b3)
    if ok then
        passed = passed + 1
        print(('[PASS] %s -> (%s, %s, %s)'):format(label, tostring(a1), tostring(a2), tostring(a3)))
    else
        failed = failed + 1
        print(('[FAIL] %s -> canonico=(%s, %s, %s) vendorizado=(%s, %s, %s)'):format(
            label, tostring(a1), tostring(a2), tostring(a3), tostring(b1), tostring(b2), tostring(b3)))
    end
end

local function step(label, fn)
    local a1, a2, a3 = fn(canonical)
    local b1, b2, b3 = fn(vendored)
    assertSame(label, a1, a2, a3, b1, b2, b3)
end

print('== rateLimit: bucket sintetico test_vector (window=1000, limit=3) ==')
fakeNow = 0
step('rateLimit #1 (bajo limite)', function(m) return m.rateLimit(1, 'test_vector') end)
step('rateLimit #2 (bajo limite)', function(m) return m.rateLimit(1, 'test_vector') end)
step('rateLimit #3 (en el limite)', function(m) return m.rateLimit(1, 'test_vector') end)
step('rateLimit #4 (excede el limite)', function(m) return m.rateLimit(1, 'test_vector') end)
fakeNow = 1500
step('rateLimit tras reset de ventana', function(m) return m.rateLimit(1, 'test_vector') end)
step('rateLimit source invalido (nil)', function(m) return m.rateLimit(nil, 'test_vector') end)
step('rateLimit source invalido (0)', function(m) return m.rateLimit(0, 'test_vector') end)

print('== beginTimedAction / consumeTimedAction / cancelTimedAction ==')
fakeNow = 0
step('beginTimedAction invalido (scope vacio)', function(m) return m.beginTimedAction(2, '', 'patient1', 1000) end)

fakeNow = 10000
local canonToken = select(1, canonical.beginTimedAction(2, 'test', 'patient1', 1000))
local vendToken = select(1, vendored.beginTimedAction(2, 'test', 'patient1', 1000))
if canonToken ~= nil and vendToken ~= nil then
    passed = passed + 1
    print('[PASS] beginTimedAction ambos devuelven token no-nulo')
else
    failed = failed + 1
    print(('[FAIL] beginTimedAction canonico=%s vendorizado=%s'):format(tostring(canonToken), tostring(vendToken)))
end

step('beginTimedAction repetido mientras esta ocupado -> busy', function(m) return m.beginTimedAction(2, 'test', 'patient1', 1000) end)

fakeNow = 10100
step('consumeTimedAction demasiado pronto', function(m)
    local token = m == canonical and canonToken or vendToken
    return m.consumeTimedAction(2, 'test', 'patient1', token)
end)

fakeNow = 20000
canonToken = select(1, canonical.beginTimedAction(2, 'test', 'patient1', 1000))
vendToken = select(1, vendored.beginTimedAction(2, 'test', 'patient1', 1000))

fakeNow = 20800
step('consumeTimedAction exitoso', function(m)
    local token = m == canonical and canonToken or vendToken
    return m.consumeTimedAction(2, 'test', 'patient1', token)
end)

fakeNow = 30000
canonToken = select(1, canonical.beginTimedAction(2, 'test', 'patient1', 1000))
vendToken = select(1, vendored.beginTimedAction(2, 'test', 'patient1', 1000))
fakeNow = 30000 + 1000 + 2000 + 5000
step('consumeTimedAction expirado', function(m)
    local token = m == canonical and canonToken or vendToken
    return m.consumeTimedAction(2, 'test', 'patient1', token)
end)

step('consumeTimedAction token invalido (no-string)', function(m) return m.consumeTimedAction(2, 'test', 'patient1', 12345) end)

fakeNow = 40000
canonToken = select(1, canonical.beginTimedAction(3, 'test', 'patient2', 1000))
vendToken = select(1, vendored.beginTimedAction(3, 'test', 'patient2', 1000))
step('cancelTimedAction exitoso', function(m)
    local token = m == canonical and canonToken or vendToken
    return m.cancelTimedAction(3, 'test', token)
end)
step('cancelTimedAction ya cancelado', function(m)
    local token = m == canonical and canonToken or vendToken
    return m.cancelTimedAction(3, 'test', token)
end)

print(('\nResultado: %d pasaron, %d fallaron.'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
