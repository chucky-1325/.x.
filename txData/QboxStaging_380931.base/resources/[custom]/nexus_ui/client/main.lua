local identityCache = nil

local function getIdentity()
    if identityCache then return identityCache end
    if GetResourceState('nexus_bridge') == 'started' then
        identityCache = exports.nexus_bridge:getIdentity()
    elseif GetResourceState('qbx_identity_aaa') == 'started' then
        identityCache = exports.qbx_identity_aaa:getIdentity()
    end

    return identityCache
end

local function getDesignSystem(variant)
    local identity = getIdentity() or {}
    local theme = identity.theme or {}
    local selected = NexusUiConfig.variants[variant or NexusUiConfig.defaultVariant] or NexusUiConfig.variants.civil

    return {
        brand = identity.brand or {},
        theme = theme,
        tokens = NexusUiTokens,
        variant = selected,
        variants = NexusUiConfig.variants,
    }
end

exports('getDesignSystem', getDesignSystem)
exports('getTokens', function() return NexusUiTokens end)
exports('getVariant', function(variant) return NexusUiConfig.variants[variant] end)

exports('notify', function(data)
    if type(data) ~= 'table' then return end

    if GetResourceState('nexus_bridge') == 'started' then
        exports.nexus_bridge:notify(data)
    elseif lib and lib.notify then
        lib.notify(data)
    end
end)

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Wait(500)
    print('[nexus_ui] design system cargado')
end)
