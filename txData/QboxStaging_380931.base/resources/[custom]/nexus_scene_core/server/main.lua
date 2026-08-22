exports('isRegistered', function(sceneId)
    return NexusSceneSecurity.isRegistered(sceneId)
end)

exports('getMetadata', function(sceneId)
    return NexusSceneSecurity.getMetadata(sceneId)
end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    local count = 0
    for _ in pairs(NexusSceneDefinitions) do count = count + 1 end
    print(('[nexus_scene_core] %s escenas registradas; autoridad economica permanece en recursos dueños'):format(count))
end)
