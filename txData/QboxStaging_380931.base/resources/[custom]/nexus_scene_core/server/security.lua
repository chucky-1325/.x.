NexusSceneSecurity = {}

function NexusSceneSecurity.isRegistered(sceneId)
    return NexusSceneUtils.isValidId(sceneId) and type(NexusSceneDefinitions[sceneId]) == 'table'
end

function NexusSceneSecurity.getMetadata(sceneId)
    if not NexusSceneSecurity.isRegistered(sceneId) then return nil end

    local definition = NexusSceneDefinitions[sceneId]
    return {
        id = sceneId,
        label = definition.label,
        duration = definition.duration,
    }
end
