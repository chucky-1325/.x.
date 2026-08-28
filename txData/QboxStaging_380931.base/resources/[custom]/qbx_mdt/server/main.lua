local function isAdmin(source)
    source = tonumber(source)
    if source == 0 then return true end
    if GetResourceState('nexus_permissions') ~= 'started' then return false end
    return exports.nexus_permissions:hasPermission(source, 'qbx_mdt.admin_access')
end

local function hasPoliceAccess(source)
    source = tonumber(source)
    if not source or source <= 0 then return false end
    if isAdmin(source) then return true end
    if GetResourceState('nexus_bridge') ~= 'started' then return false end

    return exports.nexus_bridge:hasAccess(source, 'police') == true
end

local searchBuckets = {}
local fullName

local function getPlayer(source)
    if GetResourceState('qbx_core') ~= 'started' then return nil end
    return exports.qbx_core:GetPlayer(source)
end

local function officerIdentity(source)
    local player = getPlayer(source)
    local data = player and player.PlayerData or {}
    return data.citizenid or ('source:%s'):format(source), fullName(data.charinfo or {}, GetPlayerName(source) or 'Oficial')
end

local function rateLimit(source)
    source = tonumber(source)
    if not source or source <= 0 then return false end

    local now = GetGameTimer()
    local bucket = searchBuckets[source] or { reset = now + 5000, count = 0 }
    if now > bucket.reset then
        bucket.reset = now + 5000
        bucket.count = 0
    end

    bucket.count = bucket.count + 1
    searchBuckets[source] = bucket

    return bucket.count <= 8
end

