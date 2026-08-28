local QBCore = exports.qbx_core
local lastRequest = {}

local function clamp(value, min, max)
    value = tonumber(value) or min
    if value < min then return min end
    if value > max then return max end
    return value
end

local function cleanString(value, maxLength, fallback)
    value = tostring(value or fallback or '')
    value = value:gsub('[\r\n]', ' ')
    if #value > maxLength then
        value = value:sub(1, maxLength)
    end
    return value
end

local function cleanLongString(value, maxLength)
    value = tostring(value or '')
    value = value:gsub('[\r]', ' ')
    value = value:gsub('[\n]+', ' | ')
    if #value > maxLength then
        value = value:sub(1, maxLength)
    end
    return value
end

local function getPlayer(source)
    return QBCore:GetPlayer(tonumber(source))
end

local function getOfficer(source)
    local player = getPlayer(source)
    local data = player and player.PlayerData
    local charinfo = data and data.charinfo or {}
    local fullName = ((charinfo.firstname or '') .. ' ' .. (charinfo.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')

    return {
        citizenid = data and data.citizenid or nil,
        name = fullName ~= '' and fullName or GetPlayerName(source) or ('ID %s'):format(source),
    }
end

local function isPolice(source)
    local player = getPlayer(source)
    local job = player and player.PlayerData and player.PlayerData.job
    return job and NexusDispatchConfig.policeJobs[job.name] == true
end

local function isAdmin(source)
    source = tonumber(source)
    if source == 0 then return true end
    if GetResourceState('nexus_permissions') ~= 'started' then return false end
    return exports.nexus_permissions:hasPermission(source, 'nexus_dispatch.admin_access')
end

local function hasAccess(source)
    return isPolice(source) or isAdmin(source)
end

local function normalizeRow(row)
    if row and row.x and row.y and row.z then
        row.coords = { x = row.x + 0.0, y = row.y + 0.0, z = row.z + 0.0 }
    end

    if row then
        local typeConfig = NexusDispatchConfig.types[row.type] or NexusDispatchConfig.types.generic
        row.sprite = typeConfig.sprite or 161
        row.color = typeConfig.color or 3
        row.status = row.status or 'open'
    end

    return row
end

local function attachUnits(rows)
    local ids = {}
    for i = 1, #(rows or {}) do
        if rows[i].id then
            ids[#ids + 1] = rows[i].id
        end
    end

    local grouped = NexusDispatchUnits(ids)
    for i = 1, #(rows or {}) do
        rows[i].units = grouped[rows[i].id] or {}
    end
end

local function rateLimit(source)
    local now = GetGameTimer()
    local last = lastRequest[source] or 0
    if now - last < 1000 then
        return false
    end
    lastRequest[source] = now
    return true
end

local function normalizeCoords(coords)
    if type(coords) ~= 'table' then return nil end

    local x = tonumber(coords.x or coords[1])
    local y = tonumber(coords.y or coords[2])
    local z = tonumber(coords.z or coords[3])

    if not x or not y or not z then return nil end
    return { x = x + 0.0, y = y + 0.0, z = z + 0.0 }
end

local function normalizeAlert(data)
    data = type(data) == 'table' and data or {}

    local alertType = cleanString(data.type or data.alertType, 64, 'generic')
    local typeConfig = NexusDispatchConfig.types[alertType] or NexusDispatchConfig.types.generic
    local sourcePlayer = tonumber(data.source or data.sourcePlayer)
    local citizenid = cleanString(data.citizenid, 64, '')

    if not citizenid and sourcePlayer then
        local player = getPlayer(sourcePlayer)
        citizenid = player and player.PlayerData and player.PlayerData.citizenid or nil
    end

    return {
        id = nil,
        type = alertType,
        title = cleanString(data.title, 96, typeConfig.label or 'Incidente'),
        message = cleanString(data.message or data.description, 255, ''),
        coords = normalizeCoords(data.coords),
        zoneId = cleanString(data.zoneId or data.zone_id, 64, ''),
        sourceResource = cleanString(data.sourceResource or GetCurrentResourceName(), 64, ''),
        sourcePlayer = sourcePlayer,
        citizenid = citizenid ~= '' and citizenid or nil,
        gangName = cleanString(data.gangName or data.gang, 64, ''),
        risk = clamp(data.risk, 0, 100),
        priority = clamp(data.priority or typeConfig.priority, 1, 5),
        status = 'open',
        sprite = data.sprite or typeConfig.sprite or 161,
        color = data.color or typeConfig.color or 3,
        createdAt = os.time(),
    }
end

local function dispatchTypeToAis(alertType)
    local ais = NexusDispatchConfig.ais or {}
    local map = ais.typeMap or {}
    return map[alertType] or map.generic or 'organized_crime'
end

local function priorityToAis(priority)
    priority = tonumber(priority) or 1
    if priority >= 4 then return 'critical' end
    if priority >= 3 then return 'high' end
    if priority >= 2 then return 'medium' end
    return 'low'
end

local function createAisCaseFromAlert(source, alert)
    local aisConfig = NexusDispatchConfig.ais or {}
    local resource = aisConfig.resource or 'ais_core'

    if not aisConfig.enabled then return false, 'disabled' end
    if GetResourceState(resource) ~= 'started' then return false, 'ais_not_started' end
    if alert.aisCaseId then return false, 'already_linked' end

    local officer = getOfficer(source)
    local coords = alert.coords or (alert.x and { x = alert.x, y = alert.y, z = alert.z } or nil)
    local caseData = {
        title = ('Dispatch #%s - %s'):format(alert.id, alert.title or 'Incidente'),
        description = alert.message or '',
        case_type = dispatchTypeToAis(alert.type),
        status = 'open',
        priority = priorityToAis(alert.priority),
        created_by = officer.citizenid or 'dispatch',
        assigned_detective = officer.citizenid,
        incident_location = coords or {},
        incident_date = alert.createdAt or os.time(),
        officers_involved = {
            {
                citizenid = officer.citizenid,
                name = officer.name,
                role = 'dispatch_owner',
            }
        },
        notes = json.encode({
            source = 'nexus_dispatch',
            dispatchId = alert.id,
            dispatchType = alert.type,
            sourceResource = alert.sourceResource,
            sourcePlayer = alert.sourcePlayer,
            suspectGang = alert.gangName,
            risk = alert.risk,
            zoneId = alert.zoneId,
        })
    }

    local ok, case = pcall(function()
        return exports[resource]:CreateCase(caseData)
    end)

    if not ok or not case then
        return false, 'ais_failed'
    end

    local caseId = tonumber(case.id)
    local caseNumber = tostring(case.case_number or case.caseNumber or ('AIS-%s'):format(caseId or alert.id))
    local changed = NexusDispatchLinkAisCase(alert.id, caseId, caseNumber)
    if not changed or changed < 1 then
        return false, 'link_failed'
    end

    return true, normalizeRow(NexusDispatchGet(alert.id))
end

local function broadcastAlert(alert)
    for _, playerId in ipairs(GetPlayers()) do
        local target = tonumber(playerId)
        if target and hasAccess(target) then
            TriggerClientEvent('nexus_dispatch:client:alert', target, alert)
        end
    end
end

local function createAlert(data)
    local alert = normalizeAlert(data)
    alert.id = NexusDispatchInsert(alert)
    broadcastAlert(alert)
    return alert.id, alert
end

exports('createAlert', createAlert)

lib.callback.register('nexus_dispatch:server:getRecent', function(source)
    if not hasAccess(source) then return false, 'no_access' end
    if not rateLimit(source) then return false, 'rate_limited' end

    local rows = NexusDispatchRecent(NexusDispatchConfig.maxRecent or 30)
    for i = 1, #rows do
        normalizeRow(rows[i])
    end
    attachUnits(rows)

    return true, rows
end)

lib.callback.register('nexus_dispatch:server:updateAlert', function(source, alertId, status)
    if not hasAccess(source) then return false, 'no_access' end
    if not rateLimit(source) then return false, 'rate_limited' end

    alertId = tonumber(alertId)
    status = tostring(status or '')

    if not alertId or not NexusDispatchConfig.statuses[status] then
        return false, 'invalid'
    end

    local current = NexusDispatchGet(alertId)
    if not current then return false, 'not_found' end
    if current.status == 'closed' then return false, 'closed' end

    local changed = NexusDispatchUpdate(alertId, status, getOfficer(source))
    if not changed or changed < 1 then return false, 'not_updated' end

    local updated = normalizeRow(NexusDispatchGet(alertId))
    for _, playerId in ipairs(GetPlayers()) do
        local target = tonumber(playerId)
        if target and hasAccess(target) then
            TriggerClientEvent('nexus_dispatch:client:updated', target, updated)
        end
    end

    return true, updated
end)

lib.callback.register('nexus_dispatch:server:setUnitStatus', function(source, alertId, status)
    if not hasAccess(source) then return false, 'no_access' end
    if not rateLimit(source) then return false, 'rate_limited' end

    alertId = tonumber(alertId)
    status = cleanString(status, 24, 'assigned')

    local allowed = {
        assigned = true,
        enroute = true,
        arrived = true,
        clear = true,
    }

    if not alertId or not allowed[status] then return false, 'invalid' end

    local current = NexusDispatchGet(alertId)
    if not current then return false, 'not_found' end
    if current.status == 'closed' then return false, 'closed' end

    local officer = getOfficer(source)
    if not officer.citizenid then return false, 'no_citizenid' end

    if status == 'clear' then
        NexusDispatchRemoveUnit(alertId, officer.citizenid)
    else
        NexusDispatchUpsertUnit(alertId, officer, status)
        if status == 'assigned' and not current.assignedCitizenid then
            NexusDispatchUpdate(alertId, 'assigned', officer)
        elseif (status == 'enroute' or status == 'arrived') and current.status ~= 'enroute' then
            NexusDispatchUpdate(alertId, 'enroute', officer)
        end
    end

    local updated = normalizeRow(NexusDispatchGet(alertId))
    attachUnits({ updated })

    for _, playerId in ipairs(GetPlayers()) do
        local target = tonumber(playerId)
        if target and hasAccess(target) then
            TriggerClientEvent('nexus_dispatch:client:updated', target, updated)
        end
    end

    return true, updated
end)

lib.callback.register('nexus_dispatch:server:closeAlert', function(source, alertId, result, notes)
    if not hasAccess(source) then return false, 'no_access' end
    if not rateLimit(source) then return false, 'rate_limited' end

    alertId = tonumber(alertId)
    if not alertId then return false, 'invalid' end

    local current = NexusDispatchGet(alertId)
    if not current then return false, 'not_found' end
    if current.status == 'closed' then return false, 'closed' end

    result = cleanString(result, 64, 'resolved')
    notes = cleanLongString(notes, 1000)

    local changed = NexusDispatchUpdate(alertId, 'closed', getOfficer(source), {
        result = result,
        notes = notes ~= '' and notes or nil,
    })
    if not changed or changed < 1 then return false, 'not_updated' end

    local updated = normalizeRow(NexusDispatchGet(alertId))
    for _, playerId in ipairs(GetPlayers()) do
        local target = tonumber(playerId)
        if target and hasAccess(target) then
            TriggerClientEvent('nexus_dispatch:client:updated', target, updated)
        end
    end

    return true, updated
end)

lib.callback.register('nexus_dispatch:server:addNote', function(source, alertId, note)
    if not hasAccess(source) then return false, 'no_access' end
    if not rateLimit(source) then return false, 'rate_limited' end

    alertId = tonumber(alertId)
    note = cleanLongString(note, 500)

    if not alertId or note == '' then return false, 'invalid' end

    local current = NexusDispatchGet(alertId)
    if not current then return false, 'not_found' end
    if current.status == 'closed' then return false, 'closed' end

    local officer = getOfficer(source)
    local stampedNote = ('[%s] %s: %s'):format(os.date('%H:%M'), officer.name, note)
    local changed = NexusDispatchAppendNote(alertId, stampedNote)
    if not changed or changed < 1 then return false, 'not_updated' end

    local updated = normalizeRow(NexusDispatchGet(alertId))
    for _, playerId in ipairs(GetPlayers()) do
        local target = tonumber(playerId)
        if target and hasAccess(target) then
            TriggerClientEvent('nexus_dispatch:client:updated', target, updated)
        end
    end

    return true, updated
end)

lib.callback.register('nexus_dispatch:server:createAisCase', function(source, alertId)
    if not hasAccess(source) then return false, 'no_access' end
    if not rateLimit(source) then return false, 'rate_limited' end

    alertId = tonumber(alertId)
    if not alertId then return false, 'invalid' end

    local alert = normalizeRow(NexusDispatchGet(alertId))
    if not alert then return false, 'not_found' end
    if alert.aisCaseId then return false, 'already_linked' end

    local ok, result = createAisCaseFromAlert(source, alert)
    if not ok then return false, result end

    for _, playerId in ipairs(GetPlayers()) do
        local target = tonumber(playerId)
        if target and hasAccess(target) then
            TriggerClientEvent('nexus_dispatch:client:updated', target, result)
        end
    end

    return true, result
end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    NexusDispatchEnsureDatabase()
    print('[nexus_dispatch] dispatch policial cargado')
end)

AddEventHandler('playerDropped', function()
    lastRequest[source] = nil
end)
