local activeLabs = {}
local activeByPlayer = {}

local function beginLabAction(source, labId, action)
    if activeLabs[labId] then return false, 'lab_busy' end
    if activeByPlayer[source] then return false, 'player_busy' end

    activeLabs[labId] = source
    activeByPlayer[source] = { labId = labId, action = action }
    return true
end

local function isLabActionActive(source, labId, action)
    local playerAction = activeByPlayer[source]
    return activeLabs[labId] == source
        and playerAction ~= nil
        and playerAction.labId == labId
        and playerAction.action == action
end

local function finishLabAction(source, labId, action)
    if not isLabActionActive(source, labId, action) then return false end

    activeLabs[labId] = nil
    activeByPlayer[source] = nil
    return true
end

local function abortLabAction(source, labId)
    if activeLabs[labId] == source then activeLabs[labId] = nil end
    local playerAction = activeByPlayer[source]
    if playerAction and playerAction.labId == labId then activeByPlayer[source] = nil end
end

local function notify(source, description, notifyType)
    TriggerClientEvent('ox_lib:notify', source, {
        title = 'Laboratorios',
        description = description,
        type = notifyType or 'inform',
    })
end

local function rateLimit(source)
    source = tonumber(source)
    if not source or source <= 0 then return false end
    if GetResourceState('nexus_bridge') ~= 'started' then return true end
    return exports.nexus_bridge:rateLimit(source, NexusLabsConfig.rateLimitBucket or 'labs')
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

-- canUseLab bypasseaba 4 requisitos distintos con un solo booleano --
-- separados en progression_bypass (rango + reputacion) y territory_bypass
-- (zona rival + influencia). sabotage_bypass es un tercero, independiente
-- (el sabotaje tiene su propio requisito de rango, que NUNCA tiene bypass
-- admin -- ver el RegisterNetEvent nexus_labs:server:sabotage).
local function hasProgressionBypass(source)
    source = tonumber(source)
    if source == 0 then return true end
    if GetResourceState('nexus_permissions') ~= 'started' then return false end
    return exports.nexus_permissions:hasPermission(source, 'nexus_labs.progression_bypass')
end

local function hasTerritoryBypass(source)
    source = tonumber(source)
    if source == 0 then return true end
    if GetResourceState('nexus_permissions') ~= 'started' then return false end
    return exports.nexus_permissions:hasPermission(source, 'nexus_labs.territory_bypass')
end

local function hasSabotageBypass(source)
    source = tonumber(source)
    if source == 0 then return true end
    if GetResourceState('nexus_permissions') ~= 'started' then return false end
    return exports.nexus_permissions:hasPermission(source, 'nexus_labs.sabotage_bypass')
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

local function publicVec4(coords)
    return coords and { x = coords.x, y = coords.y, z = coords.z, w = coords.w } or nil
end

local function getSceneId(action, lab)
    local sceneConfig = NexusLabsConfig.sceneCore or {}
    local scene = sceneConfig.actions and sceneConfig.actions[action]
    if type(scene) == 'table' then
        return scene[lab.type] or scene.default or 'lab_processing'
    end
    return scene or 'lab_processing'
end

local function startClientScene(source, labId, action, duration, label, lab)
    TriggerClientEvent('nexus_labs:client:startScene', source, {
        labId = labId,
        action = action,
        sceneId = getSceneId(action, lab),
        duration = duration,
        label = label,
        coords = publicVec4(lab.coords),
    })
end

local function isNear(source, coords, distance)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return false end
    return #(GetEntityCoords(ped) - vector3(coords.x, coords.y, coords.z)) <= (distance or NexusLabsConfig.interactDistance or 3.0)
end

local function getZoneState(zoneId)
    if GetResourceState('nexus_territories') ~= 'started' then return nil end

    local ok, state = pcall(function()
        return exports.nexus_territories:getZoneState(zoneId)
    end)

    return ok and state or nil
end

