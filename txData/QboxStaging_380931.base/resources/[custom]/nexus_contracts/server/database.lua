local function databaseCall(label, callback)
    local ok, result = pcall(callback)
    if not ok then
        print(('[nexus_contracts] database error in %s: %s'):format(label, tostring(result)))
        return nil, 'database_error'
    end
    return result
end

function NexusContractsSchemaReady()
    local result, errorCode = databaseCall('schema_check', function()
        return MySQL.single.await([[
            SELECT
                (
                    SELECT COUNT(*)
                    FROM information_schema.tables
                    WHERE table_schema = DATABASE()
                      AND table_name IN (
                          'nexus_mechanic_supply_lots',
                          'nexus_mechanic_supply_stock',
                          'nexus_mechanic_supply_events'
                      )
                ) AS table_count,
                (
                    SELECT COUNT(*)
                    FROM information_schema.columns
                    WHERE table_schema = DATABASE()
                      AND table_name = 'nexus_mechanic_supply_events'
                      AND column_name = 'transition_key'
                ) AS transition_column_count,
                (
                    SELECT COUNT(*)
                    FROM information_schema.statistics
                    WHERE table_schema = DATABASE()
                      AND table_name = 'nexus_mechanic_supply_events'
                      AND index_name = 'uq_mechanic_supply_event_transition'
                      AND non_unique = 0
                ) AS transition_index_count,
                (
                    SELECT COUNT(*)
                    FROM information_schema.statistics
                    WHERE table_schema = DATABASE()
                      AND table_name = 'nexus_mechanic_supply_events'
                      AND index_name = 'uq_mechanic_supply_event_transition'
                      AND non_unique = 0
                      AND column_name = 'transition_key'
                      AND seq_in_index = 1
                ) AS transition_index_column_count
        ]])
    end)
    if not result then return false, errorCode or 'schema_query_failed' end
    if tonumber(result.table_count) ~= 3 then return false, 'missing_supply_tables' end
    if tonumber(result.transition_column_count) ~= 1 then return false, 'missing_transition_key_column' end
    if tonumber(result.transition_index_count) ~= 1
        or tonumber(result.transition_index_column_count) ~= 1 then
        return false, 'missing_or_invalid_transition_key_index'
    end
    return true
end

function NexusContractsGetStock(stockKey)
    local count = databaseCall('get_stock', function()
        return MySQL.scalar.await([[
            SELECT COUNT(*)
            FROM nexus_mechanic_supply_stock
            WHERE stock_key = ?
        ]], { stockKey })
    end)
    return tonumber(count) or 0
end

function NexusContractsGetReservedCapacity()
    local count = databaseCall('get_reserved_capacity', function()
        return MySQL.scalar.await([[
            SELECT COUNT(*)
            FROM nexus_mechanic_supply_lots
            WHERE capacity_slot IS NOT NULL
        ]])
    end)
    return tonumber(count) or 0
end

function NexusContractsLogEvent(lotId, citizenid, eventType, details)
    return databaseCall('log_event', function()
        return MySQL.insert.await([[
            INSERT INTO nexus_mechanic_supply_events
                (lot_id, citizenid, event_type, details)
            VALUES (?, ?, ?, ?)
        ]], {
            lotId,
            citizenid,
            eventType,
            details and json.encode(details) or nil,
        })
    end)
end

function NexusContractsGetLot(lotId)
    if type(lotId) ~= 'string' or lotId == '' then return nil end
    return databaseCall('get_lot', function()
        return MySQL.single.await([[
            SELECT *
            FROM nexus_mechanic_supply_lots
            WHERE lot_id = ?
            LIMIT 1
        ]], { lotId })
    end)
end

function NexusContractsGetActiveLot(citizenid)
    if type(citizenid) ~= 'string' or citizenid == '' then return nil end
    return databaseCall('get_active_lot', function()
        return MySQL.single.await([[
            SELECT *
            FROM nexus_mechanic_supply_lots
            WHERE active_key = ?
            LIMIT 1
        ]], { citizenid })
    end)
end

function NexusContractsGetLatestLot(citizenid)
    if type(citizenid) ~= 'string' or citizenid == '' then return nil end
    return databaseCall('get_latest_lot', function()
        return MySQL.single.await([[
            SELECT *
            FROM nexus_mechanic_supply_lots
            WHERE citizenid = ?
            ORDER BY created_at DESC
            LIMIT 1
        ]], { citizenid })
    end)
end

