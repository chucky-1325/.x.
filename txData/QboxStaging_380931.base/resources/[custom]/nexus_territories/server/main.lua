local influence = {}
local dynamicZones = {}
local activeAirdrop = nil
local lastAirdropAt = 0

local function notify(source, description, notifyType)
    TriggerClientEvent('ox_lib:notify', source, {
        title = 'Territorios',
        description = description,
        type = notifyType or 'inform',
    })
end

local function rateLimit(source)
    if GetResourceState('nexus_bridge') ~= 'started' then return true end
    return exports.nexus_bridge:rateLimit(source, NexusTerritoriesConfig.rateLimitBucket or 'default')
end

local function getPlayer(source)
    if GetResourceState('qbx_core') ~= 'started' then return nil end
    return exports.qbx_core:GetPlayer(source)
end

local function getCitizenId(source)
    local player = getPlayer(source)
    return player and player.PlayerData and player.PlayerData.citizenid or nil
end

local function getPedCoords(source)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

local function hasEditorViewBypass(source)
    source = tonumber(source)
    if not source then return false end
    if source == 0 then return true end
    if GetResourceState('nexus_permissions') ~= 'started' then return false end
    return exports.nexus_permissions:hasPermission(source, 'nexus_territories.editor_view')
end

local function hasZoneSaveBypass(source)
    source = tonumber(source)
    if not source then return false end
    if source == 0 then return true end
    if GetResourceState('nexus_permissions') ~= 'started' then return false end
    return exports.nexus_permissions:hasPermission(source, 'nexus_territories.zone_save')
end

local function hasZoneDeleteBypass(source)
    source = tonumber(source)
    if not source then return false end
    if source == 0 then return true end
    if GetResourceState('nexus_permissions') ~= 'started' then return false end
    return exports.nexus_permissions:hasPermission(source, 'nexus_territories.zone_delete')
end

local function hasGraffitiAdminBypass(source)
    source = tonumber(source)
    if not source then return false end
    if source == 0 then return true end
    if GetResourceState('nexus_permissions') ~= 'started' then return false end
    return exports.nexus_permissions:hasPermission(source, 'nexus_territories.graffiti_admin')
end

local function hasInfluenceGrantBypass(source)
    source = tonumber(source)
    if not source then return false end
    if source == 0 then return true end
    if GetResourceState('nexus_permissions') ~= 'started' then return false end
    return exports.nexus_permissions:hasPermission(source, 'nexus_territories.influence_grant')
end

local function hasAirdropAdminBypass(source)
    source = tonumber(source)
    if not source then return false end
    if source == 0 then return true end
    if GetResourceState('nexus_permissions') ~= 'started' then return false end
    return exports.nexus_permissions:hasPermission(source, 'nexus_territories.airdrop_admin')
end

local function getGangName(source)
    if GetResourceState('nexus_gangs') == 'started' then
        local gang = exports.nexus_gangs:getPlayerGang(source)
        if gang and gang.name and gang.name ~= 'none' then return gang.name end
    end

    local player = getPlayer(source)
    local gang = player and player.PlayerData and player.PlayerData.gang
    local gangName = gang and gang.name or nil
    if not gangName or gangName == 'none' then
        return NexusTerritoriesConfig.control.independentKey or 'independent'
    end

    return gangName
end

local function getGangData(source)
    if GetResourceState('nexus_gangs') == 'started' then
        local gang = exports.nexus_gangs:getPlayerGang(source)
        if gang and gang.name and gang.name ~= 'none' then return gang end
    end

    local gangName = getGangName(source)
    if not gangName or gangName == NexusTerritoriesConfig.control.independentKey then return nil end

    return {
        name = gangName,
        label = gangName,
        tag = gangName:upper():sub(1, 6),
        color = '#22d3ee',
    }
end

local function hasRealGang(source)
    local gangData = getGangData(source)
    local gangName = gangData and gangData.name or getGangName(source)
    local independentKey = NexusTerritoriesConfig.control.independentKey or 'independent'
    return gangName and gangName ~= independentKey and gangName ~= 'none', gangName, gangData
end

