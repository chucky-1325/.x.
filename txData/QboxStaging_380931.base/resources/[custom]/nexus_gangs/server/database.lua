function NexusGangsEnsureTables()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS nexus_gangs (
            name VARCHAR(64) NOT NULL,
            label VARCHAR(96) NOT NULL,
            tag VARCHAR(12) NOT NULL,
            color VARCHAR(16) NOT NULL DEFAULT '#22d3ee',
            reputation INT NOT NULL DEFAULT 0,
            created_by VARCHAR(64) NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (name),
            UNIQUE KEY idx_nexus_gangs_tag (tag)
        )
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS nexus_gang_members (
            citizenid VARCHAR(64) NOT NULL,
            gang_name VARCHAR(64) NOT NULL,
            rank_level INT NOT NULL DEFAULT 0,
            joined_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (citizenid),
            KEY idx_nexus_gang_members_gang (gang_name),
            CONSTRAINT fk_nexus_gang_members_gang
                FOREIGN KEY (gang_name) REFERENCES nexus_gangs(name)
                ON DELETE CASCADE
        )
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS nexus_gang_logs (
            id INT NOT NULL AUTO_INCREMENT,
            gang_name VARCHAR(64) NULL,
            actor_citizenid VARCHAR(64) NULL,
            target_citizenid VARCHAR(64) NULL,
            action VARCHAR(64) NOT NULL,
            metadata LONGTEXT NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            KEY idx_nexus_gang_logs_gang (gang_name),
            KEY idx_nexus_gang_logs_created (created_at)
        )
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS nexus_gang_vehicles (
            id INT NOT NULL AUTO_INCREMENT,
            gang_name VARCHAR(64) NOT NULL,
            location_id VARCHAR(64) NOT NULL,
            model VARCHAR(64) NOT NULL,
            label VARCHAR(96) NULL,
            plate VARCHAR(16) NOT NULL,
            state VARCHAR(16) NOT NULL DEFAULT 'stored',
            last_driver VARCHAR(64) NULL,
            metadata LONGTEXT NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            UNIQUE KEY idx_nexus_gang_vehicle_plate (plate),
            KEY idx_nexus_gang_vehicle_gang (gang_name),
            KEY idx_nexus_gang_vehicle_state (state)
        )
    ]])
end

