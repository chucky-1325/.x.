local function notify(source, description, notifyType)
    TriggerClientEvent('ox_lib:notify', source, {
        title = 'Lavado',
        description = description,
        type = notifyType or 'inform',
    })
end

local function rateLimit(source)
    source = tonumber(source)
    if not source or source <= 0 then return false end
    if GetResourceState('nexus_bridge') ~= 'started' then return true end
    return exports.nexus_bridge:rateLimit(source, NexusLaunderingConfig.rateLimitBucket or 'laundering')
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

local function isNear(source, coords, distance)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return false end
    return #(GetEntityCoords(ped) - vector3(coords.x, coords.y, coords.z)) <= (distance or NexusLaunderingConfig.interactDistance or 3.0)
end

local function getZoneState(zoneId)
    if GetResourceState('nexus_territories') ~= 'started' then return nil end
    local ok, state = pcall(function()
        return exports.nexus_territories:getZoneState(zoneId)
    end)
    return ok and state or nil
end

local function effectiveRisk(source, location)
    local risk = tonumber(location.baseRisk) or 0
    local gang = getGang(source)
    local zone = getZoneState(location.zoneId)

    if zone and zone.status == 'controlled' and zone.owner == gang.name then risk = risk - 5 end
    if zone and zone.status == 'contested' then risk = risk + 8 end
    if zone and zone.status == 'controlled' and zone.owner and zone.owner ~= gang.name then risk = risk + 14 end
    risk = math.floor(risk * (tonumber(zone and zone.heatMultiplier) or 1.0))
    return math.max(0, math.min(95, risk)), gang, zone
end

local function buildLocations(source)
    local citizenid = getCitizenId(source)
    local progress = getProgress(source)
    local criminal = progress.criminal or {}
    local gang = getGang(source)
    local locations = {}

    for locationId, location in pairs(NexusLaunderingConfig.locations or {}) do
        local cooldown = citizenid and NexusLaunderingGetCooldown(citizenid, locationId) or 0
        local risk = effectiveRisk(source, location)
        local unlocked = (tonumber(criminal.reputation) or 0) >= (location.minCriminalReputation or 0)
        if location.requiredGang and (not gang.name or gang.name == 'none') then unlocked = false end

        locations[#locations + 1] = {
            id = locationId,
            label = location.label,
            zoneId = location.zoneId,
            coords = publicVec4(location.coords),
            commissionPercent = location.commissionPercent or 25,
            minCriminalReputation = location.minCriminalReputation or 0,
            requiredGang = location.requiredGang == true,
            risk = risk,
            cooldownRemaining = cooldown,
            unlocked = unlocked and cooldown <= 0,
        }
    end

    table.sort(locations, function(a, b)
        return a.minCriminalReputation < b.minCriminalReputation
    end)

    return locations
end

local function sendDispatchAlert(location, risk, context)
    if GetResourceState('nexus_dispatch') ~= 'started' then return end

    context = context or {}
    pcall(function()
        exports.nexus_dispatch:createAlert({
            type = 'laundering',
            title = 'Lavado de dinero',
            message = context.message or (location.label or 'Movimiento sospechoso'),
            coords = location.coords,
            zoneId = location.zoneId,
            sourceResource = GetCurrentResourceName(),
            sourcePlayer = context.source,
            gangName = context.gangName,
            risk = risk,
            priority = 2,
        })
    end)
end

local function alertPolice(location, risk, context)
    if math.random(100) > risk then return false end
    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        local player = getPlayer(src)
        local job = player and player.PlayerData and player.PlayerData.job
        if job and NexusLaunderingConfig.policeJobs[job.name] then
            TriggerClientEvent('nexus_laundering:client:policeAlert', src, {
                label = location.label,
                coords = location.coords,
            })
        end
    end
    sendDispatchAlert(location, risk, context)
    return true
end

lib.callback.register('nexus_laundering:server:getLocations', function(source)
    if not rateLimit(source) then return false, 'rate_limited' end
    return true, buildLocations(source)
end)

exports('getDashboardLaundering', function(source)
    source = tonumber(source)
    if not source or source <= 0 then return { locations = {}, logs = {} } end
    local citizenid = getCitizenId(source)
    return {
        locations = buildLocations(source),
        logs = NexusLaunderingGetRecentLogs(citizenid, 8),
    }
end)

