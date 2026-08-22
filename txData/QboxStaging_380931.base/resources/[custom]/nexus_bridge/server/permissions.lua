local function getPlayer(source)
    if GetResourceState('qbx_core') ~= 'started' then return nil end
    return exports.qbx_core:GetPlayer(source)
end

local function hasEntry(container, name, grade)
    if not name or type(container) ~= 'table' then return false end

    local minGrade = container[name]
    if minGrade == nil then return false end

    return tonumber(grade or 0) >= tonumber(minGrade or 0)
end

local function hasType(container, groupType)
    if not groupType or type(container) ~= 'table' then return false end
    return container[groupType] == true
end

function NexusHasAccess(source, permissionGroup)
    local groups = NexusBridgeConfig.permissionGroups
    local rule = groups and groups[permissionGroup]
    if not rule then return false end

    local player = getPlayer(source)
    if not player or not player.PlayerData then return false end

    local job = player.PlayerData.job or {}
    local gang = player.PlayerData.gang or {}

    return hasType(rule.jobTypes, job.type)
        or hasEntry(rule.jobs, job.name, job.grade and job.grade.level)
        or hasEntry(rule.gangs, gang.name, gang.grade and gang.grade.level)
end

exports('hasAccess', NexusHasAccess)

exports('getPlayerData', function(source)
    local player = getPlayer(source)
    return player and NexusBridgeUtils.copy(player.PlayerData) or nil
end)
