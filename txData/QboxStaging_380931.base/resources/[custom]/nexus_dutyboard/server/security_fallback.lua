-- NEXUS-VENDORED-FALLBACK
-- source: nexus_bridge/server/security.lua (solo NexusRateLimit)
-- source_sha256: c7c160d90f5e65aebabdf4c28e866b5328352aa644056187ebb20df3d2937a68
-- vendored_at: 2026-08-28
-- Adaptado para nexus_dutyboard: sin exports(), sin NexusBridgeConfig/NexusBridgeUtils,
-- usa NexusDutyboardConfig.security, expuesto como tabla NexusDutyboardSecurityFallback.
-- Solo cubre rateLimit -- nexus_dutyboard no usa timed actions (no tiene tokens de
-- accion fisica en su flujo, es un simple toggle de duty con cooldown local).
--
-- NO editar la logica de negocio aqui sin editar primero el canonico y
-- re-vendorizar (actualizar source_sha256 arriba). Verificar equivalencia con
-- test/verify_security_fallback.lua y deriva de hash con
-- test/verify_vendored_hash.sh antes de cada release.

NexusDutyboardSecurityFallback = {}

local buckets = {}
local warnedOnce = false

local function security()
    return NexusDutyboardConfig.security or {}
end

local function getLimit(bucket)
    local limits = security().rateLimits or {}
    return limits[bucket] or limits.default or { window = 10000, limit = 8 }
end

local function warnFallbackActive()
    if warnedOnce then return end
    warnedOnce = true
    print('[nexus_dutyboard] AVISO: nexus_bridge no disponible -- usando fallback de seguridad local (rate limit aislado a este recurso).')
end

function NexusDutyboardSecurityFallback.rateLimit(source, bucket)
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
