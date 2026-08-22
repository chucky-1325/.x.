local function createTables()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS nexus_lab_logs (
            id INT NOT NULL AUTO_INCREMENT,
            lab_id VARCHAR(64) NOT NULL,
            zone_id VARCHAR(64) NOT NULL,
            gang_name VARCHAR(64) NOT NULL,
            citizenid VARCHAR(64) NOT NULL,
            player_name VARCHAR(96) NULL,
            status VARCHAR(24) NOT NULL,
            risk INT NOT NULL DEFAULT 0,
            xp INT NOT NULL DEFAULT 0,
            reputation INT NOT NULL DEFAULT 0,
            influence INT NOT NULL DEFAULT 0,
            police_alert TINYINT(1) NOT NULL DEFAULT 0,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            KEY idx_lab_logs_lab (lab_id),
            KEY idx_lab_logs_gang (gang_name),
            KEY idx_lab_logs_zone (zone_id),
            KEY idx_lab_logs_created (created_at)
        )
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS nexus_lab_cooldowns (
            gang_name VARCHAR(64) NOT NULL,
            lab_id VARCHAR(64) NOT NULL,
            available_at BIGINT NOT NULL DEFAULT 0,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (gang_name, lab_id),
            KEY idx_lab_cd_available (available_at)
        )
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS nexus_lab_state (
            gang_name VARCHAR(64) NOT NULL,
            lab_id VARCHAR(64) NOT NULL,
            level INT NOT NULL DEFAULT 1,
            condition_value INT NOT NULL DEFAULT 100,
            queue_until BIGINT NOT NULL DEFAULT 0,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (gang_name, lab_id),
            KEY idx_lab_state_queue (queue_until)
        )
    ]])
end

function NexusLabsLog(data)
    MySQL.insert.await([[
        INSERT INTO nexus_lab_logs
            (lab_id, zone_id, gang_name, citizenid, player_name, status, risk, xp, reputation, influence, police_alert)
        VALUES
            (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        data.labId,
        data.zoneId,
        data.gangName,
        data.citizenid,
        data.playerName,
        data.status,
        data.risk or 0,
        data.xp or 0,
        data.reputation or 0,
        data.influence or 0,
        data.policeAlert and 1 or 0,
    })
end

function NexusLabsGetCooldown(gangName, labId)
    local row = MySQL.single.await([[
        SELECT available_at
        FROM nexus_lab_cooldowns
        WHERE gang_name = ? AND lab_id = ?
    ]], { gangName, labId })

    local availableAt = row and tonumber(row.available_at) or 0
    local remaining = availableAt - os.time()
    return remaining > 0 and remaining or 0
end

function NexusLabsSetCooldown(gangName, labId, seconds)
    local duration = tonumber(seconds) or 0
    if duration <= 0 then return end

    MySQL.query.await([[
        INSERT INTO nexus_lab_cooldowns (gang_name, lab_id, available_at)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE available_at = VALUES(available_at)
    ]], { gangName, labId, os.time() + duration })
end

function NexusLabsGetState(gangName, labId)
    if not gangName or gangName == '' or gangName == 'none' then
        return { level = 1, condition = 100, queueRemaining = 0 }
    end

    local row = MySQL.single.await([[
        SELECT level, condition_value, queue_until
        FROM nexus_lab_state
        WHERE gang_name = ? AND lab_id = ?
    ]], { gangName, labId })

    if not row then
        MySQL.query.await([[
            INSERT IGNORE INTO nexus_lab_state (gang_name, lab_id, level, condition_value, queue_until)
            VALUES (?, ?, 1, 100, 0)
        ]], { gangName, labId })

        return { level = 1, condition = 100, queueRemaining = 0 }
    end

    local queueUntil = tonumber(row.queue_until) or 0
    return {
        level = math.max(1, tonumber(row.level) or 1),
        condition = math.max(0, math.min(100, tonumber(row.condition_value) or 100)),
        queueRemaining = math.max(0, queueUntil - os.time()),
        queueUntil = queueUntil,
    }
end

function NexusLabsSetQueue(gangName, labId, seconds)
    local queueUntil = os.time() + math.max(0, tonumber(seconds) or 0)
    MySQL.query.await([[
        INSERT INTO nexus_lab_state (gang_name, lab_id, level, condition_value, queue_until)
        VALUES (?, ?, 1, 100, ?)
        ON DUPLICATE KEY UPDATE queue_until = VALUES(queue_until)
    ]], { gangName, labId, queueUntil })
    return queueUntil
end

function NexusLabsClearQueue(gangName, labId)
    MySQL.query.await([[
        INSERT INTO nexus_lab_state (gang_name, lab_id, level, condition_value, queue_until)
        VALUES (?, ?, 1, 100, 0)
        ON DUPLICATE KEY UPDATE queue_until = 0
    ]], { gangName, labId })
end

function NexusLabsApplyWear(gangName, labId, decay)
    local amount = math.max(0, tonumber(decay) or 0)
    if amount <= 0 then return end

    MySQL.query.await([[
        INSERT INTO nexus_lab_state (gang_name, lab_id, level, condition_value, queue_until)
        VALUES (?, ?, 1, GREATEST(0, 100 - ?), 0)
        ON DUPLICATE KEY UPDATE condition_value = GREATEST(0, condition_value - ?)
    ]], { gangName, labId, amount, amount })
end

function NexusLabsRepairCondition(gangName, labId, amount)
    local value = math.max(0, tonumber(amount) or 0)
    if value <= 0 then return end

    MySQL.query.await([[
        INSERT INTO nexus_lab_state (gang_name, lab_id, level, condition_value, queue_until)
        VALUES (?, ?, 1, LEAST(100, ?), 0)
        ON DUPLICATE KEY UPDATE condition_value = LEAST(100, condition_value + ?)
    ]], { gangName, labId, value, value })
end

function NexusLabsDamageCondition(gangName, labId, amount)
    local value = math.max(0, tonumber(amount) or 0)
    if value <= 0 then return end

    MySQL.query.await([[
        INSERT INTO nexus_lab_state (gang_name, lab_id, level, condition_value, queue_until)
        VALUES (?, ?, 1, GREATEST(0, 100 - ?), 0)
        ON DUPLICATE KEY UPDATE condition_value = GREATEST(0, condition_value - ?)
    ]], { gangName, labId, value, value })
end

function NexusLabsUpgrade(gangName, labId, nextLevel)
    MySQL.query.await([[
        INSERT INTO nexus_lab_state (gang_name, lab_id, level, condition_value, queue_until)
        VALUES (?, ?, ?, 100, 0)
        ON DUPLICATE KEY UPDATE level = GREATEST(level, VALUES(level)), condition_value = 100
    ]], { gangName, labId, nextLevel })
end

function NexusLabsGetRecentLogs(gangName, limit)
    if not gangName or gangName == '' or gangName == 'none' then return {} end

    return MySQL.query.await([[
        SELECT lab_id, zone_id, status, risk, xp, reputation, influence, police_alert, created_at
        FROM nexus_lab_logs
        WHERE gang_name = ?
        ORDER BY id DESC
        LIMIT ?
    ]], { gangName, math.min(tonumber(limit) or 8, 20) }) or {}
end

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    createTables()
end)
