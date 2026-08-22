RegisterNUICallback('close', function(_, cb)
    NexusEMSClient.CloseTablet()
    cb({ success = true })
end)

RegisterNUICallback('treat', function(data, cb)
    local target = NexusEMSClient.currentPatient
    local actionId = type(data) == 'table' and tostring(data.actionId or '') or ''
    if not target or not NexusEMSConfig.actions[actionId] then
        cb({ success = false })
        return
    end

    NexusEMSClient.CloseTablet()
    cb({ success = true, pending = true })
    CreateThread(function()
        NexusEMSClient.RunAction(target, actionId)
    end)
end)

RegisterNUICallback('setWaypoint', function(_, cb)
    SetNewWaypoint(NexusEMSConfig.hospital.x, NexusEMSConfig.hospital.y)
    cb({ success = true })
end)

