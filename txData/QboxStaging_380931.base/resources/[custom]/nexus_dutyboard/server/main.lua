local cooldowns = {}

local function dependenciesReady()
    return GetResourceState('qbx_core') == 'started'
        and GetResourceState('ox_target') == 'started'
end

local function rateLimit(source, bucket)
    if GetResourceState('nexus_bridge') == 'started' then
        return exports.nexus_bridge:rateLimit(source, bucket)
    end
    return NexusDutyboardSecurityFallback.rateLimit(source, bucket)
end

local function passesLocalCooldown(source)
    local now = GetGameTimer()
    local last = cooldowns[source]

    if last and now - last < NexusDutyboardConfig.localCooldownMs then
        return false
    end

    cooldowns[source] = now
    return true
end

local function notifyDuty(source, onDuty)
    TriggerClientEvent('nexus_dutyboard:client:notify', source, {
        description = onDuty and 'Has fichado: de servicio.' or 'Has fichado: fuera de servicio.',
        type = 'success',
    })
end

lib.callback.register('nexus_dutyboard:server:getStatus', function(source)
    if not dependenciesReady() then return nil end

    local player = exports.qbx_core:GetPlayer(source)
    if not player or not player.PlayerData then return nil end

    local job = player.PlayerData.job
    if not job or job.name ~= NexusDutyboardConfig.job then
        return { eligible = false }
    end

    local snapshot = GetResourceState('nexus_contracts') == 'started'
        and exports.nexus_contracts:getDutyboardSnapshot(source)
        or nil

    return {
        eligible = true,
        onDuty = job.onduty or false,
        grade = job.grade and { name = job.grade.name, level = job.grade.level } or nil,
        lot = snapshot and snapshot.lot or nil,
        craft = snapshot and snapshot.craft or nil,
    }
end)

lib.callback.register('nexus_dutyboard:server:toggleDuty', function(source)
    if not dependenciesReady() then return false end

    local player = exports.qbx_core:GetPlayer(source)
    if not player or not player.PlayerData then return false end

    local job = player.PlayerData.job
    if not job or job.name ~= NexusDutyboardConfig.job then return false end

    local ped = GetPlayerPed(source)
    if ped == 0 then return false end

    local coords = GetEntityCoords(ped)
    local distance = #(coords - NexusDutyboardConfig.point)
    if distance > NexusDutyboardConfig.maxServerDistance then return false end

    if not passesLocalCooldown(source) then return false end
    if not rateLimit(source, NexusDutyboardConfig.rateLimitBucket) then return false end

    exports.qbx_core:SetJobDuty(source, not job.onduty)

    local updated = exports.qbx_core:GetPlayer(source)
    local onDuty = updated and updated.PlayerData.job.onduty or false
    notifyDuty(source, onDuty)

    return true, onDuty
end)

AddEventHandler('playerDropped', function()
    cooldowns[source] = nil
end)
