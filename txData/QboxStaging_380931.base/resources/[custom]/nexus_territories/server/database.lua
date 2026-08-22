function NexusTerritoriesEnsureTables()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS nexus_territory_influence (
            zone_id VARCHAR(64) NOT NULL,
            gang_name VARCHAR(64) NOT NULL,
            influence INT NOT NULL DEFAULT 0,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (zone_id, gang_name),
            KEY idx_territory_zone (zone_id),
            KEY idx_territory_gang (gang_name)
        )
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS nexus_territory_logs (
            id INT NOT NULL AUTO_INCREMENT,
            zone_id VARCHAR(64) NOT NULL,
            gang_name VARCHAR(64) NOT NULL,
            citizenid VARCHAR(64) NULL,
            reason VARCHAR(64) NOT NULL,
            amount INT NOT NULL DEFAULT 0,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            KEY idx_territory_log_zone (zone_id),
            KEY idx_territory_log_gang (gang_name),
            KEY idx_territory_log_created (created_at)
        )
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS nexus_territory_zones (
            zone_id VARCHAR(64) NOT NULL,
            label VARCHAR(96) NOT NULL,
            x DOUBLE NOT NULL,
            y DOUBLE NOT NULL,
            z DOUBLE NOT NULL,
            radius DOUBLE NOT NULL DEFAULT 160,
            heat_multiplier DOUBLE NOT NULL DEFAULT 1,
            enabled TINYINT(1) NOT NULL DEFAULT 1,
            created_by VARCHAR(64) NULL,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (zone_id),
            KEY idx_territory_zones_enabled (enabled)
        )
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS nexus_territory_graffiti (
            id INT NOT NULL AUTO_INCREMENT,
            zone_id VARCHAR(64) NOT NULL,
            gang_name VARCHAR(64) NOT NULL,
            citizenid VARCHAR(64) NULL,
            text VARCHAR(48) NOT NULL,
            color VARCHAR(16) NULL,
            x DOUBLE NOT NULL,
            y DOUBLE NOT NULL,
            z DOUBLE NOT NULL,
            nx DOUBLE NOT NULL DEFAULT 0,
            ny DOUBLE NOT NULL DEFAULT 0,
            nz DOUBLE NOT NULL DEFAULT 1,
            heading DOUBLE NOT NULL DEFAULT 0,
            active TINYINT(1) NOT NULL DEFAULT 1,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            removed_at TIMESTAMP NULL,
            removed_by VARCHAR(64) NULL,
            PRIMARY KEY (id),
            KEY idx_graffiti_zone (zone_id),
            KEY idx_graffiti_gang (gang_name),
            KEY idx_graffiti_active (active)
        )
    ]])

    MySQL.query.await('ALTER TABLE nexus_territory_graffiti ADD COLUMN IF NOT EXISTS nx DOUBLE NOT NULL DEFAULT 0')
    MySQL.query.await('ALTER TABLE nexus_territory_graffiti ADD COLUMN IF NOT EXISTS ny DOUBLE NOT NULL DEFAULT 0')
    MySQL.query.await('ALTER TABLE nexus_territory_graffiti ADD COLUMN IF NOT EXISTS nz DOUBLE NOT NULL DEFAULT 1')
    MySQL.query.await('ALTER TABLE nexus_territory_graffiti ADD COLUMN IF NOT EXISTS color VARCHAR(16) NULL')
end

function NexusTerritoriesFetchInfluence()
    return MySQL.query.await('SELECT zone_id, gang_name, influence FROM nexus_territory_influence') or {}
end

function NexusTerritoriesFetchZones()
    return MySQL.query.await([[
        SELECT zone_id, label, x, y, z, radius, heat_multiplier, enabled
        FROM nexus_territory_zones
        WHERE enabled = 1
    ]]) or {}
end

function NexusTerritoriesFetchAllZones()
    return MySQL.query.await([[
        SELECT zone_id, label, x, y, z, radius, heat_multiplier, enabled, created_by
        FROM nexus_territory_zones
        ORDER BY label ASC
    ]]) or {}
end

