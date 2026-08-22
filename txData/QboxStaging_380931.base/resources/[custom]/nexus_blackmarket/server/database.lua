local function createTables()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS nexus_blackmarket_logs (
            id INT NOT NULL AUTO_INCREMENT,
            citizenid VARCHAR(64) NOT NULL,
            player_name VARCHAR(96) NULL,
            location_id VARCHAR(64) NOT NULL,
            catalog_id VARCHAR(64) NOT NULL,
            item VARCHAR(64) NOT NULL,
            price INT NOT NULL DEFAULT 0,
            money_type VARCHAR(24) NOT NULL DEFAULT 'cash',
            heat INT NOT NULL DEFAULT 0,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            KEY idx_citizenid (citizenid),
            KEY idx_catalog_id (catalog_id),
            KEY idx_created_at (created_at)
        )
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS nexus_blackmarket_state (
            state_key VARCHAR(96) NOT NULL,
            state_value VARCHAR(255) NOT NULL,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (state_key)
        )
    ]])
end

function NexusBlackmarketLogPurchase(data)
    MySQL.insert.await([[
        INSERT INTO nexus_blackmarket_logs
            (citizenid, player_name, location_id, catalog_id, item, price, money_type, heat)
        VALUES
            (?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        data.citizenid,
        data.playerName,
        data.locationId,
        data.catalogId,
        data.item,
        data.price,
        data.moneyType,
        data.heat or 0,
    })
end

function NexusBlackmarketGetState(key, fallback)
    local row = MySQL.single.await([[
        SELECT state_value
        FROM nexus_blackmarket_state
        WHERE state_key = ?
    ]], { key })

    if not row then return fallback end
    return row.state_value
end

function NexusBlackmarketSetState(key, value)
    MySQL.query.await([[
        INSERT INTO nexus_blackmarket_state (state_key, state_value)
        VALUES (?, ?)
        ON DUPLICATE KEY UPDATE state_value = VALUES(state_value)
    ]], { key, tostring(value) })
end

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    createTables()
end)
