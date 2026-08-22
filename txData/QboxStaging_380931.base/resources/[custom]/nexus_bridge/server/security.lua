local buckets = {}
local timedActions = {}
local timedTokenCounter = 0

local function getLimit(bucket)
    return NexusBridgeConfig.rateLimits[bucket] or NexusBridgeConfig.rateLimits.default
end

function NexusRateLimit(source, bucket)
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
        NexusBridgeUtils.log('WARN', ('rate limit %s exceeded by source %s'):format(bucket, source))
        return false
    end

    return true
end

exports('rateLimit', NexusRateLimit)

local function normalizeActionKey(value, maxLength)
    value = NexusBridgeUtils.trim(tostring(value or ''), maxLength or 96)
    if value == '' or not value:match('^[%w_:%-%.]+$') then return nil end
    return value
end

function NexusBeginTimedAction(source, scope, subject, durationMs)
    source = tonumber(source)
    scope = normalizeActionKey(scope, 32)
    subject = normalizeActionKey(subject, 120)
    if not source or source <= 0 or not scope or not subject then return nil, 'invalid_action' end

    local config = NexusBridgeConfig.timedActions or {}
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

function NexusConsumeTimedAction(source, scope, subject, token)
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
    local tolerance = tonumber((NexusBridgeConfig.timedActions or {}).earlyToleranceMs) or 250
    if now - action.startedAt < action.duration - tolerance then
        NexusBridgeUtils.log('SECURITY', ('timed action completed too early source=%s subject=%s'):format(source, subject))
        return false, 'too_early'
    end
    if now > action.expiresAt then return false, 'expired' end

    return true
end

function NexusCancelTimedAction(source, scope, token)
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

exports('beginTimedAction', NexusBeginTimedAction)
exports('consumeTimedAction', NexusConsumeTimedAction)
exports('cancelTimedAction', NexusCancelTimedAction)

RegisterNetEvent(NexusBridge.events.securityFlag, function(reason)
    local src = source
    if not NexusRateLimit(src, 'default') then return end

    reason = NexusBridgeUtils.trim(reason, 120)
    NexusBridgeUtils.log('SECURITY', ('source %s flagged: %s'):format(src, reason))
end)

AddEventHandler('playerDropped', function()
    timedActions[source] = nil
end)

AddEventHandler('onResourceStop', function(resource)
    local prefix = tostring(resource) .. ':'
    for source, actions in pairs(timedActions) do
        for scope, action in pairs(actions) do
            if action.subject:sub(1, #prefix) == prefix then actions[scope] = nil end
        end
        if not next(actions) then timedActions[source] = nil end
    end
end)
