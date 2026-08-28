local invites = {}
local registeredStashes = {}

local function notify(source, description, notifyType)
    if source == 0 then
        print(('[nexus_gangs] %s'):format(description))
        return
    end

    TriggerClientEvent('ox_lib:notify', source, {
        title = 'Bandas',
        description = description,
        type = notifyType or 'inform',
    })
end

-- NOTA: estos 4 bypasses son el gate GLOBAL de administrador migrado a
-- nexus_permissions. El sistema interno de permisos por rango de banda
-- (funcion hasPermission mas abajo, basada en rank.isBoss/rank.permissions)
-- es un mecanismo totalmente distinto y no se toca aqui.
local function hasGangCreateBypass(source)
    source = tonumber(source)
    if not source then return false end
    if source == 0 then return true end
    if GetResourceState('nexus_permissions') ~= 'started' then return false end
    return exports.nexus_permissions:hasPermission(source, 'nexus_gangs.gang_create')
end

local function hasMemberManageOverride(source)
    source = tonumber(source)
    if not source then return false end
    if source == 0 then return true end
    if GetResourceState('nexus_permissions') ~= 'started' then return false end
    return exports.nexus_permissions:hasPermission(source, 'nexus_gangs.member_manage_override')
end

local function hasGangMemberAdminBypass(source)
    source = tonumber(source)
    if not source then return false end
    if source == 0 then return true end
    if GetResourceState('nexus_permissions') ~= 'started' then return false end
    return exports.nexus_permissions:hasPermission(source, 'nexus_gangs.gang_member_admin')
end

local function hasReputationGrantBypass(source)
    source = tonumber(source)
    if not source then return false end
    if source == 0 then return true end
    if GetResourceState('nexus_permissions') ~= 'started' then return false end
    return exports.nexus_permissions:hasPermission(source, 'nexus_gangs.reputation_grant')
end

local function rateLimit(source)
    source = tonumber(source)
    if not source or source <= 0 then return false end
    if source == 0 then return true end
    if GetResourceState('nexus_bridge') ~= 'started' then return true end
    return exports.nexus_bridge:rateLimit(source, NexusGangsConfig.rateLimitBucket or 'default')
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

local function sanitizeName(value)
    local name = tostring(value or ''):lower():gsub('[^%w_%-]', '')
    if name == '' or #name > 64 then return nil end
    return name
end

local function sanitizeLabel(value)
    local label = tostring(value or ''):gsub('[%c]', ''):sub(1, 96)
    if label == '' then return nil end
    return label
end

local function getRank(rankLevel)
    return NexusGangsConfig.ranks[tonumber(rankLevel) or 0] or NexusGangsConfig.ranks[0]
end

local function getMemberBySource(source)
    local citizenid = getCitizenId(source)
    if not citizenid then return nil end
    return NexusGangsFetchMember(citizenid)
end

-- Puramente el sistema interno de permisos por rango de banda -- SIN bypass
-- de admin embebido. El export publico 'hasGangPermission' llama a esta
-- funcion directamente, asi que un bypass aqui se filtraria a cualquier
-- consumidor futuro de ese export con cualquier string de permiso. El
-- bypass de nexus_permissions.member_manage_override se aplica de forma
-- explicita solo en los 2 call sites reales que lo necesitan: invite (mas
-- abajo) y canManageTarget (ya lo hacia de forma explicita, sin pasar por
-- esta funcion).
local function hasPermission(source, permission)
    local member = getMemberBySource(source)
    if not member then return false end

    local rank = getRank(member.rank_level)
    return rank.isBoss == true or (rank.permissions and rank.permissions[permission] == true)
end

local function tableContains(list, value)
    if not list then return false end
    for i = 1, #list do
        if list[i] == value then return true end
    end
    return false
end

local function getAssetLocation(locationId, gangName)
    local locations = NexusGangsConfig.assets and NexusGangsConfig.assets.locations or {}
    for i = 1, #locations do
        local location = locations[i]
        if (not locationId or location.id == locationId) and tableContains(location.gangs, gangName) then
            return location
        end
    end
    return nil
end

local function getStashId(gangName, locationId)
    return ('nexus_gang_%s_%s'):format(gangName, locationId)
end