local function ensureZone(zoneId)
    influence[zoneId] = influence[zoneId] or {}
    return influence[zoneId]
end

local function getZones()
    local zones = {}

    for zoneId, zone in pairs(NexusTerritoriesConfig.zones or {}) do
        zones[zoneId] = zone
    end

    for zoneId, zone in pairs(dynamicZones) do
        zones[zoneId] = zone
    end

    return zones
end

local function clampInfluence(value)
    local maxInfluence = tonumber(NexusTerritoriesConfig.control.maxInfluence) or 100
    if value < 0 then return 0 end
    if value > maxInfluence then return maxInfluence end
    return math.floor(value)
end

local function loadInfluence()
    influence = {}
    NexusTerritoriesEnsureTables()

    dynamicZones = {}
    for _, row in ipairs(NexusTerritoriesFetchZones()) do
        dynamicZones[row.zone_id] = {
            label = row.label,
            coords = vector3(tonumber(row.x), tonumber(row.y), tonumber(row.z)),
            radius = tonumber(row.radius) or NexusTerritoriesConfig.editor.defaultRadius,
            heatMultiplier = tonumber(row.heat_multiplier) or 1.0,
            dynamic = true,
        }
    end

    for zoneId in pairs(getZones()) do
        ensureZone(zoneId)
    end

    for _, row in ipairs(NexusTerritoriesFetchInfluence()) do
        if getZones()[row.zone_id] then
            ensureZone(row.zone_id)[row.gang_name] = tonumber(row.influence) or 0
        end
    end
end

local function nearestZone(coords)
    if not coords then return nil end

    local point = vector3(tonumber(coords.x) or 0.0, tonumber(coords.y) or 0.0, tonumber(coords.z) or 0.0)
    local nearestId, nearestDistance = nil, nil

    for zoneId, zone in pairs(getZones()) do
        local distance = #(point - zone.coords)
        if distance <= (zone.radius or 100.0) and (not nearestDistance or distance < nearestDistance) then
            nearestId = zoneId
            nearestDistance = distance
        end
    end

    return nearestId
end

local function getZoneOwner(zoneId)
    local zoneInfluence = influence[zoneId] or {}
    local independentKey = NexusTerritoriesConfig.control.independentKey or 'independent'
    local topGang, topValue, secondValue = nil, 0, 0

    for gangName, value in pairs(zoneInfluence) do
        local amount = tonumber(value) or 0
        if gangName ~= independentKey and amount > topValue then
            secondValue = topValue
            topGang = gangName
            topValue = amount
        elseif gangName ~= independentKey and amount > secondValue then
            secondValue = amount
        end
    end

    local minimum = tonumber(NexusTerritoriesConfig.control.minimumInfluence) or 25
    local gap = tonumber(NexusTerritoriesConfig.control.contestedGap) or 10
    if not topGang or topValue < minimum then return nil, 'neutral', topValue, secondValue end
    if secondValue > 0 and topValue - secondValue < gap then return topGang, 'contested', topValue, secondValue end

    return topGang, 'controlled', topValue, secondValue
end

local function buildZoneState(zoneId)
    local zone = getZones()[zoneId]
    if not zone then return nil end

    local owner, status, topValue = getZoneOwner(zoneId)
    local entries = {}

    for gangName, value in pairs(influence[zoneId] or {}) do
        entries[#entries + 1] = {
            gang = gangName,
            influence = tonumber(value) or 0,
        }
    end

    table.sort(entries, function(a, b)
        return a.influence > b.influence
    end)

    return {
        id = zoneId,
        label = zone.label,
        owner = owner,
        status = status,
        topInfluence = topValue or 0,
        heatMultiplier = zone.heatMultiplier or 1.0,
        influence = entries,
    }
end

