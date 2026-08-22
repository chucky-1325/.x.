NexusEMS = NexusEMS or {}

local pendingByMedic = {}
local activePatients = {}
local actionCooldowns = {}

local function nowMs()
    return GetGameTimer()
end

local function notify(source, description, notifyType)
    TriggerClientEvent('ox_lib:notify', source, {
        title = 'NEXUS Clinica',
        description = description,
        type = notifyType or 'inform',
    })
end

function NexusEMS.GetPlayer(source)
    source = tonumber(source)
    if not source or source <= 0 or GetResourceState('qbx_core') ~= 'started' then return nil end
    return exports.qbx_core:GetPlayer(source)
end

function NexusEMS.IsAdmin(source)
    source = tonumber(source)
    return source == 0 or (source and IsPlayerAceAllowed(source, NexusEMSConfig.adminAce or 'admin')) or false
end

function NexusEMS.IsMedic(source)
    source = tonumber(source)
    if not source then return false end
    if NexusEMS.IsAdmin(source) then return true end

    local player = NexusEMS.GetPlayer(source)
    local job = player and player.PlayerData and player.PlayerData.job or {}
    local grade = NexusEMS.IsAdmin(source) and 99 or NexusEMSUtils.gradeLevel(job)
    if NexusEMSJobs.jobTypes[job.type] then return true end
    return NexusEMSJobs.jobs[job.name] ~= nil and grade >= NexusEMSJobs.jobs[job.name]
end

local function pedCoords(source)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped), ped
end

function NexusEMS.IsNear(source, target, distance)
    local sourceCoords = pedCoords(source)
    local targetCoords = pedCoords(target)
    return sourceCoords and targetCoords and #(sourceCoords - targetCoords) <= (distance or NexusEMSConfig.maxPatientDistance)
end

local function deriveVitals(health, dead)
    if dead then return 'inconsciente', 0, 0, 3, 4 end
    if health <= 120 then return 'alterada', 124, 10, 3, 4 end
    if health <= 150 then return 'consciente', 104, 16, 2, 3 end
    if health <= 180 then return 'consciente', 88, 18, 1, 2 end
    return 'consciente', 72, 18, 0, 0
end

function NexusEMS.GetPatientState(target)
    local player = NexusEMS.GetPlayer(target)
    if not player then return nil end

    local coords, ped = pedCoords(target)
    if not coords or not ped then return nil end

    local metadata = player.PlayerData.metadata or {}
    local stored = type(metadata[NexusEMSConstants.medicalMetadata]) == 'table' and metadata[NexusEMSConstants.medicalMetadata] or {}
    local entityHealth = GetEntityHealth(ped)
    local health = entityHealth > 0 and entityHealth or tonumber(metadata.health) or NexusEMSConstants.healthMax
    health = NexusEMSUtils.clamp(health, 0, NexusEMSConstants.healthMax)
    local dead = health <= 100 or metadata.isdead == true or metadata.inlaststand == true
    local consciousness, pulse, respiration, derivedBleeding, derivedPain = deriveVitals(health, dead)

    local state = {
        health = health,
        dead = dead,
        consciousness = stored.consciousness or consciousness,
        pulse = tonumber(stored.pulse) or pulse,
        respiration = tonumber(stored.respiration) or respiration,
        bleeding = NexusEMSUtils.clamp(stored.bleeding ~= nil and stored.bleeding or derivedBleeding, 0, 4),
        pain = NexusEMSUtils.clamp(stored.pain ~= nil and stored.pain or derivedPain, 0, 4),
        stabilized = stored.stabilized == true,
        transportReady = stored.transportReady == true,
    }

    if state.dead then
        state.consciousness = 'inconsciente'
        state.pulse = 0
        state.respiration = 0
        state.stabilized = false
    end

    return state, player, coords
end

local function actionAllowed(actionId, state)
    if actionId == 'assess' then return true end
    if actionId == 'bandage' then return not state.dead and state.bleeding > 0 end
    if actionId == 'pain_relief' then return not state.dead and state.pain > 0 end
    if actionId == 'stabilize' then return not state.dead and (state.health < 180 or state.bleeding > 0) end
    if actionId == 'resuscitate' then return state.dead end
    if actionId == 'prepare_transport' then return not state.dead and (state.stabilized or state.health >= 130) end
    return false
end

local function findItem(source, action)
    local items = action.items or {}
    if #items == 0 then return nil, true end
    for i = 1, #items do
        if (exports.ox_inventory:GetItemCount(source, items[i]) or 0) > 0 then return items[i], true end
    end
    return items[1], false
end