local function registerGangStash(gangName, location)
    if GetResourceState('ox_inventory') ~= 'started' then return false end
    if not NexusGangsConfig.assets or not NexusGangsConfig.assets.stash.enabled then return false end

    local stashId = getStashId(gangName, location.id)
    if registeredStashes[stashId] then return true, stashId end

    exports.ox_inventory:RegisterStash(
        stashId,
        ('%s - %s'):format(location.label or 'Safehouse', gangName),
        NexusGangsConfig.assets.stash.slots or 80,
        NexusGangsConfig.assets.stash.weight or 250000,
        false,
        nil,
        location.stash
    )

    registeredStashes[stashId] = true
    return true, stashId
end

local function getNearbyAssetLocation(source, gangName, locationId, pointType)
    local location = getAssetLocation(locationId, gangName)
    if not location then return nil, 'invalid_location' end

    local ped = GetPlayerPed(source)
    local coords = ped and GetEntityCoords(ped)
    local target = location[pointType]
    if not coords or not target then return nil, 'invalid_point' end

    local targetCoords = pointType == 'garage' and vector3(target.x, target.y, target.z) or target
    local distance = #(coords - targetCoords)
    local maxDistance = (NexusGangsConfig.assets and NexusGangsConfig.assets.interactDistance or 2.0) + 1.5
    if distance > maxDistance then return nil, 'too_far' end

    return location
end

local function getGarageVehicle(model)
    local vehicles = NexusGangsConfig.assets and NexusGangsConfig.assets.garage.vehicles or {}
    for i = 1, #vehicles do
        if vehicles[i].model == model then return vehicles[i] end
    end
    return nil
end

local function normalizePlate(plate)
    return tostring(plate or ''):upper():gsub('%s+', ''):sub(1, 16)
end

local function generateGangPlate(gangName)
    local prefix = NexusGangsConfig.assets and NexusGangsConfig.assets.garage and NexusGangsConfig.assets.garage.platePrefix or 'GANG'
    local tag = tostring(gangName or 'G'):upper():gsub('[^%w]', ''):sub(1, 3)
    for _ = 1, 20 do
        local plate = normalizePlate(('%s%s%s'):format(prefix, tag, math.random(100, 999)))
        if not NexusGangsPlateExists(plate) then return plate end
    end
    return normalizePlate(('%s%s%s'):format(prefix, tag, math.random(1000, 9999)))
end

local function publicVec3(coords)
    if not coords then return nil end
    return { x = coords.x, y = coords.y, z = coords.z }
end

local function publicVec4(coords)
    if not coords then return nil end
    return { x = coords.x, y = coords.y, z = coords.z, w = coords.w }
end

local function buildGangData(member)
    if not member then
        return {
            name = 'none',
            label = 'Sin banda',
            tag = 'NONE',
            rank = 0,
            rankLabel = 'Civil',
            isBoss = false,
            permissions = {},
        }
    end

    local rank = getRank(member.rank_level)
    return {
        name = member.gang_name,
        label = member.label,
        tag = member.tag,
        color = member.color,
        reputation = tonumber(member.reputation) or 0,
        rank = tonumber(member.rank_level) or 0,
        rankLabel = rank.label,
        isBoss = rank.isBoss == true,
        permissions = rank.permissions or {},
    }
end

local function syncQboxGang(source)
    if not NexusGangsConfig.syncQboxRuntime then return end
    if GetResourceState('qbx_core') ~= 'started' then return end

    local member = getMemberBySource(source)
    local data = buildGangData(member)
    local gangData = {
        name = data.name,
        label = data.label,
        isboss = data.isBoss,
        bankAuth = data.permissions.manage == true,
        grade = {
            name = data.rankLabel,
            level = data.rank,
        },
    }

    exports.qbx_core:SetPlayerData(source, 'gang', gangData)
    TriggerEvent('QBCore:Server:OnGangUpdate', source, gangData)
    TriggerClientEvent('QBCore:Client:OnGangUpdate', source, gangData)
end

local function setMember(actorSource, targetSource, gangName, rankLevel, action)
    local targetCitizenid = getCitizenId(targetSource)
    if not targetCitizenid then return false, 'no_target_citizenid' end
    if not NexusGangsFetchGang(gangName) then return false, 'invalid_gang' end

    NexusGangsSetMember(targetCitizenid, gangName, tonumber(rankLevel) or 0)
    NexusGangsLog({
        gangName = gangName,
        actor = getCitizenId(actorSource),
        target = targetCitizenid,
        action = action or 'set_member',
        metadata = { rank = tonumber(rankLevel) or 0 },
    })
    syncQboxGang(targetSource)
    return true
end

