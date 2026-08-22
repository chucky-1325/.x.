exports('play', function(sceneId, context)
    return NexusSceneRuntime.play(sceneId, context)
end)

exports('cancel', function()
    return NexusSceneRuntime.cancel()
end)

exports('isPlaying', function()
    return NexusSceneRuntime.isPlaying()
end)

exports('getDefinition', function(sceneId)
    local definition = NexusSceneDefinitions[sceneId]
    return definition and NexusSceneUtils.copy(definition) or nil
end)

if NexusSceneConfig.debug then
    RegisterCommand('scenetest', function(_, args)
        local sceneId = args[1] or 'craft_civil'
        local completed, reason = NexusSceneRuntime.play(sceneId, { duration = 5000 })
        print(('[nexus_scene_core] test %s -> %s (%s)'):format(sceneId, tostring(completed), tostring(reason)))
    end, false)
end

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    print(('[nexus_scene_core] escenas fisicas cargadas v%s'):format(NexusSceneConstants.VERSION))
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    NexusSceneRuntime.cancel()
end)
