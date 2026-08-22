function NexusProgressionFetch(citizenid)
    if not citizenid then return {} end

    return MySQL.query.await(
        'SELECT domain, xp, reputation, level FROM nexus_progression WHERE citizenid = ? ORDER BY domain',
        { citizenid }
    ) or {}
end

function NexusProgressionIncrement(citizenid, domain, xp, reputation)
    local affected = MySQL.update.await([[
        INSERT INTO nexus_progression (citizenid, domain, xp, reputation, level)
        VALUES (?, ?, ?, ?, 1)
        ON DUPLICATE KEY UPDATE
            xp = xp + VALUES(xp),
            reputation = reputation + VALUES(reputation)
    ]], { citizenid, domain, xp, reputation })

    return affected ~= nil
end

function NexusProgressionFetchDomain(citizenid, domain)
    return MySQL.single.await(
        'SELECT xp, reputation FROM nexus_progression WHERE citizenid = ? AND domain = ? LIMIT 1',
        { citizenid, domain }
    )
end

function NexusProgressionSyncLevel(citizenid, domain, xp, level)
    MySQL.update.await([[
        UPDATE nexus_progression
        SET level = ?
        WHERE citizenid = ? AND domain = ? AND xp = ?
    ]], { level, citizenid, domain, xp })
end