function NexusContractsCreateSupplyLot(data)
    local affected, errorCode = databaseCall('create_supply_lot', function()
        return MySQL.update.await([[
            INSERT INTO nexus_mechanic_supply_lots
                (lot_id, contract_type, citizenid, owner_name, destination,
                 contents, state, expires_at, capacity_slot, active_key)
            SELECT ?, ?, ?, ?, ?, ?, 'reserved', ?, slots.slot_id, ?
            FROM (
                SELECT 1 AS slot_id UNION ALL SELECT 2 UNION ALL SELECT 3
                UNION ALL SELECT 4 UNION ALL SELECT 5
            ) AS slots
            LEFT JOIN nexus_mechanic_supply_lots occupied
                ON occupied.capacity_slot = slots.slot_id
            WHERE occupied.lot_id IS NULL
              AND NOT EXISTS (
                  SELECT 1
                  FROM nexus_mechanic_supply_lots active
                  WHERE active.active_key = ?
              )
            ORDER BY slots.slot_id
            LIMIT 1
        ]], {
            data.lotId,
            data.contractType,
            data.citizenid,
            data.ownerName,
            data.destination,
            json.encode(data.contents),
            data.expiresAt,
            data.citizenid,
            data.citizenid,
        })
    end)

    if affected == nil then return false, errorCode end
    if affected ~= 1 then return false, 'capacity_or_active_lot' end

    local eventId = NexusContractsLogEvent(data.lotId, data.citizenid, 'created', {
        destination = data.destination,
        expiresAt = data.expiresAt,
        contents = data.contents,
    })
    if not eventId then
        NexusContractsMarkAmbiguous(data.lotId, data.citizenid, 'created_event_not_persisted')
        return false, 'audit_log_failed'
    end
    return true
end

function NexusContractsMarkPickedUp(lotId, citizenid, packageSlot)
    local affected = databaseCall('mark_picked_up', function()
        return MySQL.update.await([[
            UPDATE nexus_mechanic_supply_lots
            SET state = 'picked_up', package_slot = ?, picked_up_at = CURRENT_TIMESTAMP
            WHERE lot_id = ? AND citizenid = ? AND state = 'reserved'
        ]], { packageSlot, lotId, citizenid })
    end)
    if affected ~= 1 then return false end
    local eventId = NexusContractsLogEvent(lotId, citizenid, 'picked_up', { packageSlot = packageSlot })
    if not eventId then
        NexusContractsMarkAmbiguous(lotId, citizenid, 'pickup_event_not_persisted')
        return false
    end
    return true
end

function NexusContractsBeginDelivery(lotId, citizenid)
    local affected = databaseCall('begin_delivery', function()
        return MySQL.update.await([[
            UPDATE nexus_mechanic_supply_lots
            SET state = 'delivery_pending'
            WHERE lot_id = ? AND citizenid = ? AND state = 'picked_up'
        ]], { lotId, citizenid })
    end)
    return affected == 1
end

function NexusContractsCompleteDelivery(lotId, citizenid, stockKey, contents)
    contents = contents or {}
    local transitionKey = ('delivered:%s'):format(lotId)
    local eventDetails = json.encode({ stockKey = stockKey })
    local success = databaseCall('complete_delivery', function()
        return MySQL.transaction.await({
            {
                query = [[
                    UPDATE nexus_mechanic_supply_lots
                    SET state = 'delivered', active_key = NULL, package_slot = NULL,
                        delivered_at = CURRENT_TIMESTAMP
                    WHERE lot_id = ? AND citizenid = ? AND state = 'delivery_pending'
                ]],
                values = { lotId, citizenid },
            },
            {
                query = [[
                    INSERT INTO nexus_mechanic_supply_events
                        (lot_id, citizenid, event_type, transition_key, details)
                    SELECT ?, ?, 'delivered', ?, ?
                    UNION ALL
                    SELECT ?, ?, 'delivered', ?, ?
                    WHERE ROW_COUNT() <> 1
                ]],
                values = {
                    lotId,
                    citizenid,
                    transitionKey,
                    eventDetails,
                    lotId,
                    citizenid,
                    transitionKey,
                    eventDetails,
                },
            },
            {
                query = [[
                    INSERT INTO nexus_mechanic_supply_stock
                        (lot_id, stock_key, metalscrap, iron, plastic)
                    VALUES (?, ?, ?, ?, ?)
                ]],
                values = {
                    lotId,
                    stockKey,
                    tonumber(contents.metalscrap) or 0,
                    tonumber(contents.iron) or 0,
                    tonumber(contents.plastic) or 0,
                },
            },
        })
    end)
    return success == true
end

