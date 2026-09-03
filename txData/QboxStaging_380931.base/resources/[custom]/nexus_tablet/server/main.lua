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

-- Dos bypasses administrativos distintos -- permisos separados, no un unico
-- "isAdmin" generico (ver nexus_permissions/config.lua PermissionCatalog).
local function hasIllegalAccessBypass(source)
    source = tonumber(source)
    if not source then return false end
    if source == 0 then return true end
    if GetResourceState('nexus_permissions') ~= 'started' then return false end
    return exports.nexus_permissions:hasPermission(source, 'nexus_tablet.bypass_illegal_access')
end

local function hasAppRestrictionBypass(source)
    source = tonumber(source)
    if not source then return false end
    if source == 0 then return true end
    if GetResourceState('nexus_permissions') ~= 'started' then return false end
    return exports.nexus_permissions:hasPermission(source, 'nexus_tablet.bypass_app_restriction')
end

local function rateLimit(source)
    source = tonumber(source)
    if not source or source <= 0 then return false end
    -- Fail-closed: nexus_bridge down must not disable rate limiting entirely.
    -- Was "return true" (unlimited) -- turned any nexus_bridge outage/restart
    -- into an unlimited-abuse window.
    if GetResourceState('nexus_bridge') ~= 'started' then return false end
    return exports.nexus_bridge:rateLimit(source, 'tablet')
end

local function getProgress(source)
    local citizenid = getCitizenId(source)
    if not citizenid or GetResourceState('nexus_progression') ~= 'started' then return {} end
    return exports.nexus_progression:getProgressionByCitizen(citizenid) or {}
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

local function hasIllegalAccess(source)
    if hasIllegalAccessBypass(source) then return true end

    local gang = getGang(source)
    if gang and gang.name and gang.name ~= 'none' then return true end

    local progress = getProgress(source)
    local criminal = progress.criminal or {}
    local minimum = NexusTabletConfig.illegalAccess and NexusTabletConfig.illegalAccess.minimumCriminalReputation or 2
    return (tonumber(criminal.reputation) or 0) >= minimum
end

local function fallbackDashboard(source)
    local progress = getProgress(source)
    return {
        identity = {
            callsign = 'NEXUS/CLANDESTINE',
            mode = 'illegal',
        },
        gang = getGang(source),
        progress = {
            criminal = progress.criminal or {},
            crafting = progress.crafting or {},
        },
        assets = { locations = {}, garageVehicles = {} },
        contracts = { contracts = {}, active = nil },
        operations = { operations = {}, active = nil },
        operationLogs = {},
        members = { members = {}, permissions = {}, rank = 0, isBoss = false },
        audit = {},
        labs = { labs = {}, logs = {} },
        laundering = { locations = {}, logs = {} },
        markets = {},
        territories = {},
        airdrop = nil,
    }
end

local function safeExport(resource, exportName, fallback, ...)
    if GetResourceState(resource) ~= 'started' then return fallback end

    local args = { ... }
    local ok, result = pcall(function()
        return exports[resource][exportName](table.unpack(args))
    end)

    if not ok then
        print(('[nexus_tablet] export failed %s:%s -> %s'):format(resource, exportName, result))
        return fallback
    end

    return result or fallback
end

local function listCount(value)
    if type(value) ~= 'table' then return 0 end
    local count = 0
    for _ in pairs(value) do
        count = count + 1
    end
    return count
end

local function canOpen(source, appId)
    source = tonumber(source)
    if not source or source <= 0 then return false, 'invalid_source' end

    local app = NexusTabletApps[appId or NexusTabletConfig.defaultApp]
    if not app then return false, 'invalid_app' end
    if not app.access then return true, app end
    if hasAppRestrictionBypass(source) then return true, app end

    if not rateLimit(source) then return false, 'rate_limited' end
    if app.access == 'illegal' then
        return hasIllegalAccess(source), app
    end

    if GetResourceState('nexus_bridge') ~= 'started' then return false, 'bridge_missing' end
    if not exports.nexus_bridge:hasAccess(source, app.access) then return false, 'no_access' end

    return true, app
end

lib.callback.register('nexus_tablet:server:canOpen', function(source, appId)
    local ok, result = canOpen(source, appId)
    return ok, result
end)

exports('canOpen', canOpen)

lib.callback.register('nexus_tablet:server:getIllegalDashboard', function(source)
    source = tonumber(source)
    if not source or source <= 0 then return false, 'invalid_source' end
    if not rateLimit(source) then return false, 'rate_limited' end
    if not hasIllegalAccess(source) then return false, 'no_access' end

    local progress = getProgress(source)
    local gang = getGang(source)
    local assets = safeExport('nexus_gangs', 'getDashboardAssets', { locations = {}, garageVehicles = {} }, source)
    local members = safeExport('nexus_gangs', 'getDashboardMembers', { members = {}, permissions = {}, rank = 0, isBoss = false }, source)
    local gangAudit = safeExport('nexus_gangs', 'getDashboardAudit', {}, source)
    local operations = safeExport('nexus_operations', 'getDashboardOperations', { operations = {}, active = nil }, source)
    if listCount(operations.operations) == 0 then
        operations = safeExport('nexus_operations', 'getDashboardOperationsLite', operations, source)
    end
    local operationLogs = safeExport('nexus_operations', 'getDashboardOperationLogs', {}, source)
    local labs = safeExport('nexus_labs', 'getDashboardLabs', { labs = {}, logs = {} }, source)
    local laundering = safeExport('nexus_laundering', 'getDashboardLaundering', { locations = {}, logs = {} }, source)
    local zones = safeExport('nexus_territories', 'getDashboardZones', {})
    local airdrop = safeExport('nexus_territories', 'getActiveAirdrop', nil)

    return true, {
        identity = {
            callsign = 'NEXUS/CLANDESTINE',
            mode = 'illegal',
        },
        gang = gang,
        progress = {
            criminal = progress.criminal or {},
            crafting = progress.crafting or {},
        },
        assets = assets,
        members = members,
        contracts = { contracts = {}, active = nil },
        operations = operations,
        operationLogs = operationLogs,
        audit = {
            gang = gangAudit,
            operations = operationLogs,
            labs = labs.logs or {},
            laundering = laundering.logs or {},
        },
        labs = labs,
        laundering = laundering,
        markets = {},
        territories = zones,
        airdrop = airdrop,
    }
end)

lib.callback.register('nexus_tablet:server:getIllegalFallback', function(source)
    source = tonumber(source)
    if not source or source <= 0 then return false, 'invalid_source' end
    return true, fallbackDashboard(source)
end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    print('[nexus_tablet] shell modular cargado')
end)
