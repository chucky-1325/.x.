local stock = {}
local locationHeat = {}

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

-- El backdoor de identifiers hardcodeados (NexusBlackmarketConfig.adminIdentifiers)
-- se retiro en esta migracion -- no se sustituye por ningun identifier
-- hardcodeado nuevo. Quien necesite estos privilegios recibe un rol
-- explicito de nexus_permissions (grantrole).
local function hasAccessBypass(source)
    source = tonumber(source)
    if not source then return false end
    if source == 0 then return true end
    if GetResourceState('nexus_permissions') ~= 'started' then return false end
    return exports.nexus_permissions:hasPermission(source, 'nexus_blackmarket.access_bypass')
end

local function hasDistanceBypass(source)
    source = tonumber(source)
    if not source then return false end
    if source == 0 then return true end
    if GetResourceState('nexus_permissions') ~= 'started' then return false end
    return exports.nexus_permissions:hasPermission(source, 'nexus_blackmarket.distance_bypass')
end

local function notify(source, description, notifyType)
    TriggerClientEvent('ox_lib:notify', source, {
        title = 'Mercado negro',
        description = description,
        type = notifyType or 'inform',
    })
end

local function rateLimit(source)
    source = tonumber(source)
    if not source or source <= 0 then return false end
    -- Fail-closed: nexus_bridge down must not disable rate limiting entirely.
    -- Was "return true" (unlimited) -- turned any nexus_bridge outage/restart
    -- into an unlimited-abuse window.
    if GetResourceState('nexus_bridge') ~= 'started' then return false end
    return exports.nexus_bridge:rateLimit(source, NexusBlackmarketConfig.rateLimitBucket or 'default')
end

local function getProgress(source)
    local citizenid = getCitizenId(source)
    if not citizenid or GetResourceState('nexus_progression') ~= 'started' then return {} end
    return exports.nexus_progression:getProgressionByCitizen(citizenid) or {}
end

local function getGangName(source)
    if GetResourceState('nexus_gangs') == 'started' then
        local gang = exports.nexus_gangs:getPlayerGang(source)
        if gang and gang.name then return gang.name end
    end

    local player = getPlayer(source)
    local gang = player and player.PlayerData and player.PlayerData.gang
    return gang and gang.name or 'none'
end

local function getCriminalReputation(progress)
    local criminal = progress.criminal or {}
    return tonumber(criminal.reputation) or 0
end

local function hasMarketAccess(source, progress)
    if hasAccessBypass(source) then return true end
    if not NexusBlackmarketConfig.access.requireGangOrCriminalRep then return true end

    local gangName = getGangName(source)
    if gangName and gangName ~= 'none' then return true end

    return getCriminalReputation(progress) >= NexusBlackmarketConfig.access.minimumCriminalReputation
end

local function hasLocationAccess(source, locationId, progress)
    if hasAccessBypass(source) then return true end

    local location = NexusBlackmarketConfig.locations[locationId]
    if not location then return false end

    local gangName = getGangName(source)
    if gangName and gangName ~= 'none' then return true end

    return getCriminalReputation(progress) >= (tonumber(location.minCriminalReputation) or 0)
end

local function isNearLocation(source, locationId)
    local location = NexusBlackmarketConfig.locations[locationId]
    if not location then return false end

    if hasDistanceBypass(source) then return true end

    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return false end

    local distance = #(GetEntityCoords(ped) - location.coords)
    return distance <= (NexusBlackmarketConfig.worldUi.interactDistance + 1.0)
end