local function markTerminal(lotId, citizenid, expectedState, targetState, eventType, details)
    local transitionKey = ('terminal:%s'):format(lotId)
    local eventDetails = details and json.encode(details) or nil
    local success = databaseCall(('mark_%s'):format(targetState), function()
        return MySQL.transaction.await({
            {
                query = ([[
                    UPDATE nexus_mechanic_supply_lots
                    SET state = ?, active_key = NULL, capacity_slot = NULL, package_slot = NULL,
                        incident_reason = ?, finalized_at = CURRENT_TIMESTAMP
                    WHERE lot_id = ? AND citizenid = ? AND state = '%s'
                ]]):format(expectedState),
                values = {
                    targetState,
                    details and details.reason or nil,
                    lotId,
                    citizenid,
                },
            },
            {
                query = [[
                    INSERT INTO nexus_mechanic_supply_events
                        (lot_id, citizenid, event_type, transition_key, details)
                    SELECT ?, ?, ?, ?, ?
                    UNION ALL
                    SELECT ?, ?, ?, ?, ?
                    WHERE ROW_COUNT() <> 1
                ]],
                values = {
                    lotId,
                    citizenid,
                    eventType,
                    transitionKey,
                    eventDetails,
                    lotId,
                    citizenid,
                    eventType,
                    transitionKey,
                    eventDetails,
                },
            },
        })
    end)
    if success == true then return true end

    if not NexusContractsMarkAmbiguous(lotId, citizenid, ('%s_transaction_failed'):format(eventType)) then
        print(('[nexus_contracts] CRITICAL: terminal transition and ambiguous lock failed lot=%s event=%s'):format(
            tostring(lotId),
            tostring(eventType)
        ))
    end
    return false
end

function NexusContractsCancelReserved(lotId, citizenid, reason)
    return markTerminal(lotId, citizenid, 'reserved', 'cancelled', 'cancelled', { reason = reason })
end

function NexusContractsExpireReserved(lotId, citizenid)
    return markTerminal(lotId, citizenid, 'reserved', 'expired', 'expired', { reason = 'deadline' })
end

function NexusContractsLosePickedUp(lotId, citizenid, reason)
    return markTerminal(lotId, citizenid, 'picked_up', 'lost', 'lost', { reason = reason })
end

function NexusContractsMarkAmbiguous(lotId, citizenid, reason)
    local affected = databaseCall('mark_ambiguous', function()
        return MySQL.update.await([[
            UPDATE nexus_mechanic_supply_lots
            SET state = 'ambiguous', incident_reason = ?, finalized_at = CURRENT_TIMESTAMP
            WHERE lot_id = ? AND citizenid = ?
              AND state IN ('reserved', 'picked_up', 'delivery_pending')
        ]], { reason, lotId, citizenid })
    end)
    if affected ~= 1 then return false end
    NexusContractsLogEvent(lotId, citizenid, 'ambiguous', { reason = reason })
    return true
end

function NexusContractsListLotIncidents()
    return databaseCall('list_lot_incidents', function()
        return MySQL.query.await([[
            SELECT lot_id, citizenid, incident_reason, finalized_at
            FROM nexus_mechanic_supply_lots
            WHERE state = 'ambiguous'
            ORDER BY finalized_at ASC
        ]])
    end) or {}
end

function NexusContractsRecoverLotIncident(lotId, stockKey)
    local lot = databaseCall('get_lot_for_recovery', function()
        return MySQL.single.await([[
            SELECT incident_reason, contents
            FROM nexus_mechanic_supply_lots
            WHERE lot_id = ? AND state = 'ambiguous'
            LIMIT 1
        ]], { lotId })
    end)
    if not lot then return nil end

    local metalscrap, iron, plastic = 0, 0, 0
    if lot.incident_reason == 'inventory_removed_stock_commit_failed' then
        local ok, contents = pcall(json.decode, lot.contents or '')
        if ok and type(contents) == 'table' then
            metalscrap = tonumber(contents.metalscrap) or 0
            iron = tonumber(contents.iron) or 0
            plastic = tonumber(contents.plastic) or 0
        end
    end

    return databaseCall('recover_lot_incident', function()
        local rows = MySQL.query.await('CALL sp_recover_civil_lot_incident(?, ?, ?, ?, ?)', {
            lotId, stockKey, metalscrap, iron, plastic,
        })
        return rows and rows[1] or nil
    end)
end

function NexusContractsListCraftQuarantines()
    return databaseCall('list_craft_quarantines', function()
        return MySQL.query.await([[
            SELECT reservation_id, citizenid, lot_id, incident_reason, finalized_at
            FROM nexus_mechanic_craft_reservations
            WHERE state = 'ambiguous'
            ORDER BY finalized_at ASC
        ]])
    end) or {}
end

function NexusContractsRecoverCraftQuarantine(reservationId, route)
    return databaseCall('recover_craft_quarantine', function()
        local rows = MySQL.query.await('CALL sp_recover_craft_quarantine(?, ?)', { reservationId, route })
        return rows and rows[1] or nil
    end)
end

