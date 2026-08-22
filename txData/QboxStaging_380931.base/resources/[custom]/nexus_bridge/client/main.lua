local cachedIdentity = nil

local function getIdentity()
    if cachedIdentity then return NexusBridgeUtils.copy(cachedIdentity) end
    if GetResourceState('qbx_identity_aaa') ~= 'started' then return nil end

    cachedIdentity = exports.qbx_identity_aaa:getIdentity()
    return NexusBridgeUtils.copy(cachedIdentity)
end

exports('getIdentity', getIdentity)

exports('getTheme', function()
    local identity = getIdentity()
    return identity and identity.theme or {}
end)

exports('notify', function(data)
    if type(data) ~= 'table' then return end

    if lib and lib.notify then
        lib.notify({
            title = data.title or 'NEXUS',
            description = data.description or data.message,
            type = data.type or 'inform',
            duration = data.duration or 3500,
        })
    end
end)