local function canUseLab(source, lab, options)
    options = options or {}
    local gang = getGang(source)
    if not gang or not gang.name or gang.name == 'none' then return false, 'no_gang', gang end

    local progressionBypass = hasProgressionBypass(source)
    if not progressionBypass and (tonumber(gang.rank) or 0) < (lab.requiredRank or 0) then return false, 'rank', gang end

    local criminal = (getProgress(source).criminal or {})
    if not progressionBypass and (tonumber(criminal.reputation) or 0) < (lab.minCriminalReputation or 0) then
        return false, 'reputation', gang
    end

    local territoryBypass = hasTerritoryBypass(source)
    local zone = getZoneState(lab.zoneId)
    local production = NexusLabsConfig.production or {}
    if not territoryBypass and production.allowOwnerOnly and zone and zone.status == 'controlled' and zone.owner and zone.owner ~= gang.name then
        return false, 'rival_zone', gang, zone
    end

    if not territoryBypass and zone and zone.owner ~= gang.name then
        local ownInfluence = 0
        for i = 1, #(zone.influence or {}) do
            local entry = zone.influence[i]
            if entry.gang == gang.name then ownInfluence = tonumber(entry.influence) or 0 break end
        end
        if ownInfluence < (production.minimumInfluence or 15) then
            return false, ('influence:%s/%s:%s'):format(ownInfluence, production.minimumInfluence or 15, lab.zoneId), gang, zone
        end
    end

    local cooldown = NexusLabsGetCooldown(gang.name, lab.id)
    if not options.ignoreCooldown and cooldown > 0 then return false, 'cooldown', gang, zone, cooldown end
    return true, nil, gang, zone
end

local function effectiveRisk(lab, gang, zone)
    local risk = tonumber(lab.baseRisk) or 0
    if zone and zone.status == 'controlled' and zone.owner == gang.name then risk = risk - 6 end
    if zone and zone.status == 'contested' then risk = risk + 8 end
    if zone and zone.status == 'controlled' and zone.owner and zone.owner ~= gang.name then risk = risk + 16 end
    risk = math.floor(risk * (tonumber(zone and zone.heatMultiplier) or 1.0))
    return math.max(0, math.min(95, risk))
end

local function getLabState(gang, labId)
    local gangName = gang and gang.name or 'none'
    return NexusLabsGetState(gangName, labId)
end

local function getUpgradeCost(state)
    local upgrades = NexusLabsConfig.upgrades or {}
    if not upgrades.enabled then return nil end
    local nextLevel = (tonumber(state and state.level) or 1) + 1
    if nextLevel > (upgrades.maxLevel or 3) then return nil end
    local cost = upgrades.levels and upgrades.levels[nextLevel]
    if not cost then return nil end
    return {
        nextLevel = nextLevel,
        cash = cost.cash or 0,
        materials = cost.materials or {},
    }
end

local function getProductionMeta(lab, state, baseRisk)
    local upgrades = NexusLabsConfig.upgrades or {}
    local level = math.max(1, tonumber(state and state.level) or 1)
    local condition = math.max(0, math.min(100, tonumber(state and state.condition) or 100))
    local levelBonus = math.max(0, level - 1)
    local duration = NexusLabsConfig.production.durationMs or 12000
    local durationReduction = (tonumber(upgrades.durationReductionPerLevel) or 0) * levelBonus
    local conditionPenalty = condition < 50 and 0.20 or 0.0
    local risk = math.max(0, (tonumber(baseRisk) or 0) - ((tonumber(upgrades.riskReductionPerLevel) or 0) * levelBonus))
    local outputMultiplier = 1.0 + ((tonumber(upgrades.outputBonusPerLevel) or 0) * levelBonus)

    return {
        level = level,
        condition = condition,
        durationMs = math.floor(duration * math.max(0.45, 1.0 - durationReduction + conditionPenalty)),
        risk = math.floor(math.max(0, math.min(95, risk))),
        outputMultiplier = outputMultiplier,
        conditionPenalty = conditionPenalty,
    }
end

local function scaleOutputs(outputs, multiplier)
    local scaled = {}
    for i = 1, #(outputs or {}) do
        local output = outputs[i]
        scaled[#scaled + 1] = {
            item = output.item,
            count = math.max(1, math.floor((output.count or 1) * (multiplier or 1.0))),
        }
    end
    return scaled
end