function NexusContractsGetExpiredLots(now)
    return databaseCall('get_expired_lots', function()
        return MySQL.query.await([[
            SELECT lot_id, citizenid, state
            FROM nexus_mechanic_supply_lots
            WHERE expires_at < ? AND state IN ('reserved', 'picked_up')
        ]], { now })
    end) or {}
end

function NexusContractsRecoverPendingDeliveries()
    local pending = databaseCall('get_pending_deliveries', function()
        return MySQL.query.await([[
            SELECT lot_id, citizenid
            FROM nexus_mechanic_supply_lots
            WHERE state = 'delivery_pending'
        ]])
    end) or {}

    for i = 1, #pending do
        NexusContractsMarkAmbiguous(
            pending[i].lot_id,
            pending[i].citizenid,
            'resource_restarted_during_delivery'
        )
    end
    return #pending
end

function NexusContractsCraftingSchemaReady()
    local expectedColumns = {
        nexus_mechanic_supply_lots = {
            'lot_id', 'state', 'capacity_slot', 'finalized_at',
        },
        nexus_mechanic_supply_stock = {
            'lot_id', 'stock_key', 'metalscrap', 'iron', 'plastic', 'received_at',
            'stock_state', 'reservation_id', 'reserved_at',
            'reservation_expires_at', 'consumed_at',
        },
        nexus_mechanic_craft_reservations = {
            'reservation_id', 'lot_id', 'citizenid', 'station_id', 'recipe_id',
            'output_item', 'output_count', 'state', 'active_key', 'expires_at',
            'incident_reason', 'reserved_at', 'fulfilling_at', 'completed_at',
            'finalized_at', 'updated_at',
        },
        nexus_mechanic_craft_events = {
            'id', 'reservation_id', 'lot_id', 'citizenid', 'event_type',
            'transition_key', 'details', 'created_at',
        },
        nexus_mechanic_craft_guards = {
            'guard_key', 'created_at',
        },
    }
    local expectedIndexes = {
        { table = 'nexus_mechanic_supply_lots', name = 'PRIMARY', unique = true, columns = { 'lot_id' } },
        { table = 'nexus_mechanic_supply_lots', name = 'uq_mechanic_supply_capacity_slot', unique = true, columns = { 'capacity_slot' } },
        { table = 'nexus_mechanic_supply_lots', name = 'uq_mechanic_supply_active_key', unique = true, columns = { 'active_key' } },
        { table = 'nexus_mechanic_supply_stock', name = 'PRIMARY', unique = true, columns = { 'lot_id' } },
        { table = 'nexus_mechanic_supply_stock', name = 'uq_mechanic_supply_stock_reservation', unique = true, columns = { 'reservation_id' } },
        { table = 'nexus_mechanic_supply_stock', name = 'idx_mechanic_supply_stock_state', unique = false, columns = { 'stock_key', 'stock_state', 'received_at' } },
        { table = 'nexus_mechanic_craft_reservations', name = 'PRIMARY', unique = true, columns = { 'reservation_id' } },
        { table = 'nexus_mechanic_craft_reservations', name = 'uq_mechanic_craft_active', unique = true, columns = { 'active_key' } },
        { table = 'nexus_mechanic_craft_reservations', name = 'idx_mechanic_craft_state_expiry', unique = false, columns = { 'state', 'expires_at' } },
        { table = 'nexus_mechanic_craft_events', name = 'PRIMARY', unique = true, columns = { 'id' } },
        { table = 'nexus_mechanic_craft_events', name = 'uq_mechanic_craft_event_transition', unique = true, columns = { 'transition_key' } },
        { table = 'nexus_mechanic_craft_guards', name = 'PRIMARY', unique = true, columns = { 'guard_key' } },
    }

    local tables, tableError = databaseCall('crafting_schema_tables', function()
        return MySQL.query.await([[
            SELECT table_name, engine
            FROM information_schema.tables
            WHERE table_schema = DATABASE()
              AND table_name IN (
                  'nexus_mechanic_supply_lots',
                  'nexus_mechanic_supply_stock',
                  'nexus_mechanic_craft_reservations',
                  'nexus_mechanic_craft_events',
                  'nexus_mechanic_craft_guards'
              )
        ]])
    end)
    if not tables then return false, tableError or 'schema_table_query_failed' end

    local tableEngines = {}
    for i = 1, #tables do
        tableEngines[tables[i].table_name] = tostring(tables[i].engine or ''):upper()
    end
    for tableName in pairs(expectedColumns) do
        if not tableEngines[tableName] then return false, ('missing_table:%s'):format(tableName) end
        if tableEngines[tableName] ~= 'INNODB' then return false, ('invalid_engine:%s'):format(tableName) end
    end

    local columns, columnError = databaseCall('crafting_schema_columns', function()
        return MySQL.query.await([[
            SELECT table_name, column_name
            FROM information_schema.columns
            WHERE table_schema = DATABASE()
              AND table_name IN (
                  'nexus_mechanic_supply_lots',
                  'nexus_mechanic_supply_stock',
                  'nexus_mechanic_craft_reservations',
                  'nexus_mechanic_craft_events',
                  'nexus_mechanic_craft_guards'
              )
        ]])
    end)
    if not columns then return false, columnError or 'schema_column_query_failed' end

    local presentColumns = {}
    for i = 1, #columns do
        local tableName = columns[i].table_name
        presentColumns[tableName] = presentColumns[tableName] or {}
        presentColumns[tableName][columns[i].column_name] = true
    end
    for tableName, names in pairs(expectedColumns) do
        for i = 1, #names do
            if not (presentColumns[tableName] and presentColumns[tableName][names[i]]) then
                return false, ('missing_column:%s.%s'):format(tableName, names[i])
            end
        end
    end

    local indexes, indexError = databaseCall('crafting_schema_indexes', function()
        return MySQL.query.await([[
            SELECT table_name, index_name, non_unique, seq_in_index, column_name, sub_part
            FROM information_schema.statistics
            WHERE table_schema = DATABASE()
              AND table_name IN (
                  'nexus_mechanic_supply_lots',
                  'nexus_mechanic_supply_stock',
                  'nexus_mechanic_craft_reservations',
                  'nexus_mechanic_craft_events',
                  'nexus_mechanic_craft_guards'
              )
            ORDER BY table_name, index_name, seq_in_index
        ]])
    end)
    if not indexes then return false, indexError or 'schema_index_query_failed' end

    local presentIndexes = {}
    for i = 1, #indexes do
        local row = indexes[i]
        presentIndexes[row.table_name] = presentIndexes[row.table_name] or {}
        local index = presentIndexes[row.table_name][row.index_name]
        if not index then
            index = { unique = tonumber(row.non_unique) == 0, fullColumns = true, columns = {} }
            presentIndexes[row.table_name][row.index_name] = index
        end
        if row.sub_part ~= nil then index.fullColumns = false end
        index.columns[tonumber(row.seq_in_index)] = row.column_name
    end
    for i = 1, #expectedIndexes do
        local expected = expectedIndexes[i]
        local index = presentIndexes[expected.table] and presentIndexes[expected.table][expected.name]
        if not index then return false, ('missing_index:%s.%s'):format(expected.table, expected.name) end
        if index.unique ~= expected.unique or not index.fullColumns or #index.columns ~= #expected.columns then
            return false, ('invalid_index:%s.%s'):format(expected.table, expected.name)
        end
        for position = 1, #expected.columns do
            if index.columns[position] ~= expected.columns[position] then
                return false, ('invalid_index:%s.%s'):format(expected.table, expected.name)
            end
        end
    end
    return true