local function removeMember(actorSource, targetSource, action)
    local targetCitizenid = getCitizenId(targetSource)
    if not targetCitizenid then return false, 'no_target_citizenid' end

    local member = NexusGangsFetchMember(targetCitizenid)
    NexusGangsRemoveMember(targetCitizenid)
    NexusGangsLog({
        gangName = member and member.gang_name or nil,
        actor = getCitizenId(actorSource),
        target = targetCitizenid,
        action = action or 'remove_member',
    })
    syncQboxGang(targetSource)
    return true
end

local function canManageTarget(actorSource, targetSource, permission)
    local actor = getMemberBySource(actorSource)
    local target = getMemberBySource(targetSource)
    if not actor or not target then return false, 'no_gang' end
    if actor.gang_name ~= target.gang_name then return false, 'different_gang' end
    if actorSource == targetSource then return false, 'self_target' end

    if not hasMemberManageOverride(actorSource) and not hasPermission(actorSource, permission) then return false, 'no_permission' end

    local actorRank = tonumber(actor.rank_level) or 0
    local targetRank = tonumber(target.rank_level) or 0
    if not hasMemberManageOverride(actorSource) and targetRank >= actorRank then return false, 'rank_too_high' end

    return true, actor, target
end

local function createGang(source, name, label, tag, color)
    local gangName = sanitizeName(name)
    local gangLabel = sanitizeLabel(label)
    local gangTag = tostring(tag or gangName or ''):upper():gsub('[^%w]', ''):sub(1, 12)
    if not gangName or not gangLabel or gangTag == '' then return false, 'invalid_data' end

    local ok, result = pcall(function()
        return NexusGangsCreateGang({
            name = gangName,
            label = gangLabel,
            tag = gangTag,
            color = tostring(color or NexusGangsConfig.defaultColor):sub(1, 16),
            reputation = NexusGangsConfig.defaultReputation or 0,
            createdBy = getCitizenId(source),
        })
    end)

    if not ok or not result then return false, 'exists_or_sql' end

    NexusGangsLog({
        gangName = gangName,
        actor = getCitizenId(source),
        action = 'create_gang',
        metadata = { label = gangLabel, tag = gangTag },
    })

    return true, gangName
end

exports('getPlayerGang', function(source)
    return buildGangData(getMemberBySource(source))
end)

exports('isGangMember', function(source, gangName)
    local member = getMemberBySource(source)
    return member and member.gang_name == gangName or false
end)

exports('getGangRank', function(source)
    local member = getMemberBySource(source)
    return member and tonumber(member.rank_level) or 0
end)

exports('hasGangPermission', function(source, permission)
    return hasPermission(source, permission)
end)

local function buildAssetsPayload(source)
    source = tonumber(source)
    if not source or source <= 0 then return { gang = buildGangData(nil), locations = {}, garageVehicles = {} } end

    local member = getMemberBySource(source)
    if not member then return { gang = buildGangData(nil), locations = {}, garageVehicles = {} } end

    local gang = buildGangData(member)
    local rankLevel = tonumber(member.rank_level) or 0
    local locations = {}
    local configLocations = NexusGangsConfig.assets and NexusGangsConfig.assets.locations or {}

    for i = 1, #configLocations do
        local location = configLocations[i]
        if tableContains(location.gangs, member.gang_name) then
            locations[#locations + 1] = {
                id = location.id,
                label = location.label,
                stash = publicVec3(location.stash),
                garage = publicVec4(location.garage),
                canStash = rankLevel >= (NexusGangsConfig.assets.stash.minRank or 0),
                canGarage = rankLevel >= (NexusGangsConfig.assets.garage.minRank or 0),
            }
        end
    end

    return {
        gang = gang,
        locations = locations,
        garageVehicles = NexusGangsConfig.assets.garage.vehicles or {},
        persistedVehicles = NexusGangsFetchVehicles(member.gang_name),
    }
end

exports('getDashboardAssets', buildAssetsPayload)

exports('getPrimaryStashId', function(source)
    source = tonumber(source)
    if not source or source <= 0 then return nil end

    local member = getMemberBySource(source)
    if not member then return nil end

    local location = getAssetLocation(nil, member.gang_name)
    if not location or not location.stash then return nil end

    local ok, stashId = registerGangStash(member.gang_name, location)
    return ok and stashId or nil
end)

