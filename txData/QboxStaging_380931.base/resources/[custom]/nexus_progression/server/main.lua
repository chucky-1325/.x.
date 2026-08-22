local function getPlayer(source)
    if GetResourceState('qbx_core') ~= 'started' then return nil end
    return exports.qbx_core:GetPlayer(source)
end

local function getCitizenId(source)
    local player = getPlayer(source)
    return player and player.PlayerData and player.PlayerData.citizenid or nil
end

local function normalizeRows(rows)
    local result = {}

    for domain, meta in pairs(NexusProgressionConfig.domains) do
        result[domain] = {
            domain = domain,
            label = meta.label,
            icon = meta.icon,
            color = meta.color,
            xp = 0,
            reputation = 0,
            level = 1,
            currentXp = 0,
            requiredXp = NexusProgressionUtils.getRequiredXp(1),
        }
    end

    for i = 1, #(rows or {}) do
        local row = rows[i]
        local level, currentXp, requiredXp = NexusProgressionUtils.resolveLevel(row.xp)
        local entry = result[row.domain]
        if entry then
            entry.xp = row.xp or 0
            entry.reputation = row.reputation or 0
            entry.level = level
            entry.currentXp = currentXp
            entry.requiredXp = requiredXp
        end
    end

    return result
end

local function getProgressionByCitizen(citizenid)
    if not citizenid then return {} end

    return normalizeRows(NexusProgressionFetch(citizenid))
end

exports('getProgressionByCitizen', getProgressionByCitizen)

local function isInteger(value)
    return type(value) == 'number' and value == math.floor(value)
end

local function rejectAward(resource, reason)
    if NexusProgressionConfig.debug then
        print(('[nexus_progression] reward rejected resource=%s reason=%s'):format(resource or 'unknown', reason))
    end

    return false
end

local function addProgression(citizenid, domain, xp, reputation)
    local invokingResource = GetInvokingResource()
    local resourceRules = invokingResource and NexusProgressionConfig.serverApi.writers[invokingResource]
    local limits = resourceRules and resourceRules[domain]

    if not limits then return rejectAward(invokingResource, 'unauthorized_writer') end
    if type(citizenid) ~= 'string' or #citizenid < 1 or #citizenid > 64 then
        return rejectAward(invokingResource, 'invalid_citizenid')
    end
    if not NexusProgressionUtils.isValidDomain(domain) then
        return rejectAward(invokingResource, 'invalid_domain')
    end
    if not isInteger(xp) or xp < 1 or xp > limits.maxXp then
        return rejectAward(invokingResource, 'invalid_xp')
    end
    if not isInteger(reputation) or reputation < 1 or reputation > limits.maxReputation then
        return rejectAward(invokingResource, 'invalid_reputation')
    end
    if not NexusProgressionIncrement(citizenid, domain, xp, reputation) then return false end

    local row = NexusProgressionFetchDomain(citizenid, domain)
    if row then
        local totalXp = tonumber(row.xp) or 0
        local level = NexusProgressionUtils.resolveLevel(totalXp)
        NexusProgressionSyncLevel(citizenid, domain, totalXp, level)
    end

    return true
end

exports('addProgression', addProgression)

lib.callback.register('nexus_progression:server:get', function(source)
    local citizenid = getCitizenId(source)
    return getProgressionByCitizen(citizenid)
end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    print('[nexus_progression] progresion persistente cargada')
end)