end

function NexusContractsGetMechanicStockSnapshot(stockKey)
    local rows = databaseCall('get_mechanic_stock_snapshot', function()
        return MySQL.query.await([[
            SELECT stock_state, COUNT(*) AS total
            FROM nexus_mechanic_supply_stock
            WHERE stock_key = ?
            GROUP BY stock_state
        ]], { stockKey })
    end)
    if not rows then return nil end

    local snapshot = { available = 0, reserved = 0, consumed = 0, total = 0 }
    for i = 1, #rows do
        local state = tostring(rows[i].stock_state or '')
        local count = tonumber(rows[i].total) or 0
        if snapshot[state] ~= nil then snapshot[state] = count end
    end
    snapshot.total = snapshot.available + snapshot.reserved
    return snapshot
end

function NexusContractsGetMechanicCraftReservation(reservationId)
    if type(reservationId) ~= 'string' or reservationId == '' then return nil end
    return databaseCall('get_mechanic_craft_reservation', function()
        return MySQL.single.await([[
            SELECT * FROM nexus_mechanic_craft_reservations
            WHERE reservation_id = ? LIMIT 1
        ]], { reservationId })
    end)
end

function NexusContractsGetActiveMechanicCraft(citizenid)
    if type(citizenid) ~= 'string' or citizenid == '' then return nil end
    return databaseCall('get_active_mechanic_craft', function()
        return MySQL.single.await([[
            SELECT * FROM nexus_mechanic_craft_reservations
            WHERE active_key = ? LIMIT 1
        ]], { citizenid })
    end)
end

