-- NEXUS-VENDORED-FALLBACK
-- source: nexus_bridge/server/security.lua
-- source_sha256: c7c160d90f5e65aebabdf4c28e866b5328352aa644056187ebb20df3d2937a68
-- vendored_at: 2026-08-28
-- Adaptado para nexus_contracts: sin exports(), sin globales NexusBridgeConfig/
-- NexusBridgeUtils/NexusBridge (usa NexusContractsConfig.security y un log local),
-- expuesto como tabla NexusContractsSecurityFallback en vez de funciones globales.
-- Solo cubre rateLimit + timed actions (lo unico que nexus_contracts consume de
-- nexus_bridge/server/security.lua) -- no vendoriza el evento securityFlag ni la
-- limpieza en onResourceStop, que son de alcance cross-resource y no aplican aqui.
--
-- NO editar la logica de negocio aqui sin editar primero el canonico y
-- re-vendorizar (actualizar source_sha256 arriba). Verificar equivalencia con
-- test/verify_security_fallback.lua y deriva de hash con
-- test/verify_vendored_hash.sh antes de cada release.

NexusContractsSecurityFallback = {}

local buckets = {}
local timedActions = {}
local timedTokenCounter = 0
local warnedOnce = false

local function security()
    return NexusContractsConfig.security or {}
end

local function getLimit(bucket)
    local limits = security().rateLimits or {}
    return limits[bucket] or limits.default or { window = 10000, limit = 8 }
end

local function warnFallbackActive()
    if warnedOnce then return end
    warnedOnce = true
    print('[nexus_contracts] AVISO: nexus_bridge no disponible -- usando fallback de seguridad local (rate limit y tokens de accion fisica aislados a este recurso).')
end

function NexusContractsSecurityFallback.rateLimit(source, bucket)
    warnFallbackActive()
    source = tonumber(source)
    if not source or source <= 0 then return false end

    bucket = bucket or 'default'
    local rule = getLimit(bucket)
    local now = GetGameTimer()
    local key = ('%s:%s'):format(source, bucket)
    local state = buckets[key]

    if not state or now - state.startedAt > rule.window then
        buckets[key] = { startedAt = now, count = 1 }
        return true
    end

    state.count = state.count + 1
    if state.count > rule.limit then
        return false
    end

    return true
end

local function normalizeActionKey(value, maxLength)
    value = tostring(value or ''):sub(1, maxLength or 96)
    value = value:match('^%s*(.-)%s*$') or value
    if value == '' or not value:match('^[%w_:%-%.]+$') then return nil end
    return value
end

function NexusContractsSecurityFallback.beginTimedAction(source, scope, subject, durationMs)
    warnFallbackActive()
    source = tonumber(source)
    scope = normalizeActionKey(scope, 32)
    subject = normalizeActionKey(subject, 120)
    if not source or source <= 0 or not scope or not subject then return nil, 'invalid_action' end

    local config = security().timedActions or {}
    local minimum = tonumber(config.minimumDuration) or 500
    local maximum = tonumber(config.maximumDuration) or 120000
    local duration = math.max(minimum, math.min(maximum, tonumber(durationMs) or minimum))
    local now = GetGameTimer()
    local actions = timedActions[source] or {}
    local current = actions[scope]
    if current and now <= current.expiresAt then
        return nil, 'busy', math.max(0, current.expiresAt - now)
    end

    timedTokenCounter = timedTokenCounter + 1
    local token = ('%x:%x:%x:%x'):format(source, now, timedTokenCounter, math.random(0x10000, 0xFFFFFF))
    actions[scope] = {
        token = token,
        subject = subject,
        startedAt = now,
        duration = duration,
        expiresAt = now + duration + (tonumber(config.graceMs) or 60000),
    }
    timedActions[source] = actions

    return token, nil, duration
end

function NexusContractsSecurityFallback.consumeTimedAction(source, scope, subject, token)
    warnFallbackActive()
    source = tonumber(source)
    scope = normalizeActionKey(scope, 32)
    subject = normalizeActionKey(subject, 120)
    if not source or source <= 0 or not scope or not subject or type(token) ~= 'string' then return false, 'invalid_action' end

    local actions = timedActions[source]
    local action = actions and actions[scope]
    if actions then actions[scope] = nil end
    if actions and not next(actions) then timedActions[source] = nil end
    if not action or action.token ~= token or action.subject ~= subject then return false, 'invalid_token' end

    local now = GetGameTimer()
    local tolerance = tonumber((security().timedActions or {}).earlyToleranceMs) or 250
    if now - action.startedAt < action.duration - tolerance then
        return false, 'too_early'
    end
    if now > action.expiresAt then return false, 'expired' end

    return true
end

function NexusContractsSecurityFallback.cancelTimedAction(source, scope, token)
    warnFallbackActive()
    source = tonumber(source)
    scope = normalizeActionKey(scope, 32)
    if not source or source <= 0 or not scope then return false end

    local actions = timedActions[source]
    local action = actions and actions[scope]
    if not action or (token and token ~= action.token) then return false end

    actions[scope] = nil
    if not next(actions) then timedActions[source] = nil end
    return true
end

AddEventHandler('playerDropped', function()
    local src = source
    timedActions[src] = nil
end)
