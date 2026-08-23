local activeOperations = {}

local function physicalSubject(stage, operationId)
    return ('nexus_operations:%s:%s'):format(tostring(stage), tostring(operationId))
end

local function beginPhysicalAction(source, stage, operationId, duration)
    if GetResourceState('nexus_bridge') ~= 'started' then return nil, 'security_unavailable' end
    return exports.nexus_bridge:beginTimedAction(source, 'physical', physicalSubject(stage, operationId), duration)
end

local function consumePhysicalAction(source, stage, operationId, token)
    if GetResourceState('nexus_bridge') ~= 'started' then return false, 'security_unavailable' end
    return exports.nexus_bridge:consumeTimedAction(source, 'physical', physicalSubject(stage, operationId), token)
end

local function cancelPhysicalAction(source, token)
    if GetResourceState('nexus_bridge') ~= 'started' then return false end
    return exports.nexus_bridge:cancelTimedAction(source, 'physical', token)
end

local function notify(source, description, notifyType)
    TriggerClientEvent('ox_lib:notify', source, {
        title = 'Operaciones',
        description = description,
        type = notifyType or 'inform',
    })
end

local function rateLimit(source)
    source = tonumber(source)
    if not source or source <= 0 then return false end
    if GetResourceState('nexus_bridge') ~= 'started' then return true end
    return exports.nexus_bridge:rateLimit(source, NexusOperationsConfig.rateLimitBucket or 'default')
end

local function getPlayer(source)
    if GetResourceState('qbx_core') ~= 'started' then return nil end
    source = tonumber(source)
    if not source or source <= 0 then return nil end
    return exports.qbx_core:GetPlayer(source)
end

local function getCitizenId(source)
    local player = getPlayer(source)
    return player and player.PlayerData and player.PlayerData.citizenid or nil
end

local function getGang(source)
    if GetResourceState('nexus_gangs') == 'started' then
        local ok, gang = pcall(function()
            return exports.nexus_gangs:getPlayerGang(source)
        end)
        if ok and gang then return gang end
    end

    local player = getPlayer(source)
    local gang = player and player.PlayerData and player.PlayerData.gang or {}
    return {
        name = gang.name or 'none',
        label = gang.label or 'Sin banda',
        rank = gang.grade and gang.grade.level or 0,
        rankLabel = gang.grade and gang.grade.name or 'Civil',
    }
end

local function getProgress(source)
    local citizenid = getCitizenId(source)
    if not citizenid or GetResourceState('nexus_progression') ~= 'started' then return {} end
    return exports.nexus_progression:getProgressionByCitizen(citizenid) or {}
end

local function packageItem()
    return NexusOperationsConfig.supplyPackageItem or 'nexus_contract_package'
end

