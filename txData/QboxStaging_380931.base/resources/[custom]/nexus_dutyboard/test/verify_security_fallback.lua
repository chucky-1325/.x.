-- Prueba de equivalencia determinista entre nexus_bridge/server/security.lua
-- (canonico, solo NexusRateLimit) y nexus_dutyboard/server/security_fallback.lua
-- (vendorizado). nexus_dutyboard no usa timed actions, asi que esta prueba solo
-- cubre rateLimit -- ver nexus_contracts/test/verify_security_fallback.lua para
-- la version que ademas cubre begin/consume/cancelTimedAction.
--
-- No requiere FXServer: carga ambos modulos en un entorno Lua aislado, con un
-- reloj falso compartido y sin dependencias externas (RegisterNetEvent,
-- AddEventHandler, exports, print quedan como no-ops). Corre bajo cualquier
-- interprete Lua 5.1+ (probado con Lua 5.1 -- CitizenFX usa 5.4 en runtime;
-- esta prueba valida equivalencia logica/de ramas, no paridad bit-a-bit de
-- funciones numericas especificas de 5.4).
--
-- Uso: lua test/verify_security_fallback.lua   (desde la carpeta nexus_dutyboard)
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

local testRateLimits = { test_vector = { window = 1000, limit = 3 }, default = { window = 1000, limit = 3 } }
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
    NexusDutyboardConfig = { security = { rateLimits = testRateLimits } },
}))

local canonicalRateLimit = canonicalEnv.NexusRateLimit
local vendoredRateLimit = vendoredEnv.NexusDutyboardSecurityFallback.rateLimit

local passed, failed = 0, 0

local function assertSame(label, a, b)
    if a == b then
        passed = passed + 1
        print(('[PASS] %s -> %s'):format(label, tostring(a)))
    else
        failed = failed + 1
        print(('[FAIL] %s -> canonico=%s vendorizado=%s'):format(label, tostring(a), tostring(b)))
    end
end

local function step(label, source, bucket)
    local a = canonicalRateLimit(source, bucket)
    local b = vendoredRateLimit(source, bucket)
    assertSame(label, a, b)
end

print('== rateLimit: bucket sintetico test_vector (window=1000, limit=3) ==')
fakeNow = 0
step('rateLimit #1 (bajo limite)', 1, 'test_vector')
step('rateLimit #2 (bajo limite)', 1, 'test_vector')
step('rateLimit #3 (en el limite)', 1, 'test_vector')
step('rateLimit #4 (excede el limite)', 1, 'test_vector')
fakeNow = 1500
step('rateLimit tras reset de ventana', 1, 'test_vector')
step('rateLimit source invalido (nil)', nil, 'test_vector')
step('rateLimit source invalido (0)', 0, 'test_vector')
step('rateLimit source distinto no comparte contador', 2, 'test_vector')
step('rateLimit bucket distinto no comparte contador', 1, 'otro_bucket')

print(('\nResultado: %d pasaron, %d fallaron.'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
