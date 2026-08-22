RegisterCommand(NexusEMSConfig.command, function()
    local allowed = lib.callback.await('nexus_ems:server:canUse', false)
    if not allowed then return NexusEMSClient.Notify(NexusEMSLocale.noAccess, 'error') end

    local target = NexusEMSClient.GetClosestPatient(NexusEMSConfig.maxPatientDistance)
    if not target then return NexusEMSClient.Notify(NexusEMSLocale.noPatient, 'error') end
    NexusEMSClient.AssessPatient(target)
end, false)

RegisterNetEvent('nexus_ems:client:applyTreatment', function(data)
    if type(data) ~= 'table' then return end
    local ped = PlayerPedId()

    if data.revive then
        local coords = GetEntityCoords(ped)
        NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, GetEntityHeading(ped), true, false)
        ClearPedBloodDamage(ped)
        ClearPedTasksImmediately(ped)
    end

    SetEntityHealth(ped, math.floor(tonumber(data.health) or GetEntityHealth(ped)))
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    NexusEMSClient.CloseTablet()
    if NexusEMSClient.activeToken then
        TriggerServerEvent('nexus_ems:server:cancelAction', NexusEMSClient.activeToken)
    end
    if GetResourceState('nexus_scene_core') == 'started' then exports.nexus_scene_core:cancel() end
    pcall(function() exports.ox_target:removeGlobalPlayer('nexus_ems_assess') end)
end)

CreateThread(function()
    Wait(1000)
    SendNUIMessage({ action = 'close' })
    print('[nexus_ems] cliente clinico cargado')
end)

