exports('getDesignSystem', function(variant)
    local identity = nil
    if GetResourceState('nexus_bridge') == 'started' then
        identity = exports.nexus_bridge:getIdentity()
    elseif GetResourceState('qbx_identity_aaa') == 'started' then
        identity = exports.qbx_identity_aaa:getIdentity()
    end

    local selected = NexusUiConfig.variants[variant or NexusUiConfig.defaultVariant] or NexusUiConfig.variants.civil

    return {
        brand = identity and identity.brand or {},
        theme = identity and identity.theme or {},
        tokens = NexusUiTokens,
        variant = selected,
        variants = NexusUiConfig.variants,
    }
end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    print('[nexus_ui] design system cargado')
end)