local function cleanSearch(value)
    value = tostring(value or ''):gsub('[%c]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    if #value > 48 then value = value:sub(1, 48) end
    return value
end

local function cleanText(value, maxLength)
    value = tostring(value or ''):gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if #value > maxLength then value = value:sub(1, maxLength) end
    return value
end

local function decodeJson(value)
    if type(value) ~= 'string' or value == '' then return {} end

    local ok, result = pcall(json.decode, value)
    if ok and type(result) == 'table' then return result end

    return {}
end

function fullName(charinfo, fallback)
    local first = charinfo.firstname or charinfo.firstName or ''
    local last = charinfo.lastname or charinfo.lastName or ''
    local name = (('%s %s'):format(first, last):gsub('^%s+', ''):gsub('%s+$', ''))
    return name ~= '' and name or fallback or 'Sin nombre'
end

local function setupDatabase()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `qbx_mdt_bolos` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `bolo_type` varchar(20) NOT NULL DEFAULT 'person',
            `target` varchar(80) NOT NULL,
            `plate` varchar(15) DEFAULT NULL,
            `citizenid` varchar(50) DEFAULT NULL,
            `description` varchar(500) NOT NULL DEFAULT '',
            `priority` varchar(12) NOT NULL DEFAULT 'normal',
            `status` varchar(20) NOT NULL DEFAULT 'active',
            `created_by_citizenid` varchar(50) DEFAULT NULL,
            `created_by_name` varchar(80) DEFAULT NULL,
            `closed_by_citizenid` varchar(50) DEFAULT NULL,
            `closed_by_name` varchar(80) DEFAULT NULL,
            `close_notes` varchar(300) DEFAULT NULL,
            `dispatch_alert_id` int(11) DEFAULT NULL,
            `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
            `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
            `closed_at` timestamp NULL DEFAULT NULL,
            PRIMARY KEY (`id`),
            KEY `idx_qbx_mdt_bolos_status` (`status`),
            KEY `idx_qbx_mdt_bolos_plate` (`plate`),
            KEY `idx_qbx_mdt_bolos_citizenid` (`citizenid`),
            KEY `idx_qbx_mdt_bolos_dispatch` (`dispatch_alert_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])

    local hasDispatchColumn = MySQL.scalar.await([[
        SELECT COUNT(*)
        FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'qbx_mdt_bolos'
          AND COLUMN_NAME = 'dispatch_alert_id'
    ]])

    if tonumber(hasDispatchColumn) == 0 then
        MySQL.query.await('ALTER TABLE qbx_mdt_bolos ADD COLUMN dispatch_alert_id INT(11) DEFAULT NULL')
        MySQL.query.await('ALTER TABLE qbx_mdt_bolos ADD KEY idx_qbx_mdt_bolos_dispatch (dispatch_alert_id)')
    end
end

local function vehicleStateLabel(state)
    state = tonumber(state)
    if state == 0 then return 'Fuera' end
    if state == 1 then return 'Garaje' end
    if state == 2 then return 'Depósito' end
    return 'Desconocido'
end

lib.callback.register('qbx_mdt:server:searchCitizens', function(source, query)
    if not hasPoliceAccess(source) then return false, 'no_access' end
    if not rateLimit(source) then return false, 'rate_limited' end

    local clean = cleanSearch(query)
    if #clean < 2 then return false, 'query_too_short' end

    local like = ('%%%s%%'):format(clean)
    local rows = MySQL.query.await([[
        SELECT citizenid, name, charinfo, job, gang, metadata, phone_number, last_updated
        FROM players
        WHERE citizenid LIKE ? OR name LIKE ? OR phone_number LIKE ? OR charinfo LIKE ?
        ORDER BY last_updated DESC
        LIMIT 20
    ]], { like, like, like, like }) or {}

    local results = {}
    for i = 1, #rows do
        local row = rows[i]
        local charinfo = decodeJson(row.charinfo)
        local job = decodeJson(row.job)
        local gang = decodeJson(row.gang)
        local metadata = decodeJson(row.metadata)

        results[#results + 1] = {
            citizenid = row.citizenid,
            name = fullName(charinfo, row.name),
            phone = row.phone_number or charinfo.phone or 'N/A',
            birthdate = charinfo.birthdate or charinfo.birthDate or 'N/A',
            nationality = charinfo.nationality or 'N/A',
            job = {
                name = job.name or 'unemployed',
                label = job.label or job.name or 'Civil',
                grade = job.grade and (job.grade.name or job.grade.level) or 'N/A',
            },
            gang = {
                name = gang.name or 'none',
                label = gang.label or gang.name or 'Sin banda',
            },
            licenses = metadata.licences or metadata.licenses or {},
            lastUpdated = tostring(row.last_updated or ''),
        }
    end

    return true, results
end)

lib.callback.register('qbx_mdt:server:searchVehicles', function(source, query)
    if not hasPoliceAccess(source) then return false, 'no_access' end
    if not rateLimit(source) then return false, 'rate_limited' end

    local clean = cleanSearch(query)
    if #clean < 2 then return false, 'query_too_short' end

    local like = ('%%%s%%'):format(clean)
    local rows = MySQL.query.await([[
        SELECT v.id, v.citizenid, v.vehicle, v.hash, v.plate, v.fakeplate, v.garage,
               v.fuel, v.engine, v.body, v.state, v.depotprice, v.drivingdistance,
               p.name, p.charinfo
        FROM player_vehicles v
        LEFT JOIN players p ON p.citizenid = v.citizenid
        WHERE v.plate LIKE ? OR v.fakeplate LIKE ? OR v.vehicle LIKE ? OR v.citizenid LIKE ?
        ORDER BY v.id DESC
        LIMIT 20
    ]], { like, like, like, like }) or {}

    local results = {}
    for i = 1, #rows do
        local row = rows[i]
        local charinfo = decodeJson(row.charinfo)

        results[#results + 1] = {
            id = row.id,
            citizenid = row.citizenid or 'N/A',
            ownerName = fullName(charinfo, row.name),
            model = row.vehicle or 'unknown',
            hash = row.hash or '',
            plate = row.plate or 'N/A',
            fakeplate = row.fakeplate or '',
            garage = row.garage or 'N/A',
            fuel = tonumber(row.fuel) or 0,
            engine = math.floor(tonumber(row.engine) or 0),
            body = math.floor(tonumber(row.body) or 0),
            state = tonumber(row.state) or 0,
            stateLabel = vehicleStateLabel(row.state),
            depotPrice = tonumber(row.depotprice) or 0,
            drivingDistance = tonumber(row.drivingdistance) or 0,
        }
    end

    return true, results
end)

local function normalizeBolo(row)
    return {
        id = tonumber(row.id),
        type = row.bolo_type or 'person',
        target = row.target or 'Sin objetivo',
        plate = row.plate or '',
        citizenid = row.citizenid or '',
        description = row.description or '',
        priority = row.priority or 'normal',
        status = row.status or 'active',
        createdBy = row.created_by_name or 'N/A',
        createdAt = tostring(row.created_at or ''),
        updatedAt = tostring(row.updated_at or ''),
        closedBy = row.closed_by_name or '',
        closedAt = tostring(row.closed_at or ''),
        closeNotes = row.close_notes or '',
        dispatchAlertId = tonumber(row.dispatch_alert_id),
    }
end

local function boloPriorityToDispatch(priority)
    if priority == 'critical' then return 5, 85 end
    if priority == 'high' then return 4, 60 end
    if priority == 'low' then return 1, 10 end
    return 2, 30
end

lib.callback.register('qbx_mdt:server:getBolos', function(source, status)
    if not hasPoliceAccess(source) then return false, 'no_access' end
    if not rateLimit(source) then return false, 'rate_limited' end

    status = cleanText(status or 'active', 20)
    if status ~= 'active' and status ~= 'closed' and status ~= 'all' then
        status = 'active'
    end

    local rows
    if status == 'all' then
        rows = MySQL.query.await([[
            SELECT *
            FROM qbx_mdt_bolos
            ORDER BY FIELD(status, 'active', 'closed'), updated_at DESC
            LIMIT 60
        ]]) or {}
    else
        rows = MySQL.query.await([[
            SELECT *
            FROM qbx_mdt_bolos
            WHERE status = ?
            ORDER BY updated_at DESC
            LIMIT 40
        ]], { status }) or {}
    end

    local results = {}
    for i = 1, #rows do
        results[#results + 1] = normalizeBolo(rows[i])
    end

    return true, results
end)

lib.callback.register('qbx_mdt:server:createBolo', function(source, data)
    if not hasPoliceAccess(source) then return false, 'no_access' end
    if not rateLimit(source) then return false, 'rate_limited' end
    if type(data) ~= 'table' then return false, 'invalid_payload' end

    local boloType = cleanText(data.type or 'person', 20)
    if boloType ~= 'person' and boloType ~= 'vehicle' and boloType ~= 'area' then
        boloType = 'person'
    end

    local priority = cleanText(data.priority or 'normal', 12)
    if priority ~= 'low' and priority ~= 'normal' and priority ~= 'high' and priority ~= 'critical' then
        priority = 'normal'
    end

    local target = cleanText(data.target, 80)
    local description = cleanText(data.description, 500)
    local plate = cleanText(data.plate, 15)
    local citizenid = cleanText(data.citizenid, 50)

    if #target < 2 then return false, 'target_required' end
    if #description < 5 then return false, 'description_required' end

    local officerCitizenid, officerName = officerIdentity(source)
    local insertId = MySQL.insert.await([[
        INSERT INTO qbx_mdt_bolos
            (bolo_type, target, plate, citizenid, description, priority, status, created_by_citizenid, created_by_name)
        VALUES (?, ?, ?, ?, ?, ?, 'active', ?, ?)
    ]], {
        boloType,
        target,
        plate ~= '' and plate or nil,
        citizenid ~= '' and citizenid or nil,
        description,
        priority,
        officerCitizenid,
        officerName,
    })

    if not insertId then return false, 'db_error' end

    local row = MySQL.single.await('SELECT * FROM qbx_mdt_bolos WHERE id = ? LIMIT 1', { insertId })
    TriggerClientEvent('qbx_mdt:client:bolosUpdated', -1)
    return true, normalizeBolo(row or { id = insertId, bolo_type = boloType, target = target, plate = plate, citizenid = citizenid, description = description, priority = priority, status = 'active', created_by_name = officerName })
end)

lib.callback.register('qbx_mdt:server:closeBolo', function(source, boloId, notes)
    if not hasPoliceAccess(source) then return false, 'no_access' end
    if not rateLimit(source) then return false, 'rate_limited' end

    boloId = tonumber(boloId)
    if not boloId or boloId < 1 then return false, 'invalid_bolo' end

    local existing = MySQL.single.await('SELECT id, status FROM qbx_mdt_bolos WHERE id = ? LIMIT 1', { boloId })
    if not existing then return false, 'not_found' end
    if existing.status == 'closed' then return false, 'already_closed' end

    local officerCitizenid, officerName = officerIdentity(source)
    MySQL.update.await([[
        UPDATE qbx_mdt_bolos
        SET status = 'closed',
            closed_by_citizenid = ?,
            closed_by_name = ?,
            close_notes = ?,
            closed_at = current_timestamp()
        WHERE id = ?
    ]], {
        officerCitizenid,
        officerName,
        cleanText(notes, 300),
        boloId,
    })

    local row = MySQL.single.await('SELECT * FROM qbx_mdt_bolos WHERE id = ? LIMIT 1', { boloId })
    TriggerClientEvent('qbx_mdt:client:bolosUpdated', -1)
    return true, normalizeBolo(row)
end)

lib.callback.register('qbx_mdt:server:createDispatchFromBolo', function(source, boloId)
    if not hasPoliceAccess(source) then return false, 'no_access' end
    if not rateLimit(source) then return false, 'rate_limited' end
    if GetResourceState('nexus_dispatch') ~= 'started' then return false, 'dispatch_not_started' end

    boloId = tonumber(boloId)
    if not boloId or boloId < 1 then return false, 'invalid_bolo' end

    local row = MySQL.single.await('SELECT * FROM qbx_mdt_bolos WHERE id = ? LIMIT 1', { boloId })
    if not row then return false, 'not_found' end
    if row.status == 'closed' then return false, 'closed' end
    if row.dispatch_alert_id then return false, 'already_dispatched' end

    local priority, risk = boloPriorityToDispatch(row.priority)
    local message = cleanText((row.description or '') .. (row.plate and row.plate ~= '' and (' | Placa: ' .. row.plate) or ''), 255)
    local alertId, alert = exports.nexus_dispatch:createAlert({
        type = 'bolo',
        title = ('BOLO #%s - %s'):format(row.id, row.target or 'Objetivo'),
        message = message,
        sourceResource = GetCurrentResourceName(),
        sourcePlayer = source,
        citizenid = row.citizenid,
        risk = risk,
        priority = priority,
    })

    alertId = tonumber(alertId or (alert and alert.id))
    if not alertId then return false, 'dispatch_failed' end

    MySQL.update.await('UPDATE qbx_mdt_bolos SET dispatch_alert_id = ? WHERE id = ?', { alertId, boloId })
    local updated = MySQL.single.await('SELECT * FROM qbx_mdt_bolos WHERE id = ? LIMIT 1', { boloId })

    TriggerClientEvent('qbx_mdt:client:bolosUpdated', -1)
    return true, normalizeBolo(updated)
end)

AddEventHandler('playerDropped', function()
    searchBuckets[source] = nil
end)

CreateThread(function()
    setupDatabase()
    print('[qbx_mdt] BOLO database ready')
end)