local function cooldownKey(source, target, actionId)
    return ('%s:%s:%s'):format(source, target, actionId)
end

local function isCoolingDown(source, target, actionId)
    return os.time() < (actionCooldowns[cooldownKey(source, target, actionId)] or 0)
end

local function setCooldown(source, target, actionId)
    local action = NexusEMSConfig.actions[actionId] or {}
    actionCooldowns[cooldownKey(source, target, actionId)] = os.time() + (tonumber(action.cooldownSeconds) or (actionId == 'assess' and 45 or 10))
end

local function publicActions(source, state)
    local player = NexusEMS.GetPlayer(source)
    local job = player and player.PlayerData and player.PlayerData.job or {}
    local grade = NexusEMSUtils.gradeLevel(job)
    local actions = {}

    for actionId, action in pairs(NexusEMSConfig.actions) do
        local itemName, hasRequired = findItem(source, action)
        actions[#actions + 1] = {
            id = actionId,
            label = action.label,
            description = action.description,
            item = itemName,
            available = actionAllowed(actionId, state) and hasRequired and grade >= (tonumber(action.minGrade) or 0),
        }
    end

    table.sort(actions, function(a, b)
        local order = { assess = 1, bandage = 2, pain_relief = 3, stabilize = 4, resuscitate = 5, prepare_transport = 6 }
        return (order[a.id] or 99) < (order[b.id] or 99)
    end)
    return actions
end