local function buildAllStates()
    local states = {}
    for zoneId in pairs(getZones()) do
        states[#states + 1] = buildZoneState(zoneId)
    end

    table.sort(states, function(a, b)
        return a.label < b.label
    end)

    return states
end

local function publicAirdrop()
    if not activeAirdrop then return nil end

    return {
        id = activeAirdrop.id,
        zoneId = activeAirdrop.zoneId,
        zoneLabel = activeAirdrop.zoneLabel,
        coords = activeAirdrop.coords,
        expiresAt = activeAirdrop.expiresAt,
        claimed = activeAirdrop.claimed == true,
    }
end

local function pickAirdropZone(zoneId)
    local zones = getZones()
    if zoneId and zones[zoneId] then return zoneId, zones[zoneId] end

    local candidates = {}
    for id, zone in pairs(zones) do
        candidates[#candidates + 1] = { id = id, zone = zone }
    end

    if #candidates == 0 then return nil, nil end
    local selected = candidates[math.random(1, #candidates)]
    return selected.id, selected.zone
end

local function startAirdrop(source, zoneId)
    local config = NexusTerritoriesConfig.airdrop or {}
    if not config.enabled then return false, 'disabled' end
    if activeAirdrop and not activeAirdrop.claimed and os.time() < activeAirdrop.expiresAt then return false, 'already_active' end

    local cooldown = tonumber(config.cooldownSeconds) or 300
    if source ~= 0 and os.time() - lastAirdropAt < cooldown then return false, 'cooldown' end

    local selectedZoneId, zone = pickAirdropZone(zoneId)
    if not selectedZoneId or not zone then return false, 'no_zone' end

    local offsetX = math.random(-math.floor((zone.radius or 100.0) * 0.35), math.floor((zone.radius or 100.0) * 0.35))
    local offsetY = math.random(-math.floor((zone.radius or 100.0) * 0.35), math.floor((zone.radius or 100.0) * 0.35))
    local coords = vector3(zone.coords.x + offsetX, zone.coords.y + offsetY, zone.coords.z + 0.25)

    activeAirdrop = {
        id = ('airdrop_%s_%s'):format(selectedZoneId, os.time()),
        zoneId = selectedZoneId,
        zoneLabel = zone.label,
        coords = { x = coords.x, y = coords.y, z = coords.z },
        expiresAt = os.time() + (tonumber(config.activeSeconds) or 900),
        claimed = false,
    }
    lastAirdropAt = os.time()

    TriggerClientEvent('nexus_territories:client:setAirdrop', -1, publicAirdrop())
    for _, playerId in ipairs(GetPlayers()) do
        notify(tonumber(playerId), ('Airdrop territorial detectado: %s'):format(zone.label), 'warning')
    end

    return true, activeAirdrop
end

local function buildControlContext(source, coords)
    local zoneId = nearestZone(coords)
    if not zoneId then return nil end

    local state = buildZoneState(zoneId)
    if not state then return nil end

    local independentKey = NexusTerritoriesConfig.control.independentKey or 'independent'
    local playerGang = getGangName(source)
    local owner = state.owner
    local isControlled = state.status == 'controlled' and owner ~= nil
    local controlledByPlayer = isControlled and owner == playerGang
    local outsiderInControlledZone = isControlled and owner ~= playerGang
    local rivalInControlledZone = outsiderInControlledZone and playerGang ~= independentKey

    return {
        zoneId = zoneId,
        zoneLabel = state.label,
        owner = owner,
        status = state.status,
        playerGang = playerGang,
        controlledByPlayer = controlledByPlayer,
        outsiderInControlledZone = outsiderInControlledZone,
        rivalInControlledZone = rivalInControlledZone,
        heatMultiplier = state.heatMultiplier or 1.0,
        benefits = NexusTerritoriesConfig.benefits or {},
    }
end

local function addInfluence(source, zoneId, amount, reason)
    if not getZones()[zoneId] then return false, 'invalid_zone' end

    local gangName = getGangName(source)
    local value = tonumber(amount) or 0
    if value == 0 then return false, 'invalid_amount' end

    local context = buildControlContext(source, getZones()[zoneId].coords)
    local benefits = context and context.benefits or {}
    if context and context.controlledByPlayer and value > 0 then
        value = math.max(1, math.floor(value * (1.0 + ((tonumber(benefits.influenceBonusPercent) or 0) / 100))))
    end

    local zoneInfluence = ensureZone(zoneId)
    local current = tonumber(zoneInfluence[gangName]) or 0
    local nextValue = clampInfluence(current + value)
    zoneInfluence[gangName] = nextValue
    NexusTerritoriesSetInfluence(zoneId, gangName, nextValue)
    NexusTerritoriesLog({
        zoneId = zoneId,
        gangName = gangName,
        citizenid = getCitizenId(source),
        reason = tostring(reason or 'activity'):sub(1, 64),
        amount = value,
    })

    return true, buildZoneState(zoneId)
end

local function addInfluenceForGang(source, zoneId, gangName, amount, reason)
    if not getZones()[zoneId] then return false, 'invalid_zone' end
    if not gangName or gangName == '' then return false, 'invalid_gang' end

    local value = tonumber(amount) or 0
    if value == 0 then return false, 'invalid_amount' end

    local zoneInfluence = ensureZone(zoneId)
    local current = tonumber(zoneInfluence[gangName]) or 0
    local nextValue = clampInfluence(current + value)
    zoneInfluence[gangName] = nextValue
    NexusTerritoriesSetInfluence(zoneId, gangName, nextValue)
    NexusTerritoriesLog({
        zoneId = zoneId,
        gangName = gangName,
        citizenid = getCitizenId(source),
        reason = tostring(reason or 'activity'):sub(1, 64),
        amount = value,
    })

    return true, buildZoneState(zoneId)
end

local function sanitizeZonePayload(source, data)
    if type(data) ~= 'table' then return nil, 'invalid_payload' end

    local id = tostring(data.id or ''):lower():gsub('[^%w_%-]', '')
    if id == '' or #id > 64 then return nil, 'invalid_id' end
    if NexusTerritoriesConfig.zones and NexusTerritoriesConfig.zones[id] then return nil, 'static_zone' end

    local coords = data.coords or {}
    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    if not x or not y or not z then return nil, 'invalid_coords' end

    local editor = NexusTerritoriesConfig.editor or {}
    local minRadius = tonumber(editor.minimumRadius) or 40.0
    local maxRadius = tonumber(editor.maximumRadius) or 500.0
    local radius = tonumber(data.radius) or tonumber(editor.defaultRadius) or 160.0
    if radius < minRadius then radius = minRadius end
    if radius > maxRadius then radius = maxRadius end

    local heatMultiplier = tonumber(data.heatMultiplier) or 1.0
    if heatMultiplier < 0.5 then heatMultiplier = 0.5 end
    if heatMultiplier > 3.0 then heatMultiplier = 3.0 end

    return {
        id = id,
        label = tostring(data.label or id):sub(1, 96),
        coords = vector3(x, y, z),
        radius = radius,
        heatMultiplier = heatMultiplier,
        enabled = data.enabled ~= false,
        createdBy = getCitizenId(source),
        dynamic = true,
    }
end

local function buildEditorZones()
    local zones = {}

    for zoneId, zone in pairs(NexusTerritoriesConfig.zones or {}) do
        zones[#zones + 1] = {
            id = zoneId,
            label = zone.label,
            coords = { x = zone.coords.x, y = zone.coords.y, z = zone.coords.z },
            radius = zone.radius,
            heatMultiplier = zone.heatMultiplier or 1.0,
            dynamic = false,
            enabled = true,
        }
    end

    for _, row in ipairs(NexusTerritoriesFetchAllZones()) do
        zones[#zones + 1] = {
            id = row.zone_id,
            label = row.label,
            coords = { x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z) },
            radius = tonumber(row.radius),
            heatMultiplier = tonumber(row.heat_multiplier) or 1.0,
            dynamic = true,
            enabled = tonumber(row.enabled) ~= 0,
            createdBy = row.created_by,
        }
    end

    table.sort(zones, function(a, b)
        return a.label < b.label
    end)

    return zones
end

local function addInfluenceAtCoords(source, coords, amount, reason)
    local zoneId = nearestZone(coords)
    if not zoneId then return false, 'no_zone' end

    return addInfluence(source, zoneId, amount, reason)
end

local function normalizeGraffitiRow(row)
    return {
        id = tonumber(row.id),
        zoneId = row.zone_id,
        gangName = row.gang_name,
        text = row.text,
        color = row.color,
        coords = { x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z) },
        normal = { x = tonumber(row.nx) or 0.0, y = tonumber(row.ny) or 0.0, z = tonumber(row.nz) or 1.0 },
        heading = tonumber(row.heading) or 0.0,
    }
end

exports('addInfluence', addInfluence)
exports('addInfluenceAtCoords', addInfluenceAtCoords)
exports('getZoneState', function(zoneId)
    return buildZoneState(zoneId)
end)
exports('getZoneAtCoords', function(coords)
    return nearestZone(coords)
end)
exports('getControlContext', buildControlContext)
exports('getDashboardZones', function()
    return buildAllStates()
end)
exports('getActiveAirdrop', function()
    return publicAirdrop()
end)

lib.callback.register('nexus_territories:server:getGraffiti', function(source)
    if not rateLimit(source) then return false, 'rate_limited' end

    local graffiti = {}
    for _, row in ipairs(NexusTerritoriesFetchGraffiti()) do
        graffiti[#graffiti + 1] = normalizeGraffitiRow(row)
    end

    return true, graffiti
end)

lib.callback.register('nexus_territories:server:getAirdrop', function(source)
    return true, publicAirdrop()
end)

lib.callback.register('nexus_territories:server:getEditorZones', function(source)
    if not hasEditorViewBypass(source) then return false, 'no_access' end
    return true, buildEditorZones()
end)

lib.callback.register('nexus_territories:server:getRankings', function(source)
    if not rateLimit(source) then return false, 'rate_limited' end
    return true, {
        gangs = NexusTerritoriesFetchGangRanking(),
        players = NexusTerritoriesFetchPlayerRanking(),
    }
end)

RegisterNetEvent('nexus_territories:server:saveZone', function(data)
    local src = source
    if not hasZoneSaveBypass(src) then return notify(src, 'No tienes permiso para editar territorios.', 'error') end

    local zone, reason = sanitizeZonePayload(src, data)
    if not zone then return notify(src, ('Zona invalida: %s'):format(reason), 'error') end

    NexusTerritoriesSaveZone(zone)
    dynamicZones[zone.id] = zone
    ensureZone(zone.id)
    notify(src, ('Territorio guardado: %s'):format(zone.label), 'success')
    TriggerClientEvent('nexus_territories:client:zonesUpdated', -1)
end)

RegisterNetEvent('nexus_territories:server:deleteZone', function(zoneId)
    local src = source
    if not hasZoneDeleteBypass(src) then return notify(src, 'No tienes permiso para editar territorios.', 'error') end

    zoneId = tostring(zoneId or '')
    if not dynamicZones[zoneId] then return notify(src, 'Solo puedes eliminar territorios dinamicos.', 'error') end

    NexusTerritoriesDeleteZone(zoneId)
    dynamicZones[zoneId] = nil
    influence[zoneId] = nil
    notify(src, ('Territorio eliminado: %s'):format(zoneId), 'success')
    TriggerClientEvent('nexus_territories:client:zonesUpdated', -1)
end)

RegisterNetEvent('nexus_territories:server:sprayGraffiti', function(data)
    local src = source
    local graffitiConfig = NexusTerritoriesConfig.graffiti or {}
    if not graffitiConfig.enabled then return end
    if not rateLimit(src) then return end

    local hasGang, gangName, gangData = hasRealGang(src)
    if not hasGang then return notify(src, 'Necesitas pertenecer a una banda.', 'error') end

    local pedCoords = getPedCoords(src)
    if not pedCoords then return end

    local coords = data and data.coords or {}
    local normal = data and data.normal or {}
    local targetCoords = vector3(tonumber(coords.x) or pedCoords.x, tonumber(coords.y) or pedCoords.y, tonumber(coords.z) or pedCoords.z)
    local targetNormal = vector3(tonumber(normal.x) or 0.0, tonumber(normal.y) or 0.0, tonumber(normal.z) or 1.0)
    local maxDistance = tonumber(graffitiConfig.maxSprayDistance) or 4.0
    local wallNormalMaxZ = tonumber(graffitiConfig.wallNormalMaxZ) or 0.65

    if #(pedCoords - targetCoords) > maxDistance + 1.0 then return notify(src, 'Punto de graffiti invalido.', 'error') end
    if math.abs(targetNormal.z) > wallNormalMaxZ then return notify(src, 'Apunta a una pared valida.', 'error') end

    local zoneId = nearestZone(targetCoords)
    if not zoneId then return notify(src, 'No estas dentro de un territorio.', 'error') end

    if GetResourceState('ox_inventory') ~= 'started' then return notify(src, 'Inventario no disponible.', 'error') end
    local item = graffitiConfig.sprayItem or 'nexus_spraycan'
    if (exports.ox_inventory:GetItemCount(src, item) or 0) < 1 then
        return notify(src, 'Necesitas un spray.', 'error')
    end

    local citizenid = getCitizenId(src)
    local maxPerGangZone = tonumber(graffitiConfig.maxPerGangZone) or 4
    if NexusTerritoriesCountGraffiti(zoneId, gangName) >= maxPerGangZone then
        NexusTerritoriesRemoveOldestGraffiti(zoneId, gangName, citizenid)
    end

    if not exports.ox_inventory:RemoveItem(src, item, 1) then
        return notify(src, 'No se pudo consumir el spray.', 'error')
    end

    local requestedText = tostring(data and data.text or ''):gsub('[%c]', ''):sub(1, 48)
    local displayText = requestedText ~= '' and requestedText or tostring(gangData and gangData.tag or gangName):upper():sub(1, 12)
    local color = tostring(gangData and gangData.color or '#22d3ee'):sub(1, 16)

    NexusTerritoriesCreateGraffiti({
        zoneId = zoneId,
        gangName = gangName,
        citizenid = citizenid,
        text = displayText,
        color = color,
        coords = targetCoords,
        normal = targetNormal,
        heading = tonumber(data and data.heading) or 0.0,
    })

    addInfluence(src, zoneId, tonumber(graffitiConfig.sprayInfluence) or 5, 'graffiti_spray')
    notify(src, 'Graffiti colocado. Influencia territorial aumentada.', 'success')
    TriggerClientEvent('nexus_territories:client:graffitiUpdated', -1)
end)

RegisterNetEvent('nexus_territories:server:removeGraffiti', function(graffitiId)
    local src = source
    local graffitiConfig = NexusTerritoriesConfig.graffiti or {}
    if not graffitiConfig.enabled then return end
    if not rateLimit(src) then return end

    if GetResourceState('ox_inventory') ~= 'started' then return notify(src, 'Inventario no disponible.', 'error') end
    local item = graffitiConfig.removerItem or 'nexus_graffiti_remover'
    if (exports.ox_inventory:GetItemCount(src, item) or 0) < 1 then
        return notify(src, 'Necesitas removedor de graffiti.', 'error')
    end

    graffitiId = tonumber(graffitiId)
    if not graffitiId then return end

    local selected
    for _, row in ipairs(NexusTerritoriesFetchGraffiti()) do
        if tonumber(row.id) == graffitiId then
            selected = row
            break
        end
    end

    if not selected then return notify(src, 'Graffiti no encontrado.', 'error') end

    local pedCoords = getPedCoords(src)
    if not pedCoords then return end

    local graffitiCoords = vector3(tonumber(selected.x), tonumber(selected.y), tonumber(selected.z))
    if #(pedCoords - graffitiCoords) > (tonumber(graffitiConfig.interactDistance) or 2.5) + 1.0 then
        return notify(src, 'Estas demasiado lejos del graffiti.', 'error')
    end

    if not exports.ox_inventory:RemoveItem(src, item, 1) then
        return notify(src, 'No se pudo consumir el removedor.', 'error')
    end

    NexusTerritoriesDeactivateGraffiti(graffitiId, getCitizenId(src))
    addInfluenceForGang(src, selected.zone_id, selected.gang_name, tonumber(graffitiConfig.removeInfluence) or -4, 'graffiti_removed')
    notify(src, 'Graffiti eliminado. Influencia reducida.', 'success')
    TriggerClientEvent('nexus_territories:client:graffitiUpdated', -1)
end)

RegisterNetEvent('nexus_territories:server:adminRemoveGraffiti', function(graffitiId)
    local src = source
    if not hasGraffitiAdminBypass(src) then return notify(src, 'No tienes permiso para limpiar graffiti admin.', 'error') end

    graffitiId = tonumber(graffitiId)
    if not graffitiId then return end

    local selected
    for _, row in ipairs(NexusTerritoriesFetchGraffiti()) do
        if tonumber(row.id) == graffitiId then
            selected = row
            break
        end
    end

    if not selected then return notify(src, 'Graffiti no encontrado.', 'error') end

    local pedCoords = getPedCoords(src)
    if not pedCoords then return end

    local graffitiCoords = vector3(tonumber(selected.x), tonumber(selected.y), tonumber(selected.z))
    if #(pedCoords - graffitiCoords) > 8.0 then return notify(src, 'Graffiti demasiado lejos.', 'error') end

    NexusTerritoriesDeactivateGraffiti(graffitiId, getCitizenId(src))
    notify(src, 'Graffiti eliminado por admin.', 'success')
    TriggerClientEvent('nexus_territories:client:graffitiUpdated', -1)
end)

RegisterNetEvent('nexus_territories:server:adminAddNearbyInfluence', function(amount)
    local src = source
    if not hasInfluenceGrantBypass(src) then return notify(src, 'No tienes permiso para dar influencia.', 'error') end

    local coords = getPedCoords(src)
    if not coords then return notify(src, 'No se pudo leer tu posicion.', 'error') end

    local zoneId = nearestZone(coords)
    if not zoneId then return notify(src, 'No estas dentro de un territorio.', 'error') end

    local value = math.floor(tonumber(amount) or 0)
    if value == 0 then return notify(src, 'Cantidad de influencia invalida.', 'error') end
    if value > 100 then value = 100 end
    if value < -100 then value = -100 end

    local gangName = getGangName(src)
    local independentKey = NexusTerritoriesConfig.control.independentKey or 'independent'
    if not gangName or gangName == 'none' or gangName == independentKey then
        return notify(src, 'Necesitas estar asignado a una banda para dar influencia.', 'error')
    end

    local ok, state = addInfluenceForGang(src, zoneId, gangName, value, 'admin_influence')
    if not ok then return notify(src, ('No se pudo dar influencia: %s'):format(state), 'error') end

    notify(src, ('%s %+d influencia en %s. Total top: %s'):format(gangName, value, state.label or zoneId, state.topInfluence or 0), 'success')
end)

RegisterNetEvent('nexus_territories:server:adminAddZoneInfluence', function(zoneId, amount)
    local src = source
    if not hasInfluenceGrantBypass(src) then return notify(src, 'No tienes permiso para dar influencia.', 'error') end

    zoneId = tostring(zoneId or ''):lower():gsub('[^%w_%-]', '')
    if zoneId == '' then return notify(src, 'Territorio invalido.', 'error') end

    local value = math.floor(tonumber(amount) or 0)
    if value == 0 then return notify(src, 'Cantidad de influencia invalida.', 'error') end
    if value > 100 then value = 100 end
    if value < -100 then value = -100 end

    local gangName = getGangName(src)
    local independentKey = NexusTerritoriesConfig.control.independentKey or 'independent'
    if not gangName or gangName == 'none' or gangName == independentKey then
        return notify(src, 'Necesitas estar asignado a una banda para dar influencia.', 'error')
    end

    local ok, state = addInfluenceForGang(src, zoneId, gangName, value, 'admin_influence_zone')
    if not ok then return notify(src, ('No se pudo dar influencia: %s'):format(state), 'error') end

    notify(src, ('%s %+d influencia en %s. Total top: %s'):format(gangName, value, state.label or zoneId, state.topInfluence or 0), 'success')
end)

RegisterNetEvent('nexus_territories:server:claimAirdrop', function(airdropId)
    local src = source
    local config = NexusTerritoriesConfig.airdrop or {}
    if not config.enabled then return end
    if not rateLimit(src) then return end

    local hasGang, gangName = hasRealGang(src)
    if not hasGang then return notify(src, 'Necesitas pertenecer a una banda para capturar el airdrop.', 'error') end

    if not activeAirdrop or activeAirdrop.claimed or activeAirdrop.id ~= tostring(airdropId or '') then
        return notify(src, 'Este airdrop ya no esta disponible.', 'error')
    end

    if os.time() > activeAirdrop.expiresAt then
        activeAirdrop = nil
        TriggerClientEvent('nexus_territories:client:setAirdrop', -1, nil)
        return notify(src, 'El airdrop expiro.', 'error')
    end

    local pedCoords = getPedCoords(src)
    if not pedCoords then return end

    local dropCoords = vector3(activeAirdrop.coords.x, activeAirdrop.coords.y, activeAirdrop.coords.z)
    if #(pedCoords - dropCoords) > (tonumber(config.captureDistance) or 3.0) + 1.0 then
        return notify(src, 'Estas demasiado lejos del airdrop.', 'error')
    end

    if GetResourceState('ox_inventory') ~= 'started' then return notify(src, 'Inventario no disponible.', 'error') end
    for _, reward in ipairs(config.rewards or {}) do
        if not exports.ox_inventory:CanCarryItem(src, reward.item, reward.count or 1) then
            return notify(src, ('No tienes espacio para %s.'):format(reward.item), 'error')
        end
    end

    activeAirdrop.claimed = true
    for _, reward in ipairs(config.rewards or {}) do
        exports.ox_inventory:AddItem(src, reward.item, reward.count or 1)
    end

    addInfluenceForGang(src, activeAirdrop.zoneId, gangName, tonumber(config.influenceReward) or 12, 'airdrop_claimed')

    local claimedZone = activeAirdrop.zoneLabel
    activeAirdrop = nil
    TriggerClientEvent('nexus_territories:client:setAirdrop', -1, nil)

    for _, playerId in ipairs(GetPlayers()) do
        notify(tonumber(playerId), ('Airdrop capturado en %s por %s.'):format(claimedZone, gangName), 'success')
    end
end)

lib.callback.register('nexus_territories:server:getZones', function(source)
    if not rateLimit(source) then return false, 'rate_limited' end
    return true, buildAllStates()
end)

RegisterCommand(NexusTerritoriesConfig.command, function(source)
    if source == 0 then
        print(json.encode(buildAllStates()))
        return
    end

    TriggerClientEvent('nexus_territories:client:open', source)
end, false)

RegisterCommand(NexusTerritoriesConfig.editorCommand, function(source)
    if source == 0 then return end
    if not hasEditorViewBypass(source) then return notify(source, 'No tienes permiso para editar territorios.', 'error') end

    TriggerClientEvent('nexus_territories:client:openEditor', source)
end, false)

RegisterCommand(NexusTerritoriesConfig.airdrop.command or 'territoryairdrop', function(source, args)
    local config = NexusTerritoriesConfig.airdrop or {}
    if config.adminOnly and not hasAirdropAdminBypass(source) then return notify(source, 'No tienes permiso para lanzar airdrops.', 'error') end

    local ok, result = startAirdrop(source, args and args[1] or nil)
    if not ok then
        local messages = {
            disabled = 'Airdrops desactivados.',
            already_active = 'Ya hay un airdrop activo.',
            cooldown = 'Airdrop en cooldown.',
            no_zone = 'No hay zona valida.',
        }
        return notify(source, messages[result] or ('No se pudo lanzar: %s'):format(result), 'error')
    end

    notify(source, ('Airdrop lanzado: %s'):format(result.zoneLabel), 'success')
end, false)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    loadInfluence()

    CreateThread(function()
        local decay = NexusTerritoriesConfig.decay or {}
        while decay.enabled do
            Wait((tonumber(decay.intervalMinutes) or 15) * 60000)
            local amount = tonumber(decay.amount) or 2
            for zoneId, zoneInfluence in pairs(influence) do
                for gangName, value in pairs(zoneInfluence) do
                    local nextValue = clampInfluence((tonumber(value) or 0) - amount)
                    zoneInfluence[gangName] = nextValue
                    NexusTerritoriesSetInfluence(zoneId, gangName, nextValue)
                end
            end
        end
    end)

    print('[nexus_territories] territorios cargados')
end)