function NexusTerritoriesSaveZone(zone)
    MySQL.query.await([[
        INSERT INTO nexus_territory_zones
            (zone_id, label, x, y, z, radius, heat_multiplier, enabled, created_by)
        VALUES
            (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            label = VALUES(label),
            x = VALUES(x),
            y = VALUES(y),
            z = VALUES(z),
            radius = VALUES(radius),
            heat_multiplier = VALUES(heat_multiplier),
            enabled = VALUES(enabled)
    ]], {
        zone.id,
        zone.label,
        zone.coords.x,
        zone.coords.y,
        zone.coords.z,
        zone.radius,
        zone.heatMultiplier,
        zone.enabled and 1 or 0,
        zone.createdBy,
    })
end

function NexusTerritoriesDeleteZone(zoneId)
    MySQL.query.await('DELETE FROM nexus_territory_zones WHERE zone_id = ?', { zoneId })
    MySQL.query.await('DELETE FROM nexus_territory_influence WHERE zone_id = ?', { zoneId })
end

function NexusTerritoriesSetInfluence(zoneId, gangName, influence)
    MySQL.query.await([[
        INSERT INTO nexus_territory_influence (zone_id, gang_name, influence)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE influence = VALUES(influence)
    ]], { zoneId, gangName, influence })
end

function NexusTerritoriesLog(data)
    MySQL.insert.await([[
        INSERT INTO nexus_territory_logs
            (zone_id, gang_name, citizenid, reason, amount)
        VALUES
            (?, ?, ?, ?, ?)
    ]], {
        data.zoneId,
        data.gangName,
        data.citizenid,
        data.reason,
        data.amount,
    })
end

function NexusTerritoriesFetchGangRanking()
    return MySQL.query.await([[
        SELECT gang_name, SUM(influence) AS influence
        FROM nexus_territory_influence
        GROUP BY gang_name
        ORDER BY influence DESC
        LIMIT 20
    ]]) or {}
end

function NexusTerritoriesFetchPlayerRanking()
    return MySQL.query.await([[
        SELECT citizenid, SUM(amount) AS influence
        FROM nexus_territory_logs
        WHERE citizenid IS NOT NULL AND amount > 0
        GROUP BY citizenid
        ORDER BY influence DESC
        LIMIT 20
    ]]) or {}
end

function NexusTerritoriesFetchGraffiti()
    return MySQL.query.await([[
        SELECT id, zone_id, gang_name, text, color, x, y, z, nx, ny, nz, heading, created_at
        FROM nexus_territory_graffiti
        WHERE active = 1
        ORDER BY created_at DESC
    ]]) or {}
end

function NexusTerritoriesCountGraffiti(zoneId, gangName)
    return MySQL.scalar.await([[
        SELECT COUNT(*)
        FROM nexus_territory_graffiti
        WHERE zone_id = ? AND gang_name = ? AND active = 1
    ]], { zoneId, gangName }) or 0
end

function NexusTerritoriesRemoveOldestGraffiti(zoneId, gangName, citizenid)
    MySQL.query.await([[
        UPDATE nexus_territory_graffiti
        SET active = 0, removed_at = CURRENT_TIMESTAMP, removed_by = ?
        WHERE id = (
            SELECT id FROM (
                SELECT id
                FROM nexus_territory_graffiti
                WHERE zone_id = ? AND gang_name = ? AND active = 1
                ORDER BY created_at ASC
                LIMIT 1
            ) AS oldest_graffiti
        )
    ]], { citizenid, zoneId, gangName })
end

function NexusTerritoriesCreateGraffiti(data)
    return MySQL.insert.await([[
        INSERT INTO nexus_territory_graffiti
            (zone_id, gang_name, citizenid, text, color, x, y, z, nx, ny, nz, heading)
        VALUES
            (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        data.zoneId,
        data.gangName,
        data.citizenid,
        data.text,
        data.color,
        data.coords.x,
        data.coords.y,
        data.coords.z,
        data.normal.x,
        data.normal.y,
        data.normal.z,
        data.heading,
    })
end

function NexusTerritoriesDeactivateGraffiti(id, citizenid)
    MySQL.query.await([[
        UPDATE nexus_territory_graffiti
        SET active = 0, removed_at = CURRENT_TIMESTAMP, removed_by = ?
        WHERE id = ? AND active = 1
    ]], { citizenid, id })
end

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    NexusTerritoriesEnsureTables()
end)
