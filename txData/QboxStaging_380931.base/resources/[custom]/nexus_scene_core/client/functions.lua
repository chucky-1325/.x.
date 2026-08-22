NexusSceneRuntime = {}

local activeScene

local function requestAnimation(dictionary)
    if type(dictionary) ~= 'string' or dictionary == '' then return false end
    if HasAnimDictLoaded(dictionary) then return true end

    RequestAnimDict(dictionary)
    local timeout = GetGameTimer() + 5000
    while not HasAnimDictLoaded(dictionary) and GetGameTimer() < timeout do
        Wait(0)
    end

    return HasAnimDictLoaded(dictionary)
end

local function requestModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then return nil end
    if HasModelLoaded(hash) then return hash end

    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do
        Wait(0)
    end

    return HasModelLoaded(hash) and hash or nil
end

local function requestEntityControl(entity)
    if not NetworkGetEntityIsNetworked(entity) or NetworkHasControlOfEntity(entity) then return end

    NetworkRequestControlOfEntity(entity)
    local timeout = GetGameTimer() + 500
    while not NetworkHasControlOfEntity(entity) and GetGameTimer() < timeout do
        Wait(0)
        NetworkRequestControlOfEntity(entity)
    end
end

local function deleteProp(entity)
    if not entity or not DoesEntityExist(entity) then return end
    requestEntityControl(entity)
    DetachEntity(entity, true, true)
    SetEntityAsMissionEntity(entity, true, true)
    DeleteObject(entity)
    if DoesEntityExist(entity) then DeleteEntity(entity) end
end

local function stopEffect(handle)
    if handle then StopParticleFxLooped(handle, false) end
end

function NexusSceneRuntime.cleanup()
    if not activeScene then return end

    local scene = activeScene
    activeScene = nil

    if scene.animation and DoesEntityExist(scene.ped) then
        StopAnimTask(scene.ped, scene.animation.dict, scene.animation.clip, 2.0)
    end

    for i = 1, #(scene.props or {}) do
        deleteProp(scene.props[i])
    end

    for i = 1, #(scene.effects or {}) do
        stopEffect(scene.effects[i])
    end

    if LocalPlayer and LocalPlayer.state then
        LocalPlayer.state:set('nexusScene', false, true)
    end
end

local function createAttachedProp(ped, definition)
    if type(definition) ~= 'table' or not definition.model then return nil end

    local hash = requestModel(definition.model)
    if not hash then return nil end

    local coords = GetEntityCoords(ped)
    local entity = CreateObjectNoOffset(
        hash,
        coords.x,
        coords.y,
        coords.z,
        NexusSceneConfig.networkedProps == true,
        NexusSceneConfig.networkedProps == true,
        false
    )

    if not DoesEntityExist(entity) then
        SetModelAsNoLongerNeeded(hash)
        return nil
    end

    SetEntityCollision(entity, false, false)
    local position = definition.position or {}
    local rotation = definition.rotation or {}
    AttachEntityToEntity(
        entity,
        ped,
        GetPedBoneIndex(ped, tonumber(definition.bone) or 57005),
        tonumber(position.x) or 0.0,
        tonumber(position.y) or 0.0,
        tonumber(position.z) or 0.0,
        tonumber(rotation.x) or 0.0,
        tonumber(rotation.y) or 0.0,
        tonumber(rotation.z) or 0.0,
        true,
        true,
        false,
        true,
        1,
        true
    )
    SetModelAsNoLongerNeeded(hash)

    return entity
end

local function startEffect(entity, definition)
    if type(definition) ~= 'table' or not definition.dictionary or not definition.name then return nil end

    RequestNamedPtfxAsset(definition.dictionary)
    local timeout = GetGameTimer() + 3000
    while not HasNamedPtfxAssetLoaded(definition.dictionary) and GetGameTimer() < timeout do
        Wait(0)
    end
    if not HasNamedPtfxAssetLoaded(definition.dictionary) then return nil end

    UseParticleFxAssetNextCall(definition.dictionary)
    local position = definition.position or {}
    local rotation = definition.rotation or {}
    return StartParticleFxLoopedOnEntity(
        definition.name,
        entity,
        tonumber(position.x) or 0.0,
        tonumber(position.y) or 0.0,
        tonumber(position.z) or 0.0,
        tonumber(rotation.x) or 0.0,
        tonumber(rotation.y) or 0.0,
        tonumber(rotation.z) or 0.0,
        tonumber(definition.scale) or 1.0,
        false,
        false,
        false
    )
end

local function turnToTarget(ped, target)
    if not NexusSceneConfig.turnToTarget then return end
    local coords = NexusSceneUtils.toCoords(target)
    if not coords then return end

    TaskTurnPedToFaceCoord(ped, coords.x, coords.y, coords.z, NexusSceneConfig.turnTimeout)
    Wait(NexusSceneConfig.turnTimeout)
end

function NexusSceneRuntime.play(sceneId, context)
    if activeScene then return false, 'busy' end
    if not NexusSceneUtils.isValidId(sceneId) then return false, 'invalid_scene' end

    local definition = NexusSceneDefinitions[sceneId]
    if type(definition) ~= 'table' then return false, 'invalid_scene' end

    context = type(context) == 'table' and context or {}
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) or IsEntityDead(ped) then return false, 'invalid_ped' end

    local duration = NexusSceneUtils.clamp(
        context.duration or definition.duration or 5000,
        NexusSceneConstants.MIN_DURATION,
        NexusSceneConstants.MAX_DURATION
    )
    local animation = definition.animation
    if animation and not requestAnimation(animation.dict) then return false, 'animation_failed' end

    turnToTarget(ped, context.targetCoords)

    activeScene = {
        id = sceneId,
        ped = ped,
        animation = animation,
        props = {},
        effects = {},
        startedAt = GetGameTimer(),
    }

    if LocalPlayer and LocalPlayer.state then
        LocalPlayer.state:set('nexusScene', sceneId, true)
    end

    for i = 1, math.min(#(definition.props or {}), NexusSceneConstants.MAX_PROPS) do
        local entity = createAttachedProp(ped, definition.props[i])
        if entity then activeScene.props[#activeScene.props + 1] = entity end
    end

    if animation then
        TaskPlayAnim(
            ped,
            animation.dict,
            animation.clip,
            tonumber(animation.blendIn) or 3.0,
            tonumber(animation.blendOut) or 3.0,
            -1,
            tonumber(animation.flag) or 1,
            0.0,
            false,
            false,
            false
        )
    end

    for i = 1, #(definition.effects or {}) do
        local handle = startEffect(ped, definition.effects[i])
        if handle then activeScene.effects[#activeScene.effects + 1] = handle end
    end

    local completed = lib.progressBar({
        duration = duration,
        label = context.label or definition.label or 'Realizando accion',
        position = NexusSceneConfig.progressPosition,
        useWhileDead = false,
        canCancel = context.canCancel ~= false,
        disable = NexusSceneConfig.controls,
    })

    NexusSceneRuntime.cleanup()
    return completed == true, completed and 'completed' or 'cancelled'
end

function NexusSceneRuntime.cancel()
    if not activeScene then return false end
    if lib and lib.cancelProgress then lib.cancelProgress() end
    NexusSceneRuntime.cleanup()
    return true
end

function NexusSceneRuntime.isPlaying()
    return activeScene ~= nil, activeScene and activeScene.id or nil
end