exports('getDashboardMembers', function(source)
    source = tonumber(source)
    if not source or source <= 0 then return { members = {}, permissions = {}, rank = 0, isBoss = false } end

    local member = getMemberBySource(source)
    if not member then return { members = {}, permissions = {}, rank = 0, isBoss = false } end

    local actorRank = getRank(member.rank_level)
    local members = NexusGangsFetchMembers(member.gang_name)
    for i = 1, #members do
        local rank = getRank(members[i].rank_level)
        members[i].rank_label = rank.label
        members[i].is_boss = rank.isBoss == true
    end

    return {
        members = members,
        permissions = actorRank.permissions or {},
        rank = tonumber(member.rank_level) or 0,
        rankLabel = actorRank.label,
        isBoss = actorRank.isBoss == true,
    }
end)

exports('getDashboardAudit', function(source)
    source = tonumber(source)
    if not source or source <= 0 then return {} end

    local member = getMemberBySource(source)
    if not member then return {} end

    return NexusGangsFetchLogs(member.gang_name, 12)
end)

RegisterNetEvent('nexus_gangs:server:adminAddGangReputation', function(amount)
    local src = source
    if not hasReputationGrantBypass(src) then return notify(src, 'No tienes permiso para reputacion de banda.', 'error') end

    local member = getMemberBySource(src)
    if not member then return notify(src, 'No perteneces a una banda NEXUS.', 'error') end

    local value = math.floor(tonumber(amount) or 0)
    if value == 0 then return notify(src, 'Cantidad invalida.', 'error') end
    if value > 100 then value = 100 end
    if value < -100 then value = -100 end

    if not NexusGangsAddReputation(member.gang_name, value) then
        return notify(src, 'No se pudo modificar reputacion.', 'error')
    end

    NexusGangsLog({
        gangName = member.gang_name,
        actor = getCitizenId(src),
        action = 'admin_gang_reputation',
        metadata = { amount = value },
    })

    local updated = NexusGangsFetchGang(member.gang_name)
    notify(src, ('%s reputacion %+d. Total: %s'):format(member.gang_name, value, updated and updated.reputation or 'n/a'), 'success')
    syncQboxGang(src)
end)

lib.callback.register('nexus_gangs:server:getGang', function(source)
    if not rateLimit(source) then return false, 'rate_limited' end

    local member = getMemberBySource(source)
    local gang = buildGangData(member)
    local members = {}

    if member then
        members = NexusGangsFetchMembers(member.gang_name)
        for i = 1, #members do
            local rank = getRank(members[i].rank_level)
            members[i].rank_label = rank.label
        end
    end

    return true, {
        gang = gang,
        members = members,
    }
end)

lib.callback.register('nexus_gangs:server:getAssets', function(source)
    if not rateLimit(source) then return false, 'rate_limited' end
    return true, buildAssetsPayload(source)
end)

lib.callback.register('nexus_gangs:server:openStash', function(source, locationId)
    if not rateLimit(source) then return false, 'rate_limited' end
    if GetResourceState('ox_inventory') ~= 'started' then return false, 'inventory_offline' end

    local member = getMemberBySource(source)
    if not member then return false, 'no_gang' end
    if (tonumber(member.rank_level) or 0) < (NexusGangsConfig.assets.stash.minRank or 0) then return false, 'no_rank' end

    local location, reason = getNearbyAssetLocation(source, member.gang_name, locationId, 'stash')
    if not location then return false, reason end

    local ok, stashId = registerGangStash(member.gang_name, location)
    if not ok then return false, 'stash_failed' end

    NexusGangsLog({
        gangName = member.gang_name,
        actor = getCitizenId(source),
        action = 'open_gang_stash',
        metadata = { location = location.id },
    })

    return true, stashId
end)