RegisterNetEvent('nexus_laundering:server:launder', function(locationId, amount)
    local src = source
    if not rateLimit(src) then return end
    if GetResourceState('ox_inventory') ~= 'started' then return notify(src, 'Inventario no disponible.', 'error') end

    locationId = tostring(locationId or '')
    local location = NexusLaunderingConfig.locations[locationId]
    if not location then return notify(src, 'Punto de lavado invalido.', 'error') end
    if not isNear(src, location.coords, (NexusLaunderingConfig.interactDistance or 3.0) + 1.5) then return notify(src, 'Estas demasiado lejos del punto de lavado.', 'error') end

    local limits = NexusLaunderingConfig.limits or {}
    local dirtyAmount = math.floor(tonumber(amount) or 0)
    if dirtyAmount < (limits.minAmount or 250) then return notify(src, ('Minimo de lavado: $%s'):format(limits.minAmount or 250), 'error') end
    if dirtyAmount > (limits.maxAmount or 15000) then dirtyAmount = limits.maxAmount or 15000 end

    local citizenid = getCitizenId(src)
    if not citizenid then return notify(src, 'CitizenID no disponible.', 'error') end

    local cooldown = NexusLaunderingGetCooldown(citizenid, locationId)
    if cooldown > 0 then return notify(src, ('Lavado en cooldown: %s min.'):format(math.ceil(cooldown / 60)), 'error') end

    local criminal = (getProgress(src).criminal or {})
    if (tonumber(criminal.reputation) or 0) < (location.minCriminalReputation or 0) then
        return notify(src, 'Necesitas mas reputacion criminal para este contacto.', 'error')
    end

    local gang = getGang(src)
    if location.requiredGang and (not gang.name or gang.name == 'none') then
        return notify(src, 'Este punto requiere pertenecer a una banda.', 'error')
    end

    local item = NexusLaunderingConfig.dirtyItem or 'black_money'
    if (exports.ox_inventory:GetItemCount(src, item) or 0) < dirtyAmount then
        return notify(src, ('Necesitas $%s en dinero sucio.'):format(dirtyAmount), 'error')
    end

    if not exports.ox_inventory:RemoveItem(src, item, dirtyAmount) then
        return notify(src, 'No se pudo retirar dinero sucio.', 'error')
    end

    local commission = math.floor(dirtyAmount * ((location.commissionPercent or 25) / 100))
    local cleanAmount = math.max(0, dirtyAmount - commission)
    local player = getPlayer(src)
    if not player then return notify(src, 'Jugador no disponible.', 'error') end
    player.Functions.AddMoney('cash', cleanAmount, 'nexus-laundering')

    local risk = effectiveRisk(src, location)
    local policeAlert = alertPolice(location, risk, {
        source = src,
        gangName = gang and gang.name or nil,
        message = ('Posible lavado en %s'):format(location.label or locationId),
    })
    NexusLaunderingSetCooldown(citizenid, locationId, limits.cooldownSeconds or 900)
    NexusLaunderingLog({
        citizenid = citizenid,
        playerName = GetPlayerName(src),
        gangName = gang and gang.name or nil,
        locationId = locationId,
        zoneId = location.zoneId,
        dirtyAmount = dirtyAmount,
        cleanAmount = cleanAmount,
        commission = commission,
        risk = risk,
        policeAlert = policeAlert,
    })

    if GetResourceState('nexus_progression') == 'started' then
        local progressionOk = exports.nexus_progression:addProgression(citizenid, 'criminal', math.floor(dirtyAmount / 100), 1)
        if progressionOk then
            TriggerClientEvent('nexus_progression:client:tick', src, 'criminal', math.floor(dirtyAmount / 100), 1)
        else
            print(('[nexus_laundering] WARNING: addProgression rechazado para citizenid=%s (criminal, xp=%s, rep=1)'):format(citizenid, math.floor(dirtyAmount / 100)))
        end
    end

    notify(src, ('Lavado completado: $%s limpio | Comision $%s | Riesgo %s%%'):format(cleanAmount, commission, risk), 'success')
end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    math.randomseed(os.time())
    print('[nexus_laundering] lavado de dinero cargado')
end)
