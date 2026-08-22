RegisterNetEvent('nexus_ems:server:cancelAction', function(actionToken)
    NexusEMS.CancelAction(source, actionToken)
end)

AddEventHandler('playerDropped', function()
    NexusEMS.HandleDrop(source)
end)

