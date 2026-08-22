local function isAdmin(source)
    if source == 0 then return true end
    if IsPlayerAceAllowed(source, NexusMenuConfig.admin.ace or 'admin') then return true end

    local allowedIdentifiers = NexusMenuConfig.admin.identifiers or {}
    for i = 0, GetNumPlayerIdentifiers(source) - 1 do
        local identifier = GetPlayerIdentifier(source, i)
        if identifier and allowedIdentifiers[identifier] then return true end
    end

    return false
end

local function notify(source, description, notifyType)
    TriggerClientEvent('ox_lib:notify', source, {
        title = 'NEXUS Admin',
        description = description,
        type = notifyType or 'inform',
    })
end

local function getCitizenId(source)
    if GetResourceState('qbx_core') ~= 'started' then return nil end

    local player = exports.qbx_core:GetPlayer(source)
    return player and player.PlayerData and player.PlayerData.citizenid or nil
end

local function getPlayerData(source)
    if GetResourceState('qbx_core') ~= 'started' then return nil end

    local player = exports.qbx_core:GetPlayer(source)
    return player and player.PlayerData or nil
end

local function isPolice(data)
    local job = data and data.job or {}
    local policeJobs = NexusMenuConfig.access and NexusMenuConfig.access.policeJobs or {}

    return job.type == 'leo' or policeJobs[job.name] == true
end

local function isEms(data)
    local job = data and data.job or {}
    local emsJobs = NexusMenuConfig.access and NexusMenuConfig.access.emsJobs or {}
    return job.type == 'ems' or emsJobs[job.name] == true
end

local function hasGang(data)
    local gang = data and data.gang or {}
    return gang.name ~= nil and gang.name ~= 'none'
end

lib.callback.register('nexus_menu:server:isAdmin', function(source)
    return isAdmin(source)
end)

lib.callback.register('nexus_menu:server:getAccess', function(source)
    local data = getPlayerData(source)
    local admin = isAdmin(source)
    local job = data and data.job or {}
    local gang = data and data.gang or {}
    local police = admin or isPolice(data)
    local ems = admin or isEms(data)
    local illegal = admin or hasGang(data)

    return {
        admin = admin,
        police = police,
        ems = ems,
        illegal = illegal,
        job = {
            name = job.name or 'unemployed',
            label = job.label or 'Civil',
            type = job.type or 'none',
            onduty = job.onduty == true,
        },
        gang = {
            name = gang.name or 'none',
            label = gang.label or 'Sin banda',
        },
    }
end)

RegisterNetEvent('nexus_menu:server:giveAdminKit', function(kitId)
    local src = source
    if not isAdmin(src) then return notify(src, 'No tienes permiso.', 'error') end
    if GetResourceState('ox_inventory') ~= 'started' then return notify(src, 'ox_inventory no iniciado.', 'error') end

    local kit = NexusMenuConfig.admin.kits[tostring(kitId or '')]
    if not kit then return notify(src, 'Kit invalido.', 'error') end

    local added = 0
    for i = 1, #(kit.items or {}) do
        local entry = kit.items[i]
        if entry.item and exports.ox_inventory:AddItem(src, entry.item, entry.count or 1) then
            added = added + 1
        end
    end

    notify(src, ('Kit entregado: %s (%s items)'):format(kit.label, added), 'success')
end)

RegisterNetEvent('nexus_menu:server:addCraftingProgress', function(xp, reputation)
    local src = source
    if not isAdmin(src) then return notify(src, 'No tienes permiso.', 'error') end
    if GetResourceState('nexus_progression') ~= 'started' then return notify(src, 'nexus_progression no iniciado.', 'error') end

    local citizenid = getCitizenId(src)
    if not citizenid then return notify(src, 'CitizenID no disponible.', 'error') end

    local amount = tonumber(xp) or 500
    local rep = tonumber(reputation) or 5
    exports.nexus_progression:addProgression(citizenid, 'crafting', amount, rep)
    TriggerClientEvent('nexus_progression:client:tick', src, 'crafting', amount, rep)
    notify(src, ('Crafting +%s XP | +%s reputacion'):format(amount, rep), 'success')
end)

RegisterNetEvent('nexus_menu:server:addDomainProgress', function(domain, xp, reputation)
    local src = source
    if not isAdmin(src) then return notify(src, 'No tienes permiso.', 'error') end
    if GetResourceState('nexus_progression') ~= 'started' then return notify(src, 'nexus_progression no iniciado.', 'error') end

    local cleanDomain = tostring(domain or '')
    if cleanDomain ~= 'criminal' and cleanDomain ~= 'crafting' and cleanDomain ~= 'civil'
        and cleanDomain ~= 'police' and cleanDomain ~= 'ems' and cleanDomain ~= 'business' then
        return notify(src, 'Dominio invalido.', 'error')
    end

    local citizenid = getCitizenId(src)
    if not citizenid then return notify(src, 'CitizenID no disponible.', 'error') end

    local amount = tonumber(xp) or 500
    local rep = tonumber(reputation) or 5
    exports.nexus_progression:addProgression(citizenid, cleanDomain, amount, rep)
    TriggerClientEvent('nexus_progression:client:tick', src, cleanDomain, amount, rep)
    notify(src, ('%s +%s XP | +%s reputacion'):format(cleanDomain, amount, rep), 'success')
end)

lib.callback.register('nexus_menu:server:getIllegalValidationStatus', function(source)
    if not isAdmin(source) then
        return false, 'forbidden'
    end

    local resources = {
        'nexus_gangs',
        'nexus_territories',
        'nexus_contracts',
        'nexus_blackmarket',
        'nexus_crafting',
        'nexus_operations',
        'nexus_labs',
        'nexus_laundering',
        'nexus_tablet',
        'nexus_progression',
    }

    local status = {}
    for i = 1, #resources do
        local resource = resources[i]
        status[#status + 1] = {
            name = resource,
            state = GetResourceState(resource),
        }
    end

    return true, {
        citizenid = getCitizenId(source),
        resources = status,
    }
end)
