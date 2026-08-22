NexusProgressionUtils = {}

function NexusProgressionUtils.getRequiredXp(level)
    level = tonumber(level) or 1
    local base = NexusProgressionConfig.xpBase
    local growth = NexusProgressionConfig.xpGrowth

    return math.floor(base * (growth ^ math.max(level - 1, 0)))
end

function NexusProgressionUtils.resolveLevel(xp)
    xp = tonumber(xp) or 0

    local level = 1
    while level < NexusProgressionConfig.maxLevel do
        local required = NexusProgressionUtils.getRequiredXp(level)
        if xp < required then break end
        xp = xp - required
        level = level + 1
    end

    return level, xp, NexusProgressionUtils.getRequiredXp(level)
end

function NexusProgressionUtils.isValidDomain(domain)
    return type(domain) == 'string' and NexusProgressionConfig.domains[domain] ~= nil
end