local function buildLabs(source)
    local labs = {}
    for labId, lab in pairs(NexusLabsConfig.labs or {}) do
        lab.id = labId
        local unlocked, reason, gang, zone, cooldown = canUseLab(source, lab)
        local state = gang and getLabState(gang, labId) or { level = 1, condition = 100, queueRemaining = 0 }
        local baseRisk = gang and effectiveRisk(lab, gang, zone) or lab.baseRisk or 0
        local productionMeta = getProductionMeta(lab, state, baseRisk)
        local upgradeCost = getUpgradeCost(state)
        local maintenance = NexusLabsConfig.maintenance or {}
        local sabotage = NexusLabsConfig.sabotage or {}
        local canSabotage = gang and gang.name ~= 'none' and zone and zone.owner and zone.owner ~= 'none' and zone.owner ~= gang.name
        labs[#labs + 1] = {
            id = labId,
            label = lab.label,
            type = lab.type,
            zoneId = lab.zoneId,
            zoneLabel = zone and zone.label or lab.zoneId,
            zoneOwner = zone and zone.owner or nil,
            zoneStatus = zone and zone.status or 'unknown',
            coords = publicVec4(lab.coords),
            requiredRank = lab.requiredRank or 0,
            minCriminalReputation = lab.minCriminalReputation or 0,
            recipe = lab.recipe,
            risk = productionMeta.risk,
            influenceReward = lab.influenceReward or 0,
            unlocked = unlocked,
            lockedReason = reason,
            cooldownRemaining = cooldown or (gang and gang.name ~= 'none' and NexusLabsGetCooldown(gang.name, labId) or 0),
            queueRemaining = state.queueRemaining or 0,
            level = productionMeta.level,
            condition = productionMeta.condition,
            durationMs = productionMeta.durationMs,
            outputMultiplier = productionMeta.outputMultiplier,
            upgradeCost = upgradeCost,
            repairCost = maintenance.enabled and {
                repairAmount = maintenance.repairAmount or 35,
                cash = maintenance.cash or 0,
                materials = maintenance.materials or {},
            } or nil,
            sabotage = sabotage.enabled and {
                canSabotage = canSabotage == true,
                targetGang = canSabotage and zone.owner or nil,
                damage = sabotage.damage or 35,
                risk = sabotage.policeAlertChance or 35,
                influenceReward = sabotage.influenceReward or 8,
                materials = sabotage.materials or {},
            } or nil,
            active = activeLabs[labId] ~= nil,
        }
    end

    table.sort(labs, function(a, b)
        return a.minCriminalReputation < b.minCriminalReputation
    end)

    return labs
end

local function sendDispatchAlert(lab, risk, context)
    if GetResourceState('nexus_dispatch') ~= 'started' then return end

    context = context or {}
    pcall(function()
        exports.nexus_dispatch:createAlert({
            type = context.type or 'lab',
            title = context.title or 'Laboratorio ilegal',
            message = context.message or (lab.label or 'Actividad de laboratorio'),
            coords = lab.coords,
            zoneId = lab.zoneId,
            sourceResource = GetCurrentResourceName(),
            sourcePlayer = context.source,
            gangName = context.gangName,
            risk = risk,
            priority = context.priority or 3,
        })
    end)
end

local function alertPolice(lab, risk, context)
    if math.random(100) > risk then return false end
    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        local player = getPlayer(src)
        local job = player and player.PlayerData and player.PlayerData.job
        if job and NexusLabsConfig.policeJobs[job.name] then
            TriggerClientEvent('nexus_labs:client:policeAlert', src, {
                label = lab.label,
                coords = lab.coords,
            })
        end
    end
    sendDispatchAlert(lab, risk, context)
    return true
end

local function hasInputs(source, inputs)
    if GetResourceState('ox_inventory') ~= 'started' then return false, 'inventory' end
    for i = 1, #inputs do
        local input = inputs[i]
        if (exports.ox_inventory:GetItemCount(source, input.item) or 0) < (input.count or 1) then
            return false, input.item
        end
    end
    return true
end

local function consumeInputs(source, inputs)
    for i = 1, #inputs do
        local input = inputs[i]
        if not exports.ox_inventory:RemoveItem(source, input.item, input.count or 1) then return false, input.item end
    end
    return true
end

