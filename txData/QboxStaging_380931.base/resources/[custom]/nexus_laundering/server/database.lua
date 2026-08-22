local function createTables()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS nexus_laundering_logs (
            id INT NOT NULL AUTO_INCREMENT,
            citizenid VARCHAR(64) NOT NULL,
            player_name VARCHAR(96) NULL,
            gang_name VARCHAR(64) NULL,
            location_id VARCHAR(64) NOT NULL,
            zone_id VARCHAR(64) NULL,
            dirty_amount INT NOT NULL DEFAULT 0,
            clean_amount INT NOT NULL DEFAULT 0,
            commission INT NOT NULL DEFAULT 0,
            risk INT NOT NULL DEFAULT 0,
            police_alert TINYINT(1) NOT NULL DEFAULT 0,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            KEY idx_launder_citizenid (citizenid),
            KEY idx_launder_gang (gang_name),
            KEY idx_launder_location (location_id),
            KEY idx_launder_created (created_at)
        )
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS nexus_laundering_cooldowns (
            citizenid VARCHAR(64) NOT NULL,
            location_id VARCHAR(64) NOT NULL,
            available_at BIGINT NOT NULL DEFAULT 0,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (citizenid, location_id),
            KEY idx_launder_cd_available (available_at)
        )
    ]])
end

function NexusLaunderingLog(data)
    MySQL.insert.await([[
        INSERT INTO nexus_laundering_logs
            (citizenid, player_name, gang_name, location_id, zone_id, dirty_amount, clean_amount, commission, risk, police_alert)
        VALUES
            (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        data.citizenid,
        data.playerName,
        data.gangName,
        data.locationId,
        data.zoneId,
        data.dirtyAmount or 0,
        data.cleanAmount or 0,
        data.commission or 0,
        data.risk or 0,
        data.policeAlert and 1 or 0,
    })
end

function NexusLaunderingGetCooldown(citizenid, locationId)
    local row = MySQL.single.await([[
        SELECT available_at
        FROM nexus_laundering_cooldowns
        WHERE citizenid = ? AND location_id = ?
    ]], { citizenid, locationId })

    local availableAt = row and tonumber(row.available_at) or 0
    local remaining = availableAt - os.time()
    return remaining > 0 and remaining or 0
end

function NexusLaunderingSetCooldown(citizenid, locationId, seconds)
    local duration = tonumber(seconds) or 0
    if duration <= 0 then return end

    MySQL.query.await([[
        INSERT INTO nexus_laundering_cooldowns (citizenid, location_id, available_at)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE available_at = VALUES(available_at)
    ]], { citizenid, locationId, os.time() + duration })
end

function NexusLaunderingGetRecentLogs(citizenid, limit)
    if not citizenid then return {} end

    return MySQL.query.await([[
        SELECT location_id, zone_id, dirty_amount, clean_amount, commission, risk, police_alert, created_at
        FROM nexus_laundering_logs
        WHERE citizenid = ?
        ORDER BY id DESC
        LIMIT ?
    ]], { citizenid, math.min(tonumber(limit) or 8, 20) }) or {}
end

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    createTables()
end)
