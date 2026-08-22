AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    NexusBridgeUtils.log('INFO', 'bridge tecnico cargado')
end)

exports('getIdentity', function()
    if GetResourceState('qbx_identity_aaa') ~= 'started' then return nil end

    return exports.qbx_identity_aaa:getIdentity()
end)

exports('getTheme', function()
    if GetResourceState('qbx_identity_aaa') ~= 'started' then return {} end

    return exports.qbx_identity_aaa:getTheme()
end)