lib.callback.register('nexus_gangs:server:requestVehicle', function(source, locationId, model)
    if not rateLimit(source) then return false, 'rate_limited' end

    local member = getMemberBySource(source)
    if not member then return false, 'no_gang' end
    if (tonumber(member.rank_level) or 0) < (NexusGangsConfig.assets.garage.minRank or 0) then return false, 'no_rank' end

    local vehicle = getGarageVehicle(tostring(model or ''))
    if not vehicle then return false, 'invalid_vehicle' end
    if (tonumber(member.rank_level) or 0) < (vehicle.minRank or 0) then return false, 'vehicle_rank' end

    local location, reason = getNearbyAssetLocation(source, member.gang_name, locationId, 'garage')
    if not location then return false, reason end

    local citizenid = getCitizenId(source)
    local storedVehicle = NexusGangsFetchStoredVehicle(member.gang_name, vehicle.model, location.id)
    local plate = storedVehicle and storedVehicle.plate or nil
    local reused = false

    if storedVehicle then
        reused = NexusGangsSetVehicleOutById(storedVehicle.id, citizenid, {
            source = 'garage_respawn',
            location = location.id,
        })
        if not reused then return false, 'vehicle_state_changed' end
    else
        local maxPerModel = NexusGangsConfig.assets and NexusGangsConfig.assets.garage and NexusGangsConfig.assets.garage.maxPerModel or 2
        local currentCount = NexusGangsCountVehiclesByModel(member.gang_name, vehicle.model)
        if currentCount >= maxPerModel then return false, 'fleet_limit' end

        plate = generateGangPlate(member.gang_name)
        NexusGangsCreateVehicle({
            gangName = member.gang_name,
            locationId = location.id,
            model = vehicle.model,
            label = vehicle.label,
            plate = plate,
            lastDriver = citizenid,
            metadata = { source = 'garage_spawn' },
        })
    end

    NexusGangsLog({
        gangName = member.gang_name,
        actor = citizenid,
        action = 'spawn_gang_vehicle',
        metadata = { location = location.id, model = vehicle.model, plate = plate, reused = reused },
    })

    return true, {
        model = vehicle.model,
        label = vehicle.label,
        spawn = publicVec4(location.garage),
        plate = plate,
    }
end)

lib.callback.register('nexus_gangs:server:storeVehicle', function(source, locationId, plate, model)
    if not rateLimit(source) then return false, 'rate_limited' end

    local member = getMemberBySource(source)
    if not member then return false, 'no_gang' end
    if (tonumber(member.rank_level) or 0) < (NexusGangsConfig.assets.garage.minRank or 0) then return false, 'no_rank' end

    local location, reason = getNearbyAssetLocation(source, member.gang_name, locationId, 'garage')
    if not location then return false, reason end

    local cleanPlate = normalizePlate(plate)
    if cleanPlate == '' then return false, 'invalid_plate' end

    local ok = NexusGangsSetVehicleStateByPlate(member.gang_name, cleanPlate, 'stored', getCitizenId(source), {
        location = location.id,
        model = tostring(model or ''),
    })
    if not ok then return false, 'not_gang_vehicle' end

    NexusGangsLog({
        gangName = member.gang_name,
        actor = getCitizenId(source),
        action = 'store_gang_vehicle',
        metadata = { location = location.id, plate = cleanPlate, model = tostring(model or '') },
    })

    return true
end)

RegisterNetEvent('nexus_gangs:server:invite', function(targetId)
    local src = source
    if not rateLimit(src) then return end
    if not hasMemberManageOverride(src) and not hasPermission(src, 'invite') then return notify(src, 'No tienes permiso para invitar.', 'error') end

    local target = tonumber(targetId)
    if not target or not GetPlayerName(target) then return notify(src, 'Jugador no valido.', 'error') end

    local member = getMemberBySource(src)
    if not member then return notify(src, 'No perteneces a una banda.', 'error') end

    invites[target] = {
        gangName = member.gang_name,
        rank = 0,
        invitedBy = src,
        expiresAt = os.time() + 120,
    }

    notify(src, 'Invitacion enviada.', 'success')
    notify(target, ('Invitacion recibida: %s. Usa /gangaccept'):format(member.label), 'inform')
end)

RegisterNetEvent('nexus_gangs:server:setMemberRank', function(targetId, rankLevel)
    local src = source
    if not rateLimit(src) then return end

    local target = tonumber(targetId)
    local newRank = tonumber(rankLevel)
    if not target or not GetPlayerName(target) or newRank == nil then
        return notify(src, 'Datos invalidos.', 'error')
    end

    local ok, actorOrReason, targetMember = canManageTarget(src, target, 'promote')
    if not ok then return notify(src, ('No puedes cambiar rango: %s'):format(actorOrReason), 'error') end

    local actor = actorOrReason
    local actorRank = tonumber(actor.rank_level) or 0
    local maxRank = hasMemberManageOverride(src) and 99 or (actorRank - 1)
    newRank = math.floor(math.max(0, math.min(newRank, maxRank)))

    local result, reason = setMember(src, target, actor.gang_name, newRank, 'set_rank')
    if not result then return notify(src, ('No se pudo cambiar rango: %s'):format(reason), 'error') end

    NexusGangsLog({
        gangName = actor.gang_name,
        actor = getCitizenId(src),
        target = targetMember.citizenid,
        action = 'tablet_set_rank',
        metadata = { rank = newRank },
    })

    notify(src, ('Rango actualizado a %s.'):format(newRank), 'success')
    notify(target, ('Tu rango de banda fue actualizado a %s.'):format(newRank), 'inform')
end)