local function canPayUpgrade(source, cost)
    if not cost then return false, 'max_level' end
    if GetResourceState('ox_inventory') ~= 'started' then return false, 'inventory' end

    local player = getPlayer(source)
    local cash = player and player.PlayerData and player.PlayerData.money and player.PlayerData.money.cash or 0
    if cash < (cost.cash or 0) then return false, 'cash' end

    for i = 1, #(cost.materials or {}) do
        local item = cost.materials[i]
        if (exports.ox_inventory:GetItemCount(source, item.item) or 0) < (item.count or 1) then
            return false, item.item
        end
    end

    return true
end

local function payUpgrade(source, cost)
    local player = getPlayer(source)
    if not player then return false, 'player' end
    if (cost.cash or 0) > 0 and not player.Functions.RemoveMoney('cash', cost.cash, 'nexus-lab-upgrade') then
        return false, 'cash'
    end

    for i = 1, #(cost.materials or {}) do
        local item = cost.materials[i]
        if not exports.ox_inventory:RemoveItem(source, item.item, item.count or 1) then
            return false, item.item
        end
    end

    return true
end

local function canPayCost(source, cost)
    if GetResourceState('ox_inventory') ~= 'started' then return false, 'inventory' end

    local player = getPlayer(source)
    local cash = player and player.PlayerData and player.PlayerData.money and player.PlayerData.money.cash or 0
    if cash < (cost.cash or 0) then return false, 'cash' end

    for i = 1, #(cost.materials or {}) do
        local item = cost.materials[i]
        if (exports.ox_inventory:GetItemCount(source, item.item) or 0) < (item.count or 1) then
            return false, item.item
        end
    end

    return true
end

local function payCost(source, cost, reason)
    local player = getPlayer(source)
    if not player then return false, 'player' end

    if (cost.cash or 0) > 0 and not player.Functions.RemoveMoney('cash', cost.cash, reason or 'nexus-lab-cost') then
        return false, 'cash'
    end

    for i = 1, #(cost.materials or {}) do
        local item = cost.materials[i]
        if not exports.ox_inventory:RemoveItem(source, item.item, item.count or 1) then
            return false, item.item
        end
    end

    return true
end