function NexusContractsReserveMechanicCraft(data)
    local reserveStockGuard = ('craft:reserve:stock:%s'):format(data.reservationId)
    local reserveRowGuard = ('craft:reserve:row:%s'):format(data.reservationId)
    local transitionKey = ('craft:reserved:%s'):format(data.reservationId)
    local details = json.encode({
        stationId = data.stationId,
        recipeId = data.recipeId,
        outputItem = data.outputItem,
        outputCount = data.outputCount,
    })

    local success = databaseCall('reserve_mechanic_craft', function()
        return MySQL.transaction.await({
            {
                query = [[
                    UPDATE nexus_mechanic_supply_stock
                    SET stock_state = 'reserved', reservation_id = ?,
                        reserved_at = CURRENT_TIMESTAMP, reservation_expires_at = ?
                    WHERE lot_id = (
                        SELECT lot_id FROM (
                            SELECT stock.lot_id
                            FROM nexus_mechanic_supply_stock stock
                            INNER JOIN nexus_mechanic_supply_lots lot ON lot.lot_id = stock.lot_id
                            WHERE stock.stock_key = ?
                              AND stock.stock_state = 'available'
                              AND stock.reservation_id IS NULL
                              AND stock.metalscrap = ? AND stock.iron = ? AND stock.plastic = ?
                              AND lot.state = 'delivered'
                            ORDER BY stock.received_at, stock.lot_id
                            LIMIT 1
                        ) candidate
                    )
                      AND stock_state = 'available' AND reservation_id IS NULL
                ]],
                values = {
                    data.reservationId,
                    data.expiresAt,
                    data.stockKey,
                    data.contents.metalscrap,
                    data.contents.iron,
                    data.contents.plastic,
                },
            },
            {
                query = [[
                    INSERT INTO nexus_mechanic_craft_guards (guard_key)
                    SELECT ? UNION ALL SELECT ? WHERE ROW_COUNT() <> 1
                ]],
                values = { reserveStockGuard, reserveStockGuard },
            },
            {
                query = [[
                    INSERT INTO nexus_mechanic_craft_reservations
                        (reservation_id, lot_id, citizenid, station_id, recipe_id,
                         output_item, output_count, state, active_key, expires_at)
                    SELECT ?, lot_id, ?, ?, ?, ?, ?, 'reserved', ?, ?
                    FROM nexus_mechanic_supply_stock
                    WHERE reservation_id = ? AND stock_state = 'reserved'
                ]],
                values = {
                    data.reservationId,
                    data.citizenid,
                    data.stationId,
                    data.recipeId,
                    data.outputItem,
                    data.outputCount,
                    data.citizenid,
                    data.expiresAt,
                    data.reservationId,
                },
            },
            {
                query = [[
                    INSERT INTO nexus_mechanic_craft_guards (guard_key)
                    SELECT ? UNION ALL SELECT ? WHERE ROW_COUNT() <> 1
                ]],
                values = { reserveRowGuard, reserveRowGuard },
            },
            {
                query = [[
                    INSERT INTO nexus_mechanic_craft_events
                        (reservation_id, lot_id, citizenid, event_type, transition_key, details)
                    SELECT reservation_id, lot_id, citizenid, 'reserved', ?, ?
                    FROM nexus_mechanic_craft_reservations
                    WHERE reservation_id = ? AND state = 'reserved'
                ]],
                values = { transitionKey, details, data.reservationId },
            },
        })
    end)

    if success ~= true then
        local active = NexusContractsGetActiveMechanicCraft(data.citizenid)
        if active then return nil, 'active_reservation' end
        return nil, 'stock_unavailable'
    end

    local reservation = NexusContractsGetMechanicCraftReservation(data.reservationId)
    if not reservation or reservation.state ~= 'reserved' then return nil, 'reservation_unverified' end
    return reservation
end

function NexusContractsBeginMechanicCraft(reservationId, citizenid)
    local guardKey = ('craft:fulfilling:row:%s'):format(reservationId)
    local transitionKey = ('craft:fulfilling:%s'):format(reservationId)
    local success = databaseCall('begin_mechanic_craft', function()
        return MySQL.transaction.await({
            {
                query = [[
                    UPDATE nexus_mechanic_craft_reservations
                    SET state = 'fulfilling', fulfilling_at = CURRENT_TIMESTAMP
                    WHERE reservation_id = ? AND citizenid = ? AND state = 'reserved'
                ]],
                values = { reservationId, citizenid },
            },
            {
                query = [[
                    INSERT INTO nexus_mechanic_craft_guards (guard_key)
                    SELECT ? UNION ALL SELECT ? WHERE ROW_COUNT() <> 1
                ]],
                values = { guardKey, guardKey },
            },
            {
                query = [[
                    INSERT INTO nexus_mechanic_craft_events
                        (reservation_id, lot_id, citizenid, event_type, transition_key)
                    SELECT reservation_id, lot_id, citizenid, 'fulfilling', ?
                    FROM nexus_mechanic_craft_reservations
                    WHERE reservation_id = ? AND state = 'fulfilling'
                ]],
                values = { transitionKey, reservationId },
            },
        })
    end)
    return success == true
