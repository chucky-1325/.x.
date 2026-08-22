local function createTables()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS nexus_operation_logs (
            id INT NOT NULL AUTO_INCREMENT,
            gang_name VARCHAR(64) NOT NULL,
            citizenid VARCHAR(64) NOT NULL,
            player_name VARCHAR(96) NULL,
            operation_id VARCHAR(64) NOT NULL,
            status VARCHAR(24) NOT NULL,
            reward_cash INT NOT NULL DEFAULT 0,
            reward_xp INT NOT NULL DEFAULT 0,
            reward_reputation INT NOT NULL DEFAULT 0,
            influence INT NOT NULL DEFAULT 0,
            police_alert TINYINT(1) NOT NULL DEFAULT 0,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            KEY idx_operation_gang (gang_name),
            KEY idx_operation_citizenid (citizenid),
            KEY idx_operation_id (operation_id),
            KEY idx_operation_created (created_at)
        )
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS nexus_operation_cooldowns (
            gang_name VARCHAR(64) NOT NULL,
            operation_id VARCHAR(64) NOT NULL,
            available_at BIGINT NOT NULL DEFAULT 0,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (gang_name, operation_id),
            KEY idx_operation_cd_available (available_at)
        )
    ]])
end

function NexusOperationsLog(data)
    MySQL.insert.await([[
        INSERT INTO nexus_operation_logs
            (gang_name, citizenid, player_name, operation_id, status, reward_cash, reward_xp, reward_reputation, influence, police_alert)
        VALUES
            (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        data.gangName,
        data.citizenid,
        data.playerName,
        data.operationId,
        data.status,
        data.cash or 0,
        data.xp or 0,
        data.reputation or 0,
        data.influence or 0,
        data.policeAlert and 1 or 0,
    })
end

function NexusOperationsGetCooldown(gangName, operationId)
    local row = MySQL.single.await([[
        SELECT available_at
        FROM nexus_operation_cooldowns
        WHERE gang_name = ? AND operation_id = ?
    ]], { gangName, operationId })

    local availableAt = row and tonumber(row.available_at) or 0
    local remaining = availableAt - os.time()
    return remaining > 0 and remaining or 0
end

function NexusOperationsSetCooldown(gangName, operationId, seconds)
    local duration = tonumber(seconds) or 0
    if duration <= 0 then return end

    MySQL.query.await([[
        INSERT INTO nexus_operation_cooldowns (gang_name, operation_id, available_at)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE available_at = VALUES(available_at)
    ]], { gangName, operationId, os.time() + duration })
end

function NexusOperationsGetRecentLogs(gangName, limit)
    if type(gangName) ~= 'string' or gangName == '' or gangName == 'none' then return {} end

    local rows = MySQL.query.await([[
        SELECT operation_id, status, reward_cash, reward_xp, reward_reputation, influence, police_alert, created_at
        FROM nexus_operation_logs
        WHERE gang_name = ?
        ORDER BY id DESC
        LIMIT ?
    ]], { gangName, math.min(tonumber(limit) or 8, 20) })

    return rows or {}
end

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    createTables()
end)