function NexusGangsCreateGang(data)
    return MySQL.insert.await([[
        INSERT INTO nexus_gangs (name, label, tag, color, reputation, created_by)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], {
        data.name,
        data.label,
        data.tag,
        data.color,
        data.reputation or 0,
        data.createdBy,
    })
end

function NexusGangsFetchGang(name)
    return MySQL.single.await('SELECT * FROM nexus_gangs WHERE name = ?', { name })
end

function NexusGangsAddReputation(gangName, amount)
    local value = math.floor(tonumber(amount) or 0)
    if value == 0 then return false end

    MySQL.query.await([[
        UPDATE nexus_gangs
        SET reputation = GREATEST(0, reputation + ?)
        WHERE name = ?
    ]], { value, gangName })

    return true
end

function NexusGangsFetchMember(citizenid)
    return MySQL.single.await([[
        SELECT m.citizenid, m.gang_name, m.rank_level, g.label, g.tag, g.color, g.reputation
        FROM nexus_gang_members m
        JOIN nexus_gangs g ON g.name = m.gang_name
        WHERE m.citizenid = ?
    ]], { citizenid })
end

function NexusGangsFetchMembers(gangName)
    return MySQL.query.await([[
        SELECT citizenid, gang_name, rank_level, joined_at
        FROM nexus_gang_members
        WHERE gang_name = ?
        ORDER BY rank_level DESC, joined_at ASC
    ]], { gangName }) or {}
end

function NexusGangsFetchLogs(gangName, limit)
    if not gangName or gangName == '' or gangName == 'none' then return {} end

    return MySQL.query.await([[
        SELECT actor_citizenid, target_citizenid, action, metadata, created_at
        FROM nexus_gang_logs
        WHERE gang_name = ?
        ORDER BY id DESC
        LIMIT ?
    ]], { gangName, math.min(tonumber(limit) or 12, 30) }) or {}
end

function NexusGangsFetchVehicles(gangName)
    if not gangName or gangName == '' or gangName == 'none' then return {} end

    return MySQL.query.await([[
        SELECT id, gang_name, location_id, model, label, plate, state, last_driver, updated_at
        FROM nexus_gang_vehicles
        WHERE gang_name = ?
        ORDER BY updated_at DESC, id DESC
    ]], { gangName }) or {}
end

function NexusGangsCountVehiclesByModel(gangName, model)
    local row = MySQL.single.await([[
        SELECT COUNT(*) AS total
        FROM nexus_gang_vehicles
        WHERE gang_name = ? AND model = ?
    ]], { gangName, model })

    return tonumber(row and row.total) or 0
end

function NexusGangsFetchStoredVehicle(gangName, model, locationId)
    return MySQL.single.await([[
        SELECT id, gang_name, location_id, model, label, plate, state
        FROM nexus_gang_vehicles
        WHERE gang_name = ? AND model = ? AND state = 'stored'
            AND (location_id = ? OR ? IS NULL)
        ORDER BY updated_at ASC, id ASC
        LIMIT 1
    ]], { gangName, model, locationId, locationId })
end

function NexusGangsCreateVehicle(data)
    return MySQL.insert.await([[
        INSERT INTO nexus_gang_vehicles
            (gang_name, location_id, model, label, plate, state, last_driver, metadata)
        VALUES
            (?, ?, ?, ?, ?, 'out', ?, ?)
    ]], {
        data.gangName,
        data.locationId,
        data.model,
        data.label,
        data.plate,
        data.lastDriver,
        data.metadata and json.encode(data.metadata) or nil,
    })
end

function NexusGangsSetVehicleOutById(id, citizenid, metadata)
    local result = MySQL.update.await([[
        UPDATE nexus_gang_vehicles
        SET state = 'out', last_driver = ?, metadata = COALESCE(?, metadata)
        WHERE id = ? AND state = 'stored'
    ]], {
        citizenid,
        metadata and json.encode(metadata) or nil,
        id,
    })

    return (tonumber(result) or 0) > 0
end

function NexusGangsSetVehicleStateByPlate(gangName, plate, state, citizenid, metadata)
    local result = MySQL.update.await([[
        UPDATE nexus_gang_vehicles
        SET state = ?, last_driver = ?, metadata = COALESCE(?, metadata)
        WHERE gang_name = ? AND plate = ?
    ]], {
        state,
        citizenid,
        metadata and json.encode(metadata) or nil,
        gangName,
        plate,
    })

    return (tonumber(result) or 0) > 0
end

function NexusGangsPlateExists(plate)
    local row = MySQL.single.await('SELECT plate FROM nexus_gang_vehicles WHERE plate = ?', { plate })
    return row ~= nil
end

function NexusGangsSetMember(citizenid, gangName, rankLevel)
    MySQL.query.await([[
        INSERT INTO nexus_gang_members (citizenid, gang_name, rank_level)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE gang_name = VALUES(gang_name), rank_level = VALUES(rank_level)
    ]], { citizenid, gangName, rankLevel })
end

function NexusGangsRemoveMember(citizenid)
    MySQL.query.await('DELETE FROM nexus_gang_members WHERE citizenid = ?', { citizenid })
end

function NexusGangsLog(data)
    MySQL.insert.await([[
        INSERT INTO nexus_gang_logs (gang_name, actor_citizenid, target_citizenid, action, metadata)
        VALUES (?, ?, ?, ?, ?)
    ]], {
        data.gangName,
        data.actor,
        data.target,
        data.action,
        data.metadata and json.encode(data.metadata) or nil,
    })
end

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    NexusGangsEnsureTables()
end)