end

function NexusContractsCompleteMechanicCraft(reservationId, citizenid)
    local reservationGuard = ('craft:complete:reservation:%s'):format(reservationId)
    local stockGuard = ('craft:complete:stock:%s'):format(reservationId)
    local lotGuard = ('craft:complete:lot:%s'):format(reservationId)
    local transitionKey = ('craft:completed:%s'):format(reservationId)
    local success = databaseCall('complete_mechanic_craft', function()
        return MySQL.transaction.await({
            {
                query = [[
                    UPDATE nexus_mechanic_craft_reservations
                    SET state = 'completed', active_key = NULL,
                        completed_at = CURRENT_TIMESTAMP, finalized_at = CURRENT_TIMESTAMP
                    WHERE reservation_id = ? AND citizenid = ? AND state = 'fulfilling'
                ]],
                values = { reservationId, citizenid },
            },
            {
                query = [[
                    INSERT INTO nexus_mechanic_craft_guards (guard_key)
                    SELECT ? UNION ALL SELECT ? WHERE ROW_COUNT() <> 1
                ]],
                values = { reservationGuard, reservationGuard },
            },
            {
                query = [[
                    UPDATE nexus_mechanic_supply_stock
                    SET stock_state = 'consumed', reservation_id = NULL,
                        reserved_at = NULL, reservation_expires_at = NULL,
                        consumed_at = CURRENT_TIMESTAMP
                    WHERE reservation_id = ? AND stock_state = 'reserved'
                      AND metalscrap = 3 AND iron = 2 AND plastic = 2
                ]],
                values = { reservationId },
            },
            {
                query = [[
                    INSERT INTO nexus_mechanic_craft_guards (guard_key)
                    SELECT ? UNION ALL SELECT ? WHERE ROW_COUNT() <> 1
                ]],
                values = { stockGuard, stockGuard },
            },
            {
                query = [[
                    UPDATE nexus_mechanic_supply_lots lot
                    INNER JOIN nexus_mechanic_craft_reservations reservation
                        ON reservation.lot_id = lot.lot_id
                    SET lot.state = 'consumed', lot.capacity_slot = NULL,
                        lot.finalized_at = CURRENT_TIMESTAMP
                    WHERE reservation.reservation_id = ?
                      AND reservation.citizenid = ?
                      AND reservation.state = 'completed'
                      AND lot.state = 'delivered'
                      AND lot.capacity_slot IS NOT NULL
                ]],
                values = { reservationId, citizenid },
            },
            {
                query = [[
                    INSERT INTO nexus_mechanic_craft_guards (guard_key)
                    SELECT ? UNION ALL SELECT ? WHERE ROW_COUNT() <> 1
                ]],
                values = { lotGuard, lotGuard },
            },
            {
                query = [[
                    INSERT INTO nexus_mechanic_craft_events
                        (reservation_id, lot_id, citizenid, event_type, transition_key)
                    SELECT reservation_id, lot_id, citizenid, 'completed', ?
                    FROM nexus_mechanic_craft_reservations
                    WHERE reservation_id = ? AND state = 'completed'
                ]],
                values = { transitionKey, reservationId },
            },
        })
    end)

    if success == true then return true end
    local current = NexusContractsGetMechanicCraftReservation(reservationId)
    if current and current.citizenid == citizenid and current.state == 'completed' then
        return true, 'already_completed'
    end
    return false, current and current.state or 'database_error'
end

