local function columnExists(columnName)
    local row = MySQL.single.await([[
        SELECT COLUMN_NAME
        FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'nexus_dispatch_alerts'
          AND COLUMN_NAME = ?
        LIMIT 1
    ]], { columnName })

    return row ~= nil
end

local function indexExists(indexName)
    local row = MySQL.single.await([[
        SELECT INDEX_NAME
        FROM information_schema.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'nexus_dispatch_alerts'
          AND INDEX_NAME = ?
        LIMIT 1
    ]], { indexName })

    return row ~= nil
end

local function ensureColumn(columnName, definition)
    if columnExists(columnName) then return end
    MySQL.query.await(('ALTER TABLE nexus_dispatch_alerts ADD COLUMN %s %s'):format(columnName, definition))
end

local function ensureIndex(indexName, definition)
    if indexExists(indexName) then return end
    MySQL.query.await(('ALTER TABLE nexus_dispatch_alerts ADD INDEX %s %s'):format(indexName, definition))
end

function NexusDispatchEnsureDatabase()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS nexus_dispatch_alerts (
            id INT UNSIGNED NOT NULL AUTO_INCREMENT,
            alert_type VARCHAR(64) NOT NULL DEFAULT 'generic',
            title VARCHAR(96) NOT NULL DEFAULT 'Incidente',
            message VARCHAR(255) NOT NULL DEFAULT '',
            coords_x DOUBLE NULL,
            coords_y DOUBLE NULL,
            coords_z DOUBLE NULL,
            zone_id VARCHAR(64) NULL,
            source_resource VARCHAR(64) NULL,
            source_player INT NULL,
            citizenid VARCHAR(64) NULL,
            gang_name VARCHAR(64) NULL,
            risk INT NOT NULL DEFAULT 0,
            priority INT NOT NULL DEFAULT 1,
            status VARCHAR(24) NOT NULL DEFAULT 'open',
            assigned_citizenid VARCHAR(64) NULL,
            assigned_name VARCHAR(96) NULL,
            closed_by_citizenid VARCHAR(64) NULL,
            closed_by_name VARCHAR(96) NULL,
            closed_at TIMESTAMP NULL,
            close_result VARCHAR(64) NULL,
            close_notes TEXT NULL,
            operational_notes TEXT NULL,
            ais_case_id INT NULL,
            ais_case_number VARCHAR(64) NULL,
            updated_at TIMESTAMP NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            INDEX idx_dispatch_created (created_at),
            INDEX idx_dispatch_status (status),
            INDEX idx_dispatch_type (alert_type),
            INDEX idx_dispatch_zone (zone_id),
            INDEX idx_dispatch_gang (gang_name)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])

    ensureColumn('status', "VARCHAR(24) NOT NULL DEFAULT 'open'")
    ensureColumn('assigned_citizenid', 'VARCHAR(64) NULL')
    ensureColumn('assigned_name', 'VARCHAR(96) NULL')
    ensureColumn('closed_by_citizenid', 'VARCHAR(64) NULL')
    ensureColumn('closed_by_name', 'VARCHAR(96) NULL')
    ensureColumn('closed_at', 'TIMESTAMP NULL')
    ensureColumn('close_result', 'VARCHAR(64) NULL')
    ensureColumn('close_notes', 'TEXT NULL')
    ensureColumn('operational_notes', 'TEXT NULL')
    ensureColumn('ais_case_id', 'INT NULL')
    ensureColumn('ais_case_number', 'VARCHAR(64) NULL')
    ensureColumn('updated_at', 'TIMESTAMP NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP')
    ensureIndex('idx_dispatch_status', '(status)')

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS nexus_dispatch_units (
            id INT UNSIGNED NOT NULL AUTO_INCREMENT,
            alert_id INT UNSIGNED NOT NULL,
            citizenid VARCHAR(64) NOT NULL,
            officer_name VARCHAR(96) NOT NULL,
            unit_status VARCHAR(24) NOT NULL DEFAULT 'assigned',
            assigned_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            UNIQUE KEY uniq_dispatch_unit (alert_id, citizenid),
            INDEX idx_dispatch_units_alert (alert_id),
            INDEX idx_dispatch_units_status (unit_status)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
end

function NexusDispatchInsert(alert)
    return MySQL.insert.await([[
        INSERT INTO nexus_dispatch_alerts
            (alert_type, title, message, coords_x, coords_y, coords_z, zone_id, source_resource, source_player, citizenid, gang_name, risk, priority)
        VALUES
            (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        alert.type,
        alert.title,
        alert.message,
        alert.coords and alert.coords.x or nil,
        alert.coords and alert.coords.y or nil,
        alert.coords and alert.coords.z or nil,
        alert.zoneId,
        alert.sourceResource,
        alert.sourcePlayer,
        alert.citizenid,
        alert.gangName,
        alert.risk,
        alert.priority,
    })
end

function NexusDispatchRecent(limit)
    return MySQL.query.await([[
        SELECT
            id,
            alert_type AS type,
            title,
            message,
            coords_x AS x,
            coords_y AS y,
            coords_z AS z,
            zone_id AS zoneId,
            source_resource AS sourceResource,
            source_player AS sourcePlayer,
            citizenid,
            gang_name AS gangName,
            risk,
            priority,
            status,
            assigned_citizenid AS assignedCitizenid,
            assigned_name AS assignedName,
            closed_by_citizenid AS closedByCitizenid,
            closed_by_name AS closedByName,
            UNIX_TIMESTAMP(closed_at) AS closedAt,
            close_result AS closeResult,
            close_notes AS closeNotes,
            operational_notes AS operationalNotes,
            ais_case_id AS aisCaseId,
            ais_case_number AS aisCaseNumber,
            UNIX_TIMESTAMP(updated_at) AS updatedAt,
            UNIX_TIMESTAMP(created_at) AS createdAt
        FROM nexus_dispatch_alerts
        ORDER BY id DESC
        LIMIT ?
    ]], { limit })
end

function NexusDispatchUnits(alertIds)
    if not alertIds or #alertIds == 0 then return {} end

    local placeholders = {}
    for i = 1, #alertIds do
        placeholders[i] = '?'
    end

    local rows = MySQL.query.await(('SELECT alert_id AS alertId, citizenid, officer_name AS officerName, unit_status AS unitStatus, UNIX_TIMESTAMP(assigned_at) AS assignedAt, UNIX_TIMESTAMP(updated_at) AS updatedAt FROM nexus_dispatch_units WHERE alert_id IN (%s) ORDER BY assigned_at ASC'):format(table.concat(placeholders, ',')), alertIds)
    local grouped = {}

    for i = 1, #(rows or {}) do
        local row = rows[i]
        grouped[row.alertId] = grouped[row.alertId] or {}
        grouped[row.alertId][#grouped[row.alertId] + 1] = row
    end

    return grouped
end

function NexusDispatchGet(alertId)
    return MySQL.single.await([[
        SELECT
            id,
            alert_type AS type,
            title,
            message,
            coords_x AS x,
            coords_y AS y,
            coords_z AS z,
            zone_id AS zoneId,
            source_resource AS sourceResource,
            source_player AS sourcePlayer,
            citizenid,
            gang_name AS gangName,
            risk,
            priority,
            status,
            assigned_citizenid AS assignedCitizenid,
            assigned_name AS assignedName,
            closed_by_citizenid AS closedByCitizenid,
            closed_by_name AS closedByName,
            UNIX_TIMESTAMP(closed_at) AS closedAt,
            close_result AS closeResult,
            close_notes AS closeNotes,
            operational_notes AS operationalNotes,
            ais_case_id AS aisCaseId,
            ais_case_number AS aisCaseNumber,
            UNIX_TIMESTAMP(updated_at) AS updatedAt,
            UNIX_TIMESTAMP(created_at) AS createdAt
        FROM nexus_dispatch_alerts
        WHERE id = ?
        LIMIT 1
    ]], { alertId })
end

function NexusDispatchUpdate(alertId, status, officer, extra)
    extra = extra or {}

    if status == 'assigned' then
        return MySQL.update.await([[
            UPDATE nexus_dispatch_alerts
            SET status = ?, assigned_citizenid = ?, assigned_name = ?
            WHERE id = ? AND status <> 'closed'
        ]], { status, officer.citizenid, officer.name, alertId })
    end

    if status == 'closed' then
        return MySQL.update.await([[
            UPDATE nexus_dispatch_alerts
            SET status = ?, closed_by_citizenid = ?, closed_by_name = ?, closed_at = CURRENT_TIMESTAMP, close_result = ?, close_notes = ?
            WHERE id = ? AND status <> 'closed'
        ]], { status, officer.citizenid, officer.name, extra.result, extra.notes, alertId })
    end

    return MySQL.update.await([[
        UPDATE nexus_dispatch_alerts
        SET status = ?
        WHERE id = ? AND status <> 'closed'
    ]], { status, alertId })
end

function NexusDispatchAppendNote(alertId, note)
    return MySQL.update.await([[
        UPDATE nexus_dispatch_alerts
        SET operational_notes = CASE
            WHEN operational_notes IS NULL OR operational_notes = '' THEN ?
            ELSE CONCAT(operational_notes, '\n', ?)
        END
        WHERE id = ? AND status <> 'closed'
    ]], { note, note, alertId })
end

function NexusDispatchUpsertUnit(alertId, officer, status)
    return MySQL.update.await([[
        INSERT INTO nexus_dispatch_units (alert_id, citizenid, officer_name, unit_status)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE officer_name = VALUES(officer_name), unit_status = VALUES(unit_status)
    ]], { alertId, officer.citizenid, officer.name, status or 'assigned' })
end

function NexusDispatchRemoveUnit(alertId, citizenid)
    return MySQL.update.await('DELETE FROM nexus_dispatch_units WHERE alert_id = ? AND citizenid = ?', { alertId, citizenid })
end

function NexusDispatchLinkAisCase(alertId, caseId, caseNumber)
    return MySQL.update.await([[
        UPDATE nexus_dispatch_alerts
        SET ais_case_id = ?, ais_case_number = ?
        WHERE id = ? AND (ais_case_id IS NULL OR ais_case_id = 0)
    ]], { caseId, caseNumber, alertId })
end