local function addOutputs(source, outputs)
    if GetResourceState('ox_inventory') ~= 'started' then return false, 'inventory_offline' end

    local summary = {}
    for i = 1, #outputs do
        local output = outputs[i]
        summary[#summary + 1] = ('%sx %s'):format(output.count or 1, output.item)
    end

    local production = NexusLabsConfig.production or {}
    if production.depositToGangStash and GetResourceState('nexus_gangs') == 'started' then
        local ok, stashId = pcall(function()
            return exports.nexus_gangs:getPrimaryStashId(source)
        end)
        if ok and stashId then
            local stashOk = true
            local failedItem = nil
            for i = 1, #outputs do
                local output = outputs[i]
                if not exports.ox_inventory:AddItem(stashId, output.item, output.count or 1) then
                    stashOk = false
                    failedItem = output.item
                    break
                end
            end

            if stashOk then
                return true, 'stash', table.concat(summary, ', ')
            end

            print(('[nexus_labs] stash output failed %s -> %s, falling back to player inventory'):format(stashId, failedItem or 'unknown'))
            for i = 1, #outputs do
                local output = outputs[i]
                exports.ox_inventory:RemoveItem(stashId, output.item, output.count or 1)
            end
        end
    end

    for i = 1, #outputs do
        local output = outputs[i]
        if not exports.ox_inventory:CanCarryItem(source, output.item, output.count or 1) then return false, output.item end
    end
    for i = 1, #outputs do
        local output = outputs[i]
        exports.ox_inventory:AddItem(source, output.item, output.count or 1)
    end
    return true, 'player', table.concat(summary, ', ')
end

lib.callback.register('nexus_labs:server:getLabs', function(source)
    if not rateLimit(source) then return false, 'rate_limited' end
    return true, buildLabs(source)
end)

exports('getDashboardLabs', function(source)
    source = tonumber(source)
    if not source or source <= 0 then return { labs = {}, logs = {} } end
    local gang = getGang(source)
    return {
        labs = buildLabs(source),
        logs = gang and NexusLabsGetRecentLogs(gang.name, 8) or {},
    }
end)

RegisterNetEvent('nexus_labs:server:produce', function(labId)
    local src = source
    if not rateLimit(src) then return end

    labId = tostring(labId or '')
    local lab = NexusLabsConfig.labs[labId]
    if not lab then return notify(src, 'Laboratorio invalido.', 'error') end
    lab.id = labId
    if activeLabs[labId] then return notify(src, 'Este laboratorio ya tiene una accion activa.', 'error') end
    if activeByPlayer[src] then return notify(src, 'Ya estas trabajando en otro laboratorio.', 'error') end
    if not isNear(src, lab.coords, (NexusLabsConfig.interactDistance or 3.0) + 1.5) then return notify(src, 'Estas demasiado lejos del laboratorio.', 'error') end

    local allowed, reason, gang, zone, cooldown = canUseLab(src, lab)
    if not allowed then
        local reasons = {
            no_gang = 'Necesitas pertenecer a una banda.',
            rank = 'Tu rango no permite usar este laboratorio.',
            reputation = 'Necesitas mas reputacion criminal.',
            rival_zone = 'Este laboratorio esta bajo control rival.',
            cooldown = ('Laboratorio en cooldown: %s min.'):format(math.ceil((cooldown or 0) / 60)),
        }

        if type(reason) == 'string' and reason:find('^influence:') then
            local detail = reason:gsub('^influence:', '')
            return notify(src, ('Tu banda necesita mas influencia en esta zona. Actual/requerida/zona: %s'):format(detail), 'error')
        end

        return notify(src, reasons[reason] or ('No puedes usar este laboratorio: %s'):format(reason or 'desconocido'), 'error')
    end

    local state = getLabState(gang, labId)
    if (state.queueRemaining or 0) > 0 then
        return notify(src, ('Cola activa: %s min.'):format(math.ceil((state.queueRemaining or 0) / 60)), 'error')
    end

    local recipe = lab.recipe or {}
    local ok, missing = hasInputs(src, recipe.inputs or {})
    if not ok then return notify(src, ('Falta material: %s'):format(missing), 'error') end
    local started, startReason = beginLabAction(src, labId, 'production')
    if not started then return notify(src, startReason == 'player_busy' and 'Ya estas trabajando en otro laboratorio.' or 'Laboratorio ocupado.', 'error') end
    ok, missing = consumeInputs(src, recipe.inputs or {})
    if not ok then
        abortLabAction(src, labId)
        return notify(src, ('No se pudo consumir: %s'):format(missing), 'error')
    end

    local baseRisk = effectiveRisk(lab, gang, zone)
    local productionMeta = getProductionMeta(lab, state, baseRisk)
    NexusLabsSetQueue(gang.name, labId, math.ceil(productionMeta.durationMs / 1000))
    startClientScene(src, labId, 'production', productionMeta.durationMs, ('Procesando %s...'):format(recipe.label or lab.label), lab)

    SetTimeout(productionMeta.durationMs, function()
        if not isLabActionActive(src, labId, 'production') then return end
        NexusLabsClearQueue(gang.name, labId)

        if not getPlayer(src) or not isNear(src, lab.coords, (NexusLabsConfig.interactDistance or 3.0) + 2.0) then
            finishLabAction(src, labId, 'production')
            return notify(src, 'Produccion interrumpida: abandonaste el laboratorio.', 'error')
        end

        local scaledOutputs = scaleOutputs(recipe.outputs or {}, productionMeta.outputMultiplier)
        local outputOk, target, summary = addOutputs(src, scaledOutputs)
        if not outputOk then
            finishLabAction(src, labId, 'production')
            return notify(src, ('Produccion perdida, sin espacio: %s'):format(target), 'error')
        end

        local player = getPlayer(src)
        local xp = recipe.xp or 0
        local reputation = recipe.reputation or 0
        if player and GetResourceState('nexus_progression') == 'started' then
            local progressionOk = exports.nexus_progression:addProgression(player.PlayerData.citizenid, 'criminal', xp, reputation)
            if progressionOk then
                TriggerClientEvent('nexus_progression:client:tick', src, 'criminal', xp, reputation)
            else
                print(('[nexus_labs] WARNING: addProgression rechazado para citizenid=%s (criminal, xp=%s, rep=%s)'):format(player.PlayerData.citizenid, xp, reputation))
            end
        end

        if GetResourceState('nexus_territories') == 'started' then
            exports.nexus_territories:addInfluence(src, lab.zoneId, lab.influenceReward or 0, 'lab_production')
        end

        local risk = productionMeta.risk
        local policeAlert = alertPolice(lab, risk, {
            source = src,
            gangName = gang.name,
            type = 'lab',
            title = 'Produccion ilegal',
            message = ('Actividad en %s'):format(lab.label or labId),
        })
        NexusLabsApplyWear(gang.name, labId, NexusLabsConfig.upgrades.conditionDecayPerRun or 8)
        NexusLabsSetCooldown(gang.name, labId, NexusLabsConfig.production.cooldownSeconds or 900)
        NexusLabsLog({
            labId = labId,
            zoneId = lab.zoneId,
            gangName = gang.name,
            citizenid = getCitizenId(src),
            playerName = GetPlayerName(src),
            status = 'completed',
            risk = risk,
            xp = xp,
            reputation = reputation,
            influence = lab.influenceReward or 0,
            policeAlert = policeAlert,
        })

        finishLabAction(src, labId, 'production')
        notify(src, ('Produccion completada: %s -> %s (%s)'):format(recipe.label or lab.label, target == 'stash' and 'stash de banda' or 'inventario', summary or 'sin resumen'), 'success')
    end)
end)

RegisterNetEvent('nexus_labs:server:upgrade', function(labId)
    local src = source
    if not rateLimit(src) then return end

    labId = tostring(labId or '')
    local lab = NexusLabsConfig.labs[labId]
    if not lab then return notify(src, 'Laboratorio invalido.', 'error') end
    lab.id = labId
    if not isNear(src, lab.coords, (NexusLabsConfig.interactDistance or 3.0) + 1.5) then return notify(src, 'Estas demasiado lejos del laboratorio.', 'error') end

    local allowed, reason, gang = canUseLab(src, lab, { ignoreCooldown = true })
    if not allowed then return notify(src, ('No puedes mejorar este laboratorio: %s'):format(reason or 'bloqueado'), 'error') end

    local state = getLabState(gang, labId)
    if (state.queueRemaining or 0) > 0 or activeLabs[labId] then
        return notify(src, 'No puedes mejorar mientras hay produccion activa.', 'error')
    end
    if activeByPlayer[src] then return notify(src, 'Ya estas trabajando en otro laboratorio.', 'error') end

    local cost = getUpgradeCost(state)
    local ok, missing = canPayUpgrade(src, cost)
    if not ok then return notify(src, ('Falta requisito de mejora: %s'):format(missing), 'error') end

    local started, startReason = beginLabAction(src, labId, 'upgrade')
    if not started then return notify(src, startReason == 'player_busy' and 'Ya estas trabajando en otro laboratorio.' or 'Laboratorio ocupado.', 'error') end
    ok, missing = payUpgrade(src, cost)
    if not ok then
        abortLabAction(src, labId)
        return notify(src, ('No se pudo pagar mejora: %s'):format(missing), 'error')
    end

    local duration = math.max(1000, tonumber((NexusLabsConfig.upgrades or {}).durationMs) or 10000)
    startClientScene(src, labId, 'upgrade', duration, ('Mejorando %s...'):format(lab.label), lab)
    SetTimeout(duration, function()
        if not isLabActionActive(src, labId, 'upgrade') then return end
        if not getPlayer(src) or not isNear(src, lab.coords, (NexusLabsConfig.interactDistance or 3.0) + 2.0) then
            finishLabAction(src, labId, 'upgrade')
            return notify(src, 'Mejora interrumpida: abandonaste el laboratorio.', 'error')
        end

        NexusLabsUpgrade(gang.name, labId, cost.nextLevel)
        NexusLabsLog({
            labId = labId,
            zoneId = lab.zoneId,
            gangName = gang.name,
            citizenid = getCitizenId(src),
            playerName = GetPlayerName(src),
            status = ('upgraded_%s'):format(cost.nextLevel),
            risk = 0,
            xp = 0,
            reputation = 0,
            influence = 0,
            policeAlert = false,
        })

        finishLabAction(src, labId, 'upgrade')
        notify(src, ('Laboratorio mejorado a nivel %s.'):format(cost.nextLevel), 'success')
    end)
end)

RegisterNetEvent('nexus_labs:server:repair', function(labId)
    local src = source
    if not rateLimit(src) then return end

    labId = tostring(labId or '')
    local lab = NexusLabsConfig.labs[labId]
    if not lab then return notify(src, 'Laboratorio invalido.', 'error') end
    lab.id = labId
    if not isNear(src, lab.coords, (NexusLabsConfig.interactDistance or 3.0) + 1.5) then return notify(src, 'Estas demasiado lejos del laboratorio.', 'error') end

    local allowed, reason, gang = canUseLab(src, lab, { ignoreCooldown = true })
    if not allowed then return notify(src, ('No puedes reparar este laboratorio: %s'):format(reason or 'bloqueado'), 'error') end

    local state = getLabState(gang, labId)
    if (state.queueRemaining or 0) > 0 or activeLabs[labId] then
        return notify(src, 'No puedes reparar mientras hay produccion activa.', 'error')
    end
    if activeByPlayer[src] then return notify(src, 'Ya estas trabajando en otro laboratorio.', 'error') end
    if (state.condition or 100) >= 100 then return notify(src, 'El laboratorio ya esta en condicion maxima.', 'inform') end

    local maintenance = NexusLabsConfig.maintenance or {}
    if not maintenance.enabled then return notify(src, 'Mantenimiento deshabilitado.', 'error') end

    local cost = { cash = maintenance.cash or 0, materials = maintenance.materials or {} }
    local ok, missing = canPayCost(src, cost)
    if not ok then return notify(src, ('Falta requisito de reparacion: %s'):format(missing), 'error') end

    local started, startReason = beginLabAction(src, labId, 'repair')
    if not started then return notify(src, startReason == 'player_busy' and 'Ya estas trabajando en otro laboratorio.' or 'Laboratorio ocupado.', 'error') end
    ok, missing = payCost(src, cost, 'nexus-lab-repair')
    if not ok then
        abortLabAction(src, labId)
        return notify(src, ('No se pudo pagar reparacion: %s'):format(missing), 'error')
    end

    local duration = math.max(1000, tonumber(maintenance.durationMs) or 7000)
    startClientScene(src, labId, 'repair', duration, ('Reparando %s...'):format(lab.label), lab)
    SetTimeout(duration, function()
        if not isLabActionActive(src, labId, 'repair') then return end
        if not getPlayer(src) or not isNear(src, lab.coords, (NexusLabsConfig.interactDistance or 3.0) + 2.0) then
            finishLabAction(src, labId, 'repair')
            return notify(src, 'Reparacion interrumpida: abandonaste el laboratorio.', 'error')
        end

        NexusLabsRepairCondition(gang.name, labId, maintenance.repairAmount or 35)
        NexusLabsLog({
            labId = labId,
            zoneId = lab.zoneId,
            gangName = gang.name,
            citizenid = getCitizenId(src),
            playerName = GetPlayerName(src),
            status = 'repaired',
            risk = 0,
            xp = 0,
            reputation = 0,
            influence = 0,
            policeAlert = false,
        })

        finishLabAction(src, labId, 'repair')
        notify(src, ('Laboratorio reparado +%s%% condicion.'):format(maintenance.repairAmount or 35), 'success')
    end)
end)

RegisterNetEvent('nexus_labs:server:sabotage', function(labId)
    local src = source
    if not rateLimit(src) then return end

    labId = tostring(labId or '')
    local lab = NexusLabsConfig.labs[labId]
    if not lab then return notify(src, 'Laboratorio invalido.', 'error') end
    lab.id = labId
    if activeLabs[labId] then return notify(src, 'No puedes sabotear durante produccion activa.', 'error') end
    if activeByPlayer[src] then return notify(src, 'Ya estas trabajando en otro laboratorio.', 'error') end
    if not isNear(src, lab.coords, (NexusLabsConfig.interactDistance or 3.0) + 1.5) then return notify(src, 'Estas demasiado lejos del laboratorio.', 'error') end

    local sabotage = NexusLabsConfig.sabotage or {}
    if not sabotage.enabled then return notify(src, 'Sabotaje deshabilitado.', 'error') end

    local gang = getGang(src)
    if not gang or not gang.name or gang.name == 'none' then return notify(src, 'Necesitas pertenecer a una banda.', 'error') end
    if (tonumber(gang.rank) or 0) < (sabotage.requiredRank or 1) then return notify(src, 'Tu rango no permite sabotear.', 'error') end

    local criminal = (getProgress(src).criminal or {})
    if not hasSabotageBypass(src) and (tonumber(criminal.reputation) or 0) < (sabotage.minCriminalReputation or 3) then
        return notify(src, 'Necesitas mas reputacion criminal para sabotear.', 'error')
    end

    local zone = getZoneState(lab.zoneId)
    local targetGang = zone and zone.owner or nil
    if not targetGang or targetGang == 'none' or targetGang == gang.name then
        return notify(src, 'No hay control rival que sabotear en esta zona.', 'error')
    end

    local targetState = NexusLabsGetState(targetGang, labId)
    if (targetState.queueRemaining or 0) > 0 then return notify(src, 'El laboratorio rival esta en cola activa.', 'error') end

    local cost = { cash = 0, materials = sabotage.materials or {} }
    local ok, missing = canPayCost(src, cost)
    if not ok then return notify(src, ('Falta material de sabotaje: %s'):format(missing), 'error') end
    local started, startReason = beginLabAction(src, labId, 'sabotage')
    if not started then return notify(src, startReason == 'player_busy' and 'Ya estas trabajando en otro laboratorio.' or 'Laboratorio ocupado.', 'error') end
    ok, missing = payCost(src, cost, 'nexus-lab-sabotage')
    if not ok then
        abortLabAction(src, labId)
        return notify(src, ('No se pudo consumir sabotaje: %s'):format(missing), 'error')
    end

    startClientScene(src, labId, 'sabotage', sabotage.durationMs or 9000, 'Saboteando laboratorio...', lab)

    SetTimeout(sabotage.durationMs or 9000, function()
        if not isLabActionActive(src, labId, 'sabotage') then return end
        if not getPlayer(src) or not isNear(src, lab.coords, (NexusLabsConfig.interactDistance or 3.0) + 2.0) then
            finishLabAction(src, labId, 'sabotage')
            return notify(src, 'Sabotaje interrumpido: abandonaste el laboratorio.', 'error')
        end

        NexusLabsDamageCondition(targetGang, labId, sabotage.damage or 35)
        if GetResourceState('nexus_territories') == 'started' then
            exports.nexus_territories:addInfluence(src, lab.zoneId, sabotage.influenceReward or 8, 'lab_sabotage')
        end

        local risk = sabotage.policeAlertChance or 35
        local policeAlert = alertPolice(lab, risk, {
            source = src,
            gangName = gang.name,
            type = 'sabotage',
            title = 'Sabotaje de laboratorio',
            message = ('Sabotaje detectado en %s'):format(lab.label or labId),
        })
        NexusLabsLog({
            labId = labId,
            zoneId = lab.zoneId,
            gangName = gang.name,
            citizenid = getCitizenId(src),
            playerName = GetPlayerName(src),
            status = ('sabotaged_%s'):format(targetGang),
            risk = risk,
            xp = 0,
            reputation = 0,
            influence = sabotage.influenceReward or 8,
            policeAlert = policeAlert,
        })
        NexusLabsLog({
            labId = labId,
            zoneId = lab.zoneId,
            gangName = targetGang,
            citizenid = getCitizenId(src),
            playerName = GetPlayerName(src),
            status = ('sabotaged_by_%s'):format(gang.name),
            risk = risk,
            xp = 0,
            reputation = 0,
            influence = 0,
            policeAlert = policeAlert,
        })

        finishLabAction(src, labId, 'sabotage')
        notify(src, ('Sabotaje completado contra %s.'):format(targetGang), 'success')
    end)
end)

AddEventHandler('playerDropped', function()
    local src = source
    for labId, owner in pairs(activeLabs) do
        if owner == src then activeLabs[labId] = nil end
    end
    activeByPlayer[src] = nil
end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    math.randomseed(os.time())
    print('[nexus_labs] laboratorios ilegales cargados')
end)