function NexusContractsReleaseMechanicCraft(reservationId, citizenid, expectedState, targetState, reason)
    local allowed = {
        reserved = { cancelled = true, expired = true, failed = true },
        fulfilling = { failed = true },
    }
    if not (allowed[expectedState] and allowed[expectedState][targetState]) then return false end

    local reservationGuard = ('craft:%s:reservation:%s'):format(targetState, reservationId)
    local stockGuard = ('craft:%s:stock:%s'):format(targetState, reservationId)
    local transitionKey = ('craft:%s:%s'):format(targetState, reservationId)
    local details = json.encode({ reason = tostring(reason or targetState):sub(1, 120) })
    local success = databaseCall(('release_mechanic_craft_%s'):format(targetState), function()
        return MySQL.transaction.await({
            {
                query = [[
                    UPDATE nexus_mechanic_craft_reservations
                    SET state = ?, active_key = NULL, incident_reason = ?,
                        finalized_at = CURRENT_TIMESTAMP
                    WHERE reservation_id = ? AND citizenid = ? AND state = ?
                ]],
                values = { targetState, reason, reservationId, citizenid, expectedState },
            },
            {
                query = [[
                    INSERT INTO nexus_mechanic_craft_guards (guard_key)
                    SELECT ? UNION ALL SELECT ? WHERE ROW_COUNT() <> 1
                ]],
                values = { reservationGuard, reservationGuard },
            },
            {
                query = [[
                    UPDATE nexus_mechanic_supply_stock
                    SET stock_state = 'available', reservation_id = NULL,
                        reserved_at = NULL, reservation_expires_at = NULL
                    WHERE reservation_id = ? AND stock_state = 'reserved'
                ]],
                values = { reservationId },
            },
            {
                query = [[
                    INSERT INTO nexus_mechanic_craft_guards (guard_key)
                    SELECT ? UNION ALL SELECT ? WHERE ROW_COUNT() <> 1
                ]],
                values = { stockGuard, stockGuard },
            },
            {
                query = [[
                    INSERT INTO nexus_mechanic_craft_events
                        (reservation_id, lot_id, citizenid, event_type, transition_key, details)
                    SELECT reservation_id, lot_id, citizenid, ?, ?, ?
                    FROM nexus_mechanic_craft_reservations
                    WHERE reservation_id = ? AND state = ?
                ]],
                values = { targetState, transitionKey, details, reservationId, targetState },
            },
        })
    end)
    return success == true
end

function NexusContractsMarkMechanicCraftAmbiguous(reservationId, citizenid, reason)
    local guardKey = ('craft:ambiguous:reservation:%s'):format(reservationId)
    local transitionKey = ('craft:ambiguous:%s'):format(reservationId)
    local details = json.encode({ reason = tostring(reason or 'unknown'):sub(1, 120) })

    databaseCall('mark_mechanic_craft_ambiguous', function()
        return MySQL.transaction.await({
            {
                -- Unica operacion que serializa la carrera: solo un llamador
                -- concurrente puede afectar esta fila (InnoDB row lock).
                query = [[
                    UPDATE nexus_mechanic_craft_reservations
                    SET state = 'ambiguous', incident_reason = ?, finalized_at = CURRENT_TIMESTAMP
                    WHERE reservation_id = ? AND citizenid = ?
                      AND state IN ('reserved', 'fulfilling')
                ]],
                values = { reason, reservationId, citizenid },
            },
            {
                -- Snapshot en variable de sesion, capturado incondicionalmente
                -- en cada llamada, inmediatamente tras el UPDATE propio. No
                -- depende de un valor residual de una transaccion anterior en
                -- esta misma conexion pooled.
                query = [[ SET @nexus_ambiguous_won := ROW_COUNT() ]],
            },
            {
                -- Gateado por el snapshot, no por su propio ROW_COUNT() (que
                -- bajo CLIENT_FOUND_ROWS puede reportar 1 en un no-op).
                query = [[
                    INSERT INTO nexus_mechanic_craft_events
                        (reservation_id, lot_id, citizenid, event_type, transition_key, details)
                    SELECT reservation_id, lot_id, citizenid, 'ambiguous', ?, ?
                    FROM nexus_mechanic_craft_reservations
                    WHERE reservation_id = ? AND @nexus_ambiguous_won = 1
                    ON DUPLICATE KEY UPDATE transition_key = transition_key
                ]],
                values = { transitionKey, details, reservationId },
            },
            {
                -- Mismo snapshot; independiente del resultado de la sentencia
                -- anterior.
                query = [[
                    INSERT INTO nexus_mechanic_craft_guards (guard_key)
                    SELECT ? WHERE @nexus_ambiguous_won = 1
                    ON DUPLICATE KEY UPDATE guard_key = guard_key
                ]],
                values = { guardKey },
            },
        })
    end)

    -- Postcondicion siempre verificada por relectura: el booleano de la
    -- transaccion nunca se usa como prueba de exito.
    local current = NexusContractsGetMechanicCraftReservation(reservationId)
    local reachedAmbiguous = current ~= nil and current.citizenid == citizenid and current.state == 'ambiguous'

    return reachedAmbiguous
end

function NexusContractsGetExpiredMechanicCrafts(now)
    return databaseCall('get_expired_mechanic_crafts', function()
        return MySQL.query.await([[
            SELECT reservation_id, citizenid, state
            FROM nexus_mechanic_craft_reservations
            WHERE expires_at < ? AND state IN ('reserved', 'fulfilling')
        ]], { now })
    end) or {}
end

function NexusContractsGetFulfillingMechanicCrafts()
    return databaseCall('get_fulfilling_mechanic_crafts', function()
        return MySQL.query.await([[
            SELECT reservation_id, citizenid
            FROM nexus_mechanic_craft_reservations
            WHERE state = 'fulfilling'
        ]])
    end) or {}
end