function NexusEMS.BuildPatientPayload(source, target)
    local state, player = NexusEMS.GetPatientState(target)
    if not state or not player then return nil end

    local charinfo = player.PlayerData.charinfo or {}
    local name = (('%s %s'):format(charinfo.firstname or '', charinfo.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
    return {
        patient = {
            serverId = target,
            name = name ~= '' and name or ('Paciente #%s'):format(target),
            citizenid = player.PlayerData.citizenid,
        },
        vitals = state,
        actions = publicActions(source, state),
        hospital = { x = NexusEMSConfig.hospital.x, y = NexusEMSConfig.hospital.y, z = NexusEMSConfig.hospital.z },
    }
end

local function clearPending(source)
    local pending = pendingByMedic[source]
    if pending and activePatients[pending.target] == source then activePatients[pending.target] = nil end
    pendingByMedic[source] = nil
end

function NexusEMS.PrepareAction(source, target, actionId)
    source = tonumber(source)
    target = tonumber(target)
    actionId = tostring(actionId or '')
    local action = NexusEMSConfig.actions[actionId]
    if not NexusEMS.IsMedic(source) then return false, 'forbidden' end
    if not target or target <= 0 or target == source or not NexusEMS.GetPlayer(target) then return false, 'invalid_patient' end
    if not action then return false, 'invalid_action' end

    local existing = pendingByMedic[source]
    if existing and nowMs() > (existing.expiresAt or 0) then
        exports.nexus_bridge:cancelTimedAction(source, NexusEMSConstants.physicalScope, existing.token)
        clearPending(source)
        existing = nil
    end
    if existing then return false, 'physical_busy' end
    if activePatients[target] and activePatients[target] ~= source then return false, 'patient_busy' end
    if not NexusEMS.IsNear(source, target) then return false, 'too_far' end
    if isCoolingDown(source, target, actionId) then return false, 'cooldown' end

    local state, _, targetCoords = NexusEMS.GetPatientState(target)
    if not state or not actionAllowed(actionId, state) then return false, 'not_indicated' end

    local medic = NexusEMS.GetPlayer(source)
    local grade = NexusEMS.IsAdmin(source) and 99 or NexusEMSUtils.gradeLevel(medic.PlayerData.job)
    if grade < (tonumber(action.minGrade) or 0) then return false, 'grade' end

    local selectedItem, hasRequired = findItem(source, action)
    if not hasRequired then return false, ('missing_item:%s'):format(selectedItem or 'medical') end

    local subject = ('nexus_ems:%s:%s'):format(actionId, target)
    local token, reason, duration = exports.nexus_bridge:beginTimedAction(
        source,
        NexusEMSConstants.physicalScope,
        subject,
        action.duration
    )
    if not token then return false, reason == 'busy' and 'physical_busy' or reason end

    pendingByMedic[source] = {
        token = token,
        target = target,
        actionId = actionId,
        subject = subject,
        item = selectedItem,
        expiresAt = nowMs() + duration + NexusEMSConfig.actionExpiryGraceMs,
    }
    activePatients[target] = source

    return true, {
        token = token,
        target = target,
        duration = duration,
        sceneId = action.scene,
        label = action.label,
        coords = { x = targetCoords.x, y = targetCoords.y, z = targetCoords.z },
    }
end

local function applyEffect(target, state, effect)
    effect = effect or {}
    local updated = NexusEMSUtils.copy(state)
    updated.bleeding = NexusEMSUtils.clamp(updated.bleeding + (effect.bleeding or 0), 0, 4)
    updated.pain = NexusEMSUtils.clamp(updated.pain + (effect.pain or 0), 0, 4)
    updated.health = NexusEMSUtils.clamp(updated.health + (effect.health or 0), 0, NexusEMSConstants.healthMax)
    if effect.minimumHealth then updated.health = math.max(updated.health, effect.minimumHealth) end
    if effect.stabilized ~= nil then updated.stabilized = effect.stabilized end
    if effect.transportReady ~= nil then updated.transportReady = effect.transportReady end

    if effect.revive then
        updated.dead = false
        updated.consciousness = 'alterada'
        updated.pulse = 108
        updated.respiration = 12
    elseif not updated.dead then
        updated.consciousness, updated.pulse, updated.respiration = deriveVitals(updated.health, false)
    end

    local player = NexusEMS.GetPlayer(target)
    player.Functions.SetMetaData(NexusEMSConstants.medicalMetadata, {
        consciousness = updated.consciousness,
        pulse = updated.pulse,
        respiration = updated.respiration,
        bleeding = updated.bleeding,
        pain = updated.pain,
        stabilized = updated.stabilized,
        transportReady = updated.transportReady,
    })
    player.Functions.SetMetaData('health', updated.health)
    if effect.revive then
        player.Functions.SetMetaData('isdead', false)
        player.Functions.SetMetaData('inlaststand', false)
    end

    TriggerClientEvent('nexus_ems:client:applyTreatment', target, {
        health = updated.health,
        revive = effect.revive == true,
    })
    return updated
end

function NexusEMS.FinishAction(source, actionToken)
    local pending = pendingByMedic[source]
    if not pending or pending.token ~= actionToken then return false, 'invalid_token' end

    local target = pending.target
    local actionId = pending.actionId
    local action = NexusEMSConfig.actions[actionId]
    clearPending(source)

    local consumed, reason = exports.nexus_bridge:consumeTimedAction(
        source,
        NexusEMSConstants.physicalScope,
        pending.subject,
        actionToken
    )
    if not consumed then return false, reason end
    if not NexusEMS.IsMedic(source) or not NexusEMS.IsNear(source, target) then return false, 'too_far' end

    local before, patient = NexusEMS.GetPatientState(target)
    if not before or not patient or not actionAllowed(actionId, before) then return false, 'not_indicated' end
    if pending.item and not exports.ox_inventory:RemoveItem(source, pending.item, 1) then return false, 'missing_item' end

    local after = before
    if actionId ~= 'assess' then after = applyEffect(target, before, NexusEMSConfig.effects[actionId]) end
    setCooldown(source, target, actionId)

    local medic = NexusEMS.GetPlayer(source)
    local medicCitizenId = medic.PlayerData.citizenid
    if GetResourceState('nexus_progression') == 'started' then
        exports.nexus_progression:addProgression(medicCitizenId, NexusEMSConfig.progression.domain, action.xp or 0, action.reputation or 0)
        TriggerClientEvent('nexus_progression:client:tick', source, NexusEMSConfig.progression.domain, action.xp or 0, action.reputation or 0)
    end

    NexusEMSDatabase.LogEvent(patient.PlayerData.citizenid, medicCitizenId, actionId, before, after)
    notify(source, ('%s completado.'):format(action.label), 'success')

    local payload = NexusEMS.BuildPatientPayload(source, target)
    payload.completedAction = actionId
    return true, payload
end

function NexusEMS.CancelAction(source, actionToken)
    local pending = pendingByMedic[source]
    if not pending or pending.token ~= actionToken then return false end
    exports.nexus_bridge:cancelTimedAction(source, NexusEMSConstants.physicalScope, actionToken)
    clearPending(source)
    return true
end

function NexusEMS.HandleDrop(source)
    NexusEMS.CancelAction(source, pendingByMedic[source] and pendingByMedic[source].token)
    local medic = activePatients[source]
    if medic then clearPending(medic) end
    activePatients[source] = nil

    local sourcePrefix = ('%s:'):format(source)
    local targetNeedle = (':%s:'):format(source)
    for key in pairs(actionCooldowns) do
        if key:sub(1, #sourcePrefix) == sourcePrefix or key:find(targetNeedle, 1, true) then
            actionCooldowns[key] = nil
        end
    end
end