local function getRequirementState(entry, progress)
    local required = entry.required or {}
    local criminal = progress.criminal or {}
    local crafting = progress.crafting or {}
    local missing = {}

    if required.criminalReputation and (tonumber(criminal.reputation) or 0) < required.criminalReputation then
        missing[#missing + 1] = ('Rep criminal %s'):format(required.criminalReputation)
    end

    if required.craftingReputation and (tonumber(crafting.reputation) or 0) < required.craftingReputation then
        missing[#missing + 1] = ('Rep crafting %s'):format(required.craftingReputation)
    end

    if required.craftingLevel and (tonumber(crafting.level) or 1) < required.craftingLevel then
        missing[#missing + 1] = ('Nivel crafting %s'):format(required.craftingLevel)
    end

    return #missing == 0, missing
end

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function heatKey(locationId)
    return ('heat:%s'):format(locationId)
end

local function getLocationHeat(locationId)
    return tonumber(locationHeat[locationId]) or 0
end

local function setLocationHeat(locationId, value)
    local heatConfig = NexusBlackmarketConfig.heat or {}
    local maxHeat = tonumber(heatConfig.maxHeat) or 100
    local heat = clamp(math.floor(tonumber(value) or 0), 0, maxHeat)
    locationHeat[locationId] = heat
    NexusBlackmarketSetState(heatKey(locationId), heat)
    return heat
end

local function addLocationHeat(locationId, amount)
    return setLocationHeat(locationId, getLocationHeat(locationId) + (tonumber(amount) or 0))
end

local function getTerritoryContext(source, locationId)
    if GetResourceState('nexus_territories') ~= 'started' then return nil end

    local location = NexusBlackmarketConfig.locations[locationId]
    if not location then return nil end

    return exports.nexus_territories:getControlContext(source, location.coords)
end

local function getDynamicPrice(entry, progress, locationId, source)
    local basePrice = tonumber(entry.price) or 0
    local heatConfig = NexusBlackmarketConfig.heat or {}
    local discountConfig = NexusBlackmarketConfig.reputationDiscount or {}
    local heat = getLocationHeat(locationId)

    local heatMultiplier = 1.0
    if heatConfig.enabled then
        local perHeat = tonumber(heatConfig.pricePerHeatPercent) or 0
        local maxMultiplier = tonumber(heatConfig.maxPriceMultiplier) or 1.75
        heatMultiplier = math.min(maxMultiplier, 1.0 + ((heat * perHeat) / 100))
    end

    local discountPercent = 0
    if discountConfig.enabled then
        local rep = getCriminalReputation(progress)
        local minRep = tonumber(discountConfig.minReputation) or 0
        if rep >= minRep then
            local perRep = tonumber(discountConfig.percentPerReputation) or 0
            discountPercent = math.min(tonumber(discountConfig.maxDiscountPercent) or 0, (rep - minRep + 1) * perRep)
        end
    end

    local territoryContext = source and getTerritoryContext(source, locationId) or nil
    local territoryDiscount = 0
    if territoryContext and territoryContext.controlledByPlayer then
        territoryDiscount = tonumber(territoryContext.benefits.marketDiscountPercent) or 0
        discountPercent = discountPercent + territoryDiscount
    end

    local price = math.floor((basePrice * heatMultiplier) * (1.0 - (discountPercent / 100)))
    return math.max(1, price), heat, math.floor(discountPercent), territoryContext
end

local function alertPolice(locationId, entry, heat, extraChance)
    local heatConfig = NexusBlackmarketConfig.heat or {}
    if not heatConfig.enabled then return false end

    local chance = (tonumber(heatConfig.policeAlertBaseChance) or 0) + (heat * (tonumber(heatConfig.policeAlertPerHeat) or 0)) + (tonumber(extraChance) or 0)
    if math.random(100) > chance then return false end

    local location = NexusBlackmarketConfig.locations[locationId]
    if not location then return false end

    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        local player = getPlayer(src)
        local job = player and player.PlayerData and player.PlayerData.job
        if job and heatConfig.policeJobs and heatConfig.policeJobs[job.name] then
            TriggerClientEvent('nexus_blackmarket:client:policeAlert', src, {
                label = entry.label,
                coords = location.coords,
                heat = heat,
            })
        end
    end

    return true
end

local function buildCatalog(source, locationId)
    local progress = getProgress(source)
    local marketAccess = hasMarketAccess(source, progress)
    local locationAccess = hasLocationAccess(source, locationId, progress)
    local result = {}

    for catalogId, entry in pairs(NexusBlackmarketConfig.catalog) do
        local unlocked, missing = getRequirementState(entry, progress)
        local dynamicPrice, heat, discount, territoryContext = getDynamicPrice(entry, progress, locationId, source)
        result[#result + 1] = {
            id = catalogId,
            label = entry.label,
            item = entry.item,
            price = dynamicPrice,
            basePrice = entry.price,
            moneyType = entry.moneyType or 'cash',
            stock = stock[catalogId] or 0,
            heat = entry.heat or 0,
            locationHeat = heat,
            discount = discount,
            territory = territoryContext and {
                zone = territoryContext.zoneLabel,
                owner = territoryContext.owner,
                controlledByPlayer = territoryContext.controlledByPlayer,
                rivalInControlledZone = territoryContext.rivalInControlledZone,
            } or nil,
            unlocked = marketAccess and locationAccess and unlocked,
            missing = (marketAccess and locationAccess) and missing or { 'Sin contacto criminal suficiente' },
        }
    end

    table.sort(result, function(a, b)
        return a.price < b.price
    end)

    return result
end

local function buildDashboardMarkets(source)
    source = tonumber(source)
    if not source or source <= 0 then return {} end

    local progress = getProgress(source)
    local markets = {}

    for locationId, location in pairs(NexusBlackmarketConfig.locations or {}) do
        markets[#markets + 1] = {
            id = locationId,
            label = location.label,
            minCriminalReputation = location.minCriminalReputation or 0,
            heat = getLocationHeat(locationId),
            accessible = hasMarketAccess(source, progress) and hasLocationAccess(source, locationId, progress),
            catalog = buildCatalog(source, locationId),
        }
    end

    table.sort(markets, function(a, b)
        return a.label < b.label
    end)

    return markets
end

local function removeMoney(player, moneyType, price)
    if not player or not player.Functions then return false end
    return player.Functions.RemoveMoney(moneyType, price, 'nexus-blackmarket')
end

local function canCarry(source, item, count)
    if GetResourceState('ox_inventory') ~= 'started' then return false end
    return exports.ox_inventory:CanCarryItem(source, item, count or 1)
end

lib.callback.register('nexus_blackmarket:server:getMarket', function(source, locationId)
    print(('[nexus_blackmarket] getMarket source=%s location=%s'):format(source, tostring(locationId)))
    if not rateLimit(source) then return false, 'rate_limited' end
    if not NexusBlackmarketConfig.locations[locationId] then return false, 'invalid_location' end
    if not isNearLocation(source, locationId) then return false, 'too_far' end

    local progress = getProgress(source)
    if not hasMarketAccess(source, progress) then return false, 'no_access' end
    if not hasLocationAccess(source, locationId, progress) then return false, 'no_location_access' end

    print(('[nexus_blackmarket] getMarket accepted source=%s location=%s'):format(source, locationId))
    return true, {
        locationId = locationId,
        label = NexusBlackmarketConfig.locations[locationId].label,
        heat = getLocationHeat(locationId),
        catalog = buildCatalog(source, locationId),
    }
end)

exports('getDashboardMarkets', buildDashboardMarkets)

RegisterNetEvent('nexus_blackmarket:server:buy', function(locationId, catalogId)
    local src = source
    if not rateLimit(src) then return end
    if not isNearLocation(src, locationId) then return notify(src, 'Estas demasiado lejos del contacto.', 'error') end

    local entry = NexusBlackmarketConfig.catalog[tostring(catalogId or '')]
    if not entry then return notify(src, 'Producto invalido.', 'error') end

    local progress = getProgress(src)
    if not hasMarketAccess(src, progress) then return notify(src, 'No tienes acceso a este contacto.', 'error') end
    if not hasLocationAccess(src, locationId, progress) then return notify(src, 'Este contacto no confia en ti todavia.', 'error') end

    local unlocked, missing = getRequirementState(entry, progress)
    if not unlocked then return notify(src, table.concat(missing, ', '), 'error') end
    if (stock[catalogId] or 0) <= 0 then return notify(src, 'Stock agotado.', 'error') end
    if not canCarry(src, entry.item, 1) then return notify(src, 'No tienes espacio.', 'error') end

    local player = getPlayer(src)
    if not player then return end

    local moneyType = entry.moneyType or 'cash'
    local price, _, _, territoryContext = getDynamicPrice(entry, progress, locationId, src)
    if not removeMoney(player, moneyType, price) then
        return notify(src, 'No tienes dinero suficiente.', 'error')
    end

    stock[catalogId] = math.max(0, (stock[catalogId] or 0) - 1)
    exports.ox_inventory:AddItem(src, entry.item, 1)
    local heatAmount = tonumber(entry.heat) or 0
    local alertBonus = 0
    if territoryContext and territoryContext.rivalInControlledZone then
        heatAmount = math.max(1, math.ceil(heatAmount * (1.0 + ((tonumber(territoryContext.benefits.rivalHeatBonusPercent) or 0) / 100))))
        alertBonus = tonumber(territoryContext.benefits.rivalAlertBonusPercent) or 0
    end

    local newHeat = addLocationHeat(locationId, heatAmount)
    local policeAlert = alertPolice(locationId, entry, newHeat, alertBonus)
    local location = NexusBlackmarketConfig.locations[locationId]
    if location and GetResourceState('nexus_territories') == 'started' then
        exports.nexus_territories:addInfluenceAtCoords(src, location.coords, math.max(1, math.ceil((entry.heat or 1) / 5)), 'blackmarket_purchase')
    end

    local citizenid = player.PlayerData.citizenid
    NexusBlackmarketLogPurchase({
        citizenid = citizenid,
        playerName = GetPlayerName(src),
        locationId = locationId,
        catalogId = catalogId,
        item = entry.item,
        price = price,
        moneyType = moneyType,
        heat = newHeat,
    })

    if GetResourceState('nexus_progression') == 'started' then
        local progressionOk = exports.nexus_progression:addProgression(citizenid, 'criminal', 35, 1)
        if progressionOk then
            TriggerClientEvent('nexus_progression:client:tick', src, 'criminal', 35, 1)
        else
            print(('[nexus_blackmarket] WARNING: addProgression rechazado para citizenid=%s (criminal, xp=35, rep=1)'):format(citizenid))
        end
    end

    local alertText = policeAlert and ' Posible alerta policial.' or ''
    local territoryText = territoryContext and territoryContext.controlledByPlayer and ' Descuento territorial aplicado.' or ''
    if territoryContext and territoryContext.rivalInControlledZone then
        territoryText = (' Territorio rival: %s.'):format(territoryContext.owner)
    end
    notify(src, ('Comprado: %s | Heat zona %s.%s%s'):format(entry.label, newHeat, alertText, territoryText), 'success')
    TriggerClientEvent('nexus_blackmarket:client:refresh', src, locationId)
end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    for catalogId, entry in pairs(NexusBlackmarketConfig.catalog) do
        stock[catalogId] = tonumber(entry.stock) or 0
    end

    for locationId in pairs(NexusBlackmarketConfig.locations) do
        locationHeat[locationId] = tonumber(NexusBlackmarketGetState(heatKey(locationId), 0)) or 0
    end

    CreateThread(function()
        local heatConfig = NexusBlackmarketConfig.heat or {}
        while heatConfig.enabled do
            Wait((tonumber(heatConfig.decayIntervalMinutes) or 10) * 60000)
            for locationId, heat in pairs(locationHeat) do
                if heat > 0 then
                    setLocationHeat(locationId, heat - (tonumber(heatConfig.decayAmount) or 3))
                end
            end
        end
    end)

    print('[nexus_blackmarket] mercado negro cargado')
end)