local function getOperationPackageSlots(source, operationId)
    if GetResourceState('ox_inventory') ~= 'started' then return {} end

    local slots = exports.ox_inventory:GetSlotsWithItem(source, packageItem()) or {}
    local owned = {}
    for i = 1, #slots do
        local metadata = slots[i].metadata or {}
        if metadata.operation and (not operationId or tostring(metadata.operation) == tostring(operationId)) then
            owned[#owned + 1] = slots[i]
        end
    end

    return owned
end

local function hasAnyPackage(source)
    if GetResourceState('ox_inventory') ~= 'started' then return false end
    return (exports.ox_inventory:GetItemCount(source, packageItem()) or 0) > 0
end

local function hasPackage(source, operationId)
    return #getOperationPackageSlots(source, operationId) > 0
end

local function givePackage(source, operationId)
    if GetResourceState('ox_inventory') ~= 'started' then return false end
    if not exports.ox_inventory:CanCarryItem(source, packageItem(), 1) then return false end

    return exports.ox_inventory:AddItem(source, packageItem(), 1, {
        operation = operationId,
        label = 'Paquete de suministros',
    })
end

local function removePackage(source, operationId)
    if GetResourceState('ox_inventory') ~= 'started' then return false end
    local slot = getOperationPackageSlots(source, operationId)[1]
    if not slot then return false end

    return exports.ox_inventory:RemoveItem(source, packageItem(), 1, slot.metadata, slot.slot, false, true)
end

local function clearPackage(source, operationId)
    if GetResourceState('ox_inventory') ~= 'started' then return end

    local slots = getOperationPackageSlots(source, operationId)
    for i = 1, #slots do
        local slot = slots[i]
        exports.ox_inventory:RemoveItem(source, packageItem(), slot.count, slot.metadata, slot.slot, true, true)
    end
end

local function isNear(source, coords, distance)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return false end
    return #(GetEntityCoords(ped) - coords) <= (distance or NexusOperationsConfig.interactDistance or 4.0)
end

local function vecTo3(coords)
    if not coords then return nil end
    return vector3(coords.x, coords.y, coords.z)
end

local function getZoneState(zoneId)
    if not zoneId or GetResourceState('nexus_territories') ~= 'started' then return nil end

    local ok, state = pcall(function()
        return exports.nexus_territories:getZoneState(zoneId)
    end)

    return ok and state or nil
end

local function territorialModifiers(gangName, operation)
    local zone = getZoneState(operation.zoneId)
    if type(zone) ~= 'table' then return 0, 0, 'neutral' end

    local owner = zone.owner or zone.ownerGang or zone.gang
    local status = zone.status or 'neutral'
    if owner == gangName then
        return -5, 2, status
    end

    if owner and owner ~= 'none' and owner ~= gangName then
        return 10, 3, status
    end

    if status == 'contested' then
        return 6, 2, status
    end

    return 0, 0, status
end

local function sanitizeRoute(route)
    if type(route) ~= 'table' then return nil end

    return {
        label = route.label,
        pickup = route.pickup,
        dropoff = route.dropoff,
        point = route.point,
        riskModifier = tonumber(route.riskModifier) or 0,
        influenceModifier = tonumber(route.influenceModifier) or 0,
        npc = route.npc,
    }
end

local function chooseRoute(operation)
    local routes = operation.routes or {}
    if #routes > 0 then
        return sanitizeRoute(routes[math.random(#routes)])
    end

    return sanitizeRoute({
        label = operation.label,
        pickup = operation.pickup,
        dropoff = operation.dropoff,
        point = operation.point,
        riskModifier = 0,
        influenceModifier = 0,
    })
end

local function runtimeOperation(base, active)
    if not base or not active then return nil end

    local route = active.route or {}
    local operation = {}
    for key, value in pairs(base) do operation[key] = value end

    operation.id = active.id or base.id
    operation.route = route
    operation.routeLabel = route.label
    operation.pickup = vecTo3(route.pickup or base.pickup)
    operation.dropoff = vecTo3(route.dropoff or base.dropoff)
    operation.point = vecTo3(route.point or base.point)
    operation.policeAlertChance = active.policeAlertChance or base.policeAlertChance or 0
    operation.influence = active.influence or base.influence or 0
    operation.zoneStatus = active.zoneStatus

    return operation
end

local function canAccess(source, operation)
    local gang = getGang(source)
    if not gang or not gang.name or gang.name == 'none' then return false, 'no_gang', gang end

    if (tonumber(gang.rank) or 0) < (operation.requiredRank or 0) then
        return false, 'rank', gang
    end

    local criminal = (getProgress(source).criminal or {})
    if (tonumber(criminal.reputation) or 0) < (operation.minCriminalReputation or 0) then
        return false, 'reputation', gang
    end

    local cooldown = NexusOperationsGetCooldown(gang.name, operation.id)
    if cooldown > 0 then return false, 'cooldown', gang, cooldown end

    return true, nil, gang
end

local function canAccessLite(source, operation)
    local gang = getGang(source)
    if not gang or not gang.name or gang.name == 'none' then return false, 'no_gang', gang end

    if (tonumber(gang.rank) or 0) < (operation.requiredRank or 0) then
        return false, 'rank', gang
    end

    local criminal = (getProgress(source).criminal or {})
    if (tonumber(criminal.reputation) or 0) < (operation.minCriminalReputation or 0) then
        return false, 'reputation', gang
    end

    return true, nil, gang
end

local function buildOperations(source)
    local list = {}
    local gang = getGang(source)

    for operationId, operation in pairs(NexusOperationsConfig.operations or {}) do
        operation.id = operationId
        local unlocked, reason, _, cooldown = canAccess(source, operation)
        list[#list + 1] = {
            id = operationId,
            label = operation.label,
            type = operation.type,
            description = operation.description,
            requiredRank = operation.requiredRank or 0,
            minCriminalReputation = operation.minCriminalReputation or 0,
            policeAlertChance = operation.policeAlertChance or 0,
            influence = operation.influence or 0,
            routeCount = #(operation.routes or {}),
            rewards = operation.rewards,
            unlocked = unlocked,
            lockedReason = reason,
            cooldownRemaining = cooldown or (gang and gang.name ~= 'none' and NexusOperationsGetCooldown(gang.name, operationId) or 0),
        }
    end

    table.sort(list, function(a, b)
        return a.minCriminalReputation < b.minCriminalReputation
    end)

    return list
end

local function buildOperationsLite(source)
    local list = {}

    for operationId, operation in pairs(NexusOperationsConfig.operations or {}) do
        local unlocked, reason = canAccessLite(source, operation)
        list[#list + 1] = {
            id = operationId,
            label = operation.label,
            type = operation.type,
            description = operation.description,
            requiredRank = operation.requiredRank or 0,
            minCriminalReputation = operation.minCriminalReputation or 0,
            policeAlertChance = operation.policeAlertChance or 0,
            influence = operation.influence or 0,
            routeCount = #(operation.routes or {}),
            rewards = operation.rewards,
            unlocked = unlocked,
            lockedReason = reason,
            cooldownRemaining = 0,
        }
    end

    table.sort(list, function(a, b)
        return a.minCriminalReputation < b.minCriminalReputation
    end)

    return list
end

local function sendDispatchAlert(operation, context)
    if GetResourceState('nexus_dispatch') ~= 'started' then return end

    context = context or {}
    local coords = operation.pickup or operation.point or operation.dropoff
    pcall(function()
        exports.nexus_dispatch:createAlert({
            type = 'operations',
            title = 'Operacion de banda',
            message = context.message or (operation.label or 'Movimiento de banda'),
            coords = coords,
            zoneId = operation.zoneId,
            sourceResource = GetCurrentResourceName(),
            sourcePlayer = context.source,
            gangName = context.gangName,
            risk = operation.policeAlertChance or 0,
            priority = 2,
        })
    end)
end

local function alertPolice(operation, context)
    if math.random(100) > (operation.policeAlertChance or 0) then return false end

    local coords = operation.pickup or operation.point or operation.dropoff
    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        local player = getPlayer(src)
        local job = player and player.PlayerData and player.PlayerData.job
        if job and NexusOperationsConfig.policeJobs[job.name] then
            TriggerClientEvent('nexus_operations:client:policeAlert', src, {
                label = operation.label,
                coords = coords,
            })
        end
    end

    sendDispatchAlert(operation, context)
    return true
end

local function addInfluence(source, operation)
    if GetResourceState('nexus_territories') ~= 'started' then return end
    if operation.zoneId then
        exports.nexus_territories:addInfluence(source, operation.zoneId, operation.influence or 1, 'operation_completed')
    elseif operation.dropoff then
        exports.nexus_territories:addInfluenceAtCoords(source, operation.dropoff, operation.influence or 1, 'operation_completed')
    end
end

local function rewardPlayer(source, player, reward)
    local cash = tonumber(reward.cash) or 0
    local xp = tonumber(reward.xp) or 0
    local reputation = tonumber(reward.reputation) or 0

    if cash > 0 then
        player.Functions.AddMoney('cash', cash, 'nexus-operation')
    end

    if GetResourceState('nexus_progression') == 'started' and (xp > 0 or reputation > 0) then
        local progressionOk = exports.nexus_progression:addProgression(player.PlayerData.citizenid, 'criminal', xp, reputation)
        if progressionOk then
            TriggerClientEvent('nexus_progression:client:tick', source, 'criminal', xp, reputation)
        else
            print(('[nexus_operations] WARNING: addProgression rechazado para citizenid=%s (criminal, xp=%s, rep=%s)'):format(player.PlayerData.citizenid, xp, reputation))
        end
    end

    return cash, xp, reputation
end

local function rewardStash(source, operation)
    local stashRewards = operation.rewards and operation.rewards.stash or {}
    if #stashRewards == 0 then return true end
    if GetResourceState('ox_inventory') ~= 'started' then return false, 'inventory' end
    if GetResourceState('nexus_gangs') ~= 'started' then return false, 'gangs' end

    local ok, stashId = pcall(function()
        return exports.nexus_gangs:getPrimaryStashId(source)
    end)
    if not ok or not stashId then return false, 'stash' end

    for i = 1, #stashRewards do
        local reward = stashRewards[i]
        if not exports.ox_inventory:AddItem(stashId, reward.item, reward.count or 1) then
            return false, reward.item
        end
    end

    return true
end

lib.callback.register('nexus_operations:server:getOperations', function(source)
    if not rateLimit(source) then return false, 'rate_limited' end

    if not activeOperations[source] and hasPackage(source) then
        clearPackage(source)
        notify(source, 'Se limpio un paquete huerfano de una operacion anterior.', 'inform')
    end

    return true, buildOperations(source), activeOperations[source]
end)

lib.callback.register('nexus_operations:server:prepareAction', function(source, requestedStage)
    if not rateLimit(source) then return false, 'rate_limited' end

    local active = activeOperations[source]
    local base = active and NexusOperationsConfig.operations[active.id]
    local operation = runtimeOperation(base, active)
    local stage = tostring(requestedStage or '')
    if not active or not operation or active.stage ~= stage or (stage ~= 'pickup' and stage ~= 'dropoff' and stage ~= 'extort') then
        return false, 'invalid_stage'
    end
    if os.time() > active.expiresAt then return false, 'expired' end

    local coords = stage == 'pickup' and operation.pickup or (stage == 'dropoff' and operation.dropoff or operation.point)
    if not coords or not isNear(source, coords, 5.0) then return false, 'too_far' end
    if stage == 'pickup' and hasAnyPackage(source) then return false, 'already_carrying' end
    if stage == 'pickup' and not exports.ox_inventory:CanCarryItem(source, packageItem(), 1) then return false, 'no_space' end
    if stage == 'dropoff' and not hasPackage(source, active.id) then return false, 'missing_package' end

    local durations = NexusOperationsConfig.actionDurations or {}
    local durationKey = stage == 'dropoff' and 'deliver' or stage
    local duration = tonumber(durations[durationKey]) or 6500
    local token, reason, normalizedDuration = beginPhysicalAction(source, stage, active.id, duration)
    if not token then return false, reason == 'busy' and 'physical_busy' or reason end

    local scenes = NexusOperationsConfig.sceneCore or {}
    local labels = {
        pickup = 'Recogiendo suministros...',
        dropoff = 'Entregando a safehouse...',
        extort = 'Ejecutando cobro...',
    }
    return true, {
        token = token,
        duration = normalizedDuration or duration,
        sceneId = scenes[stage] or (stage == 'extort' and 'extortion_collection' or (stage == 'pickup' and 'package_pickup' or 'package_delivery')),
        label = labels[stage],
        coords = { x = coords.x, y = coords.y, z = coords.z },
    }
end)

exports('getDashboardOperations', function(source)
    source = tonumber(source)
    if not source or source <= 0 then return { operations = {}, active = nil } end
    return {
        operations = buildOperations(source),
        active = activeOperations[source],
    }
end)

exports('getDashboardOperationsLite', function(source)
    source = tonumber(source)
    if not source or source <= 0 then return { operations = {}, active = nil } end
    return {
        operations = buildOperationsLite(source),
        active = activeOperations[source],
    }
end)

exports('getDashboardOperationLogs', function(source)
    source = tonumber(source)
    if not source or source <= 0 then return {} end

    local gang = getGang(source)
    if not gang or not gang.name or gang.name == 'none' then return {} end

    return NexusOperationsGetRecentLogs(gang.name, 8)
end)

RegisterNetEvent('nexus_operations:server:start', function(operationId)
    local src = source
    if not rateLimit(src) then return end
    if activeOperations[src] then return notify(src, 'Ya tienes una operacion activa.', 'error') end

    local operation = NexusOperationsConfig.operations[tostring(operationId or '')]
    if not operation then return notify(src, 'Operacion invalida.', 'error') end
    operation.id = tostring(operationId)

    local allowed, reason, gang, cooldown = canAccess(src, operation)
    if not allowed then
        local reasons = {
            no_gang = 'Necesitas pertenecer a una banda.',
            rank = 'Tu rango no permite iniciar esta operacion.',
            reputation = 'Necesitas mas reputacion criminal.',
            cooldown = ('Operacion en cooldown: %s min.'):format(math.ceil((cooldown or 0) / 60)),
        }
        return notify(src, reasons[reason] or 'No puedes iniciar esta operacion.', 'error')
    end

    if operation.type == 'supply' and hasAnyPackage(src) then
        return notify(src, 'Ya llevas un paquete pendiente.', 'error')
    end

    local route = chooseRoute(operation)
    local riskBonus, influenceBonus, zoneStatus = territorialModifiers(gang.name, operation)
    local policeAlertChance = math.max(0, math.min(95, (operation.policeAlertChance or 0) + (route.riskModifier or 0) + riskBonus))
    local influence = math.max(0, (operation.influence or 0) + (route.influenceModifier or 0) + influenceBonus)

    activeOperations[src] = {
        id = operation.id,
        type = operation.type,
        gangName = gang.name,
        stage = operation.type == 'supply' and 'pickup' or 'extort',
        expiresAt = os.time() + (operation.durationSeconds or 900),
        route = route,
        routeLabel = route and route.label or operation.label,
        policeAlertChance = policeAlertChance,
        influence = influence,
        zoneStatus = zoneStatus,
    }

    TriggerClientEvent('nexus_operations:client:setActive', src, activeOperations[src], runtimeOperation(operation, activeOperations[src]))
    notify(src, ('Operacion iniciada: %s | Ruta %s | Riesgo %s%%'):format(operation.label, activeOperations[src].routeLabel or 'base', policeAlertChance), 'success')
end)

RegisterNetEvent('nexus_operations:server:pickup', function(actionToken)
    local src = source
    if not rateLimit(src) then return end

    local active = activeOperations[src]
    local base = active and NexusOperationsConfig.operations[active.id]
    local operation = runtimeOperation(base, active)
    if not active or not operation or active.stage ~= 'pickup' then return end
    local actionOk, actionReason = consumePhysicalAction(src, 'pickup', active.id, actionToken)
    if not actionOk then
        print(('[nexus_operations] blocked pickup source=%s reason=%s'):format(src, tostring(actionReason)))
        return notify(src, 'La recogida fisica no es valida.', 'error')
    end
    if os.time() > active.expiresAt then
        NexusOperationsSetCooldown(active.gangName, active.id, NexusOperationsConfig.abandonCooldownSeconds or 300)
        activeOperations[src] = nil
        TriggerClientEvent('nexus_operations:client:clearActive', src)
        return notify(src, 'Operacion expirada.', 'error')
    end
    if not isNear(src, operation.pickup, 5.0) then return notify(src, 'No estas en el punto de recogida.', 'error') end
    if not givePackage(src, active.id) then return notify(src, 'No tienes espacio para el paquete.', 'error') end

    active.stage = 'dropoff'
    TriggerClientEvent('nexus_operations:client:setActive', src, active, operation)
    notify(src, 'Suministro recogido. Entrega marcada en GPS.', 'inform')
end)

local function completeOperation(src, active, operation)
    local player = getPlayer(src)
    if not player then return end

    local rewards = operation.rewards or {}
    local playerReward = rewards.player or {}
    local stashOk, stashReason = rewardStash(src, operation)
    if not stashOk then return notify(src, ('No se pudo depositar en stash: %s'):format(stashReason), 'error') end

    local cash, xp, reputation = rewardPlayer(src, player, playerReward)
    local policeAlert = alertPolice(operation, {
        source = src,
        gangName = active.gangName,
        message = ('Operacion completada: %s'):format(operation.label or active.id),
    })
    addInfluence(src, operation)
    NexusOperationsSetCooldown(active.gangName, active.id, operation.cooldownSeconds or 1800)
    NexusOperationsLog({
        gangName = active.gangName,
        citizenid = player.PlayerData.citizenid,
        playerName = GetPlayerName(src),
        operationId = active.id,
        status = 'completed',
        cash = cash,
        xp = xp,
        reputation = reputation,
        influence = operation.influence or 0,
        policeAlert = policeAlert,
    })

    activeOperations[src] = nil
    TriggerClientEvent('nexus_operations:client:clearActive', src)
    notify(src, ('Operacion completada: +$%s | +%s XP | +%s influencia'):format(cash, xp, operation.influence or 0), 'success')
end

RegisterNetEvent('nexus_operations:server:deliver', function(actionToken)
    local src = source
    if not rateLimit(src) then return end

    local active = activeOperations[src]
    local base = active and NexusOperationsConfig.operations[active.id]
    local operation = runtimeOperation(base, active)
    if not active or not operation or active.stage ~= 'dropoff' then return end
    local actionOk, actionReason = consumePhysicalAction(src, 'dropoff', active.id, actionToken)
    if not actionOk then
        print(('[nexus_operations] blocked delivery source=%s reason=%s'):format(src, tostring(actionReason)))
        return notify(src, 'La entrega fisica no es valida.', 'error')
    end
    if os.time() > active.expiresAt then
        NexusOperationsSetCooldown(active.gangName, active.id, NexusOperationsConfig.abandonCooldownSeconds or 300)
        clearPackage(src, active.id)
        activeOperations[src] = nil
        TriggerClientEvent('nexus_operations:client:clearActive', src)
        return notify(src, 'Operacion expirada.', 'error')
    end
    if not isNear(src, operation.dropoff, 5.0) then return notify(src, 'No estas en el punto de entrega.', 'error') end
    if not hasPackage(src, active.id) then return notify(src, 'No llevas el paquete de suministros.', 'error') end

    if not removePackage(src, active.id) then return notify(src, 'No se pudo entregar el paquete.', 'error') end
    completeOperation(src, active, operation)
end)

RegisterNetEvent('nexus_operations:server:extort', function(actionToken)
    local src = source
    if not rateLimit(src) then return end

    local active = activeOperations[src]
    local base = active and NexusOperationsConfig.operations[active.id]
    local operation = runtimeOperation(base, active)
    if not active or not operation or active.stage ~= 'extort' then return end
    local actionOk, actionReason = consumePhysicalAction(src, 'extort', active.id, actionToken)
    if not actionOk then
        print(('[nexus_operations] blocked extortion source=%s reason=%s'):format(src, tostring(actionReason)))
        return notify(src, 'El cobro fisico no es valido.', 'error')
    end
    if os.time() > active.expiresAt then
        NexusOperationsSetCooldown(active.gangName, active.id, NexusOperationsConfig.abandonCooldownSeconds or 300)
        activeOperations[src] = nil
        TriggerClientEvent('nexus_operations:client:clearActive', src)
        return notify(src, 'Operacion expirada.', 'error')
    end
    if not isNear(src, operation.point, 5.0) then return notify(src, 'No estas en el punto de extorsion.', 'error') end

    completeOperation(src, active, operation)
end)

RegisterNetEvent('nexus_operations:server:cancelPreparedAction', function(actionToken)
    cancelPhysicalAction(source, actionToken)
end)

RegisterNetEvent('nexus_operations:server:cancel', function()
    local src = source
    local active = activeOperations[src]
    if not active then return end

    NexusOperationsSetCooldown(active.gangName, active.id, NexusOperationsConfig.abandonCooldownSeconds or 300)
    clearPackage(src, active.id)
    cancelPhysicalAction(src)
    activeOperations[src] = nil
    TriggerClientEvent('nexus_operations:client:clearActive', src)
    notify(src, 'Operacion cancelada.', 'inform')
end)

AddEventHandler('playerDropped', function()
    local active = activeOperations[source]
    clearPackage(source, active and active.id or nil)
    cancelPhysicalAction(source)
    activeOperations[source] = nil
end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    math.randomseed(os.time())
    print('[nexus_operations] operaciones de banda cargadas')
end)