RegisterNetEvent('nexus_gangs:server:kickMember', function(targetId)
    local src = source
    if not rateLimit(src) then return end

    local target = tonumber(targetId)
    if not target or not GetPlayerName(target) then return notify(src, 'Jugador invalido.', 'error') end

    local ok, actorOrReason, targetMember = canManageTarget(src, target, 'kick')
    if not ok then return notify(src, ('No puedes expulsar: %s'):format(actorOrReason), 'error') end

    local actor = actorOrReason
    local result, reason = removeMember(src, target, 'tablet_kick')
    if not result then return notify(src, ('No se pudo expulsar: %s'):format(reason), 'error') end

    NexusGangsLog({
        gangName = actor.gang_name,
        actor = getCitizenId(src),
        target = targetMember.citizenid,
        action = 'tablet_kick',
    })

    notify(src, 'Miembro expulsado.', 'success')
    notify(target, 'Fuiste expulsado de la banda.', 'warning')
end)

local function acceptInvite(src)
    if not rateLimit(src) then return end

    local invite = invites[src]
    if not invite or os.time() > invite.expiresAt then
        invites[src] = nil
        return notify(src, 'No tienes invitacion activa.', 'error')
    end

    local ok, reason = setMember(invite.invitedBy or src, src, invite.gangName, invite.rank, 'accept_invite')
    invites[src] = nil
    if not ok then return notify(src, ('No se pudo unir: %s'):format(reason), 'error') end

    notify(src, 'Te uniste a la banda.', 'success')
end

RegisterNetEvent('nexus_gangs:server:acceptInvite', function()
    acceptInvite(source)
end)

RegisterNetEvent('nexus_gangs:server:leave', function()
    local src = source
    if not rateLimit(src) then return end

    local member = getMemberBySource(src)
    if not member then return notify(src, 'No perteneces a una banda.', 'error') end
    if getRank(member.rank_level).isBoss then return notify(src, 'El lider no puede salir sin transferir liderazgo.', 'error') end

    removeMember(src, src, 'leave_gang')
    notify(src, 'Saliste de la banda.', 'inform')
end)

RegisterCommand(NexusGangsConfig.command, function(source)
    if source == 0 then return end
    TriggerClientEvent('nexus_gangs:client:open', source)
end, false)

RegisterCommand('gangaccept', function(source)
    if source == 0 then return end
    acceptInvite(source)
end, false)

RegisterCommand('gangcreate', function(source, args)
    if not hasGangCreateBypass(source) then return notify(source, 'No tienes permiso.', 'error') end

    local ok, result = createGang(source, args[1], args[2], args[3], args[4])
    if not ok then return notify(source, ('No se pudo crear banda: %s'):format(result), 'error') end
    notify(source, ('Banda creada: %s'):format(result), 'success')
end, false)

RegisterCommand('gangadd', function(source, args)
    if not hasGangMemberAdminBypass(source) then return notify(source, 'No tienes permiso.', 'error') end

    local target = tonumber(args[1])
    local gangName = sanitizeName(args[2])
    local rank = tonumber(args[3]) or 0
    if not target or not gangName then return notify(source, 'Uso: /gangadd id gang rank', 'error') end

    local ok, reason = setMember(source, target, gangName, rank, 'admin_add')
    if not ok then return notify(source, ('No se pudo asignar: %s'):format(reason), 'error') end
    notify(source, 'Miembro asignado.', 'success')
end, false)

RegisterCommand('gangremove', function(source, args)
    if not hasGangMemberAdminBypass(source) then return notify(source, 'No tienes permiso.', 'error') end

    local target = tonumber(args[1])
    if not target then return notify(source, 'Uso: /gangremove id', 'error') end

    local ok, reason = removeMember(source, target, 'admin_remove')
    if not ok then return notify(source, ('No se pudo quitar: %s'):format(reason), 'error') end
    notify(source, 'Miembro removido.', 'success')
end, false)

AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    local source = player and player.PlayerData and player.PlayerData.source
    if source then syncQboxGang(source) end
end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    NexusGangsEnsureTables()
    for _, playerId in ipairs(GetPlayers()) do
        syncQboxGang(tonumber(playerId))
    end
    print('[nexus_gangs] bandas cargadas')
end)
