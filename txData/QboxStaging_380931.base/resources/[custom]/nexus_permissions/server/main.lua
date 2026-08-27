local SourceCitizenid = {}
local PermissionCache = {}
local RateLimit = {}
local RATE_LIMIT_MS = 3000

local ROLE_PATTERN = '^[a-z_]+$'
local MAX_CITIZENID_LEN = 64
local MAX_ROLE_LEN = 32
local MAX_REASON_CHARS = 255

local function notifyConsole(message)
    print(('[nexus_permissions] %s'):format(message))
end

-- ----- Rate limit (previo a cualquier escritura, incluida la auditoria) -----

local function isRateLimited(source)
    local now = GetGameTimer()
    local last = RateLimit[source]
    if last and (now - last) < RATE_LIMIT_MS then
        return true
    end
    RateLimit[source] = now
    return false
end

-- ----- Normalizacion y saneado -----

-- Solo para citizenid/role: charset puramente ASCII, 1 byte = 1 caracter
-- siempre, asi que el corte por bytes es intrinsecamente seguro. NUNCA se
-- usa para "reason".
local function truncate(value, maxLen)
    if type(value) ~= 'string' then return nil end
    if #value > maxLen then return value:sub(1, maxLen) end
    return value
end

-- Truncado seguro para UTF-8 (tildes, emoji, cualquier multibyte). Corta por
-- CARACTER (utf8.offset), nunca a mitad de una secuencia. Si la cadena no es
-- UTF-8 valido, se descarta entera en vez de arriesgar una insercion
-- corrupta. Es la UNICA funcion que produce el valor de "reason" usado en
-- cualquier sitio -- operativo o de auditoria -- a partir de este punto.
local function safeReason(rawReason)
    if type(rawReason) ~= 'string' or rawReason == '' then return nil end

    local charCount = utf8.len(rawReason)
    if not charCount then
        -- UTF-8 invalido de entrada: no propagar nada corrupto.
        return nil
    end

    if charCount <= MAX_REASON_CHARS then
        return rawReason
    end

    -- utf8.offset(s, n) da el byte donde EMPIEZA el caracter n-esimo. El
    -- byte donde empieza el caracter (MAX_REASON_CHARS + 1) marca el limite
    -- exacto: todo lo anterior son los primeros 255 caracteres completos.
    local cutByte = utf8.offset(rawReason, MAX_REASON_CHARS + 1)
    return rawReason:sub(1, cutByte - 1)
end

-- citizenid: NO se fija a una longitud exacta (el formato de generacion de
-- qbx_core es configurable) -- solo se acota al ancho de columna y a un
-- charset alfanumerico razonable. Se evalua sobre el valor SIN truncar.
local function isValidCitizenidFormat(citizenid)
    return type(citizenid) == 'string'
        and #citizenid >= 1
        and #citizenid <= MAX_CITIZENID_LEN
        and citizenid:match('^[A-Za-z0-9]+$') ~= nil
end

local function isValidRoleFormat(roleName)
    return type(roleName) == 'string'
        and #roleName > 0
        and #roleName <= MAX_ROLE_LEN
        and roleName:match(ROLE_PATTERN) ~= nil
end

-- Unico punto que lee args[1..] -- el motivo ya sale saneado (UTF-8-safe).
-- citizenid/roleName salen SIN TOCAR: se usan tal cual para validar y para
-- cualquier operacion real (citizenExists, roleExists, assignmentExists,
-- INSERT, DELETE). Nunca se trunca antes de esas comprobaciones.
local function rawArgs(args)
    local citizenid = args[1]
    local roleName = args[2]
    local reasonRaw = args[3] and table.concat(args, ' ', 3) or nil
    return citizenid, roleName, safeReason(reasonRaw)
end

-- Solo para auditoria en las ramas de rechazo PREVIAS a la validacion de
-- formato (sin permiso, sin argumentos). reason ya viene saneado desde
-- rawArgs -- no se vuelve a tocar aqui, solo se acotan citizenid/role.
local function auditSafe(citizenid, roleName, reason)
    return truncate(citizenid, MAX_CITIZENID_LEN), truncate(roleName, MAX_ROLE_LEN), reason
end

-- ----- Auditoria -----

local function auditLog(data)
    MySQL.insert.await([[
        INSERT INTO nexus_permission_audit_log
            (actor_citizenid, actor_source, actor_identifier, target_citizenid, target_identifier, permission, reason, executed_via, result)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        data.actor_citizenid,
        data.actor_source,
        data.actor_identifier,
        data.target_citizenid,
        data.target_identifier,
        data.permission,
        data.reason,
        data.executed_via,
        data.result,
    })
end

-- ----- Cache -----

local function loadPermissionsForCitizen(citizenid)
    local rows = MySQL.query.await([[
        SELECT g.permission
        FROM nexus_character_roles cr
        JOIN nexus_permission_role_grants g ON g.role_name = cr.role_name
        WHERE cr.citizenid = ?
    ]], { citizenid }) or {}

    local permissions = {}
    for i = 1, #rows do
        permissions[rows[i].permission] = true
    end

    PermissionCache[citizenid] = { permissions = permissions, loadedAt = os.time() }
end

local function clearPermissionsForCitizen(citizenid)
    PermissionCache[citizenid] = nil
end

-- Recarga basada en SourceCitizenid (fuente de verdad de "quien esta
-- conectado ahora"), no en si la cache tenia o no una entrada previa.
local function isCurrentlyConnected(citizenid)
    for _, cid in pairs(SourceCitizenid) do
        if cid == citizenid then return true end
    end
    return false
end

local function reloadIfNeeded(citizenid)
    if isCurrentlyConnected(citizenid) then
        loadPermissionsForCitizen(citizenid)
    else
        clearPermissionsForCitizen(citizenid)
    end
end

-- ----- Ciclo de vida -----

-- La firma real es function(player), no function(source) -- confirmado en
-- qbx_core/server/player.lua:1031 (TriggerEvent con `self`).
AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    local source = player and player.PlayerData and player.PlayerData.source
    local citizenid = player and player.PlayerData and player.PlayerData.citizenid
    if not source or not citizenid then return end

    SourceCitizenid[source] = citizenid
    loadPermissionsForCitizen(citizenid)
end)

local function cleanupSource(source)
    local citizenid = SourceCitizenid[source]
    if citizenid then clearPermissionsForCitizen(citizenid) end
    SourceCitizenid[source] = nil
    RateLimit[source] = nil
end

AddEventHandler('QBCore:Server:OnPlayerUnload', function(source)
    cleanupSource(source)
end)

AddEventHandler('playerDropped', function(_)
    cleanupSource(source)
end)

-- Al arrancar/reiniciar este recurso con jugadores ya conectados,
-- QBCore:Server:PlayerLoaded no se vuelve a disparar para ellos -- hay que
-- poblar la cache manualmente iterando los jugadores ya cargados.
AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    local players = GetPlayers()
    for i = 1, #players do
        local source = tonumber(players[i])
        local player = source and exports.qbx_core:GetPlayer(source)
        local citizenid = player and player.PlayerData and player.PlayerData.citizenid
        if source and citizenid then
            SourceCitizenid[source] = citizenid
            loadPermissionsForCitizen(citizenid)
        end
    end

    notifyConsole(('catalogo de roles y auditoria cargados (Fase 1, sin autorizacion de gameplay) | %s jugador(es) ya conectado(s) indexado(s)'):format(#players))
end)

-- ----- Validacion contra BD -----

local function citizenExists(citizenid)
    return MySQL.scalar.await('SELECT citizenid FROM players WHERE citizenid = ?', { citizenid }) ~= nil
end

local function roleExists(roleName)
    return MySQL.scalar.await('SELECT role_name FROM nexus_permission_roles WHERE role_name = ?', { roleName }) ~= nil
end

local function assignmentExists(citizenid, roleName)
    return MySQL.scalar.await('SELECT citizenid FROM nexus_character_roles WHERE citizenid = ? AND role_name = ?', { citizenid, roleName }) ~= nil
end

local function actorSourceLabel(source)
    if source == 0 then return 'console' end
    return tostring(source)
end

local function actorIdentifierLabel(source)
    if source == 0 then return 'console' end
    return GetPlayerIdentifierByType(source, 'license2') or ('unknown_source:%s'):format(source)
end

-- citizenid del propio ejecutor, SOLO si tiene un PJ activo (fuente:
-- SourceCitizenid, la misma tabla que ya usamos para la cache).
local function actorCitizenidLabel(source)
    if source == 0 then return nil end
    return SourceCitizenid[source]
end

local function actorAllowed(source)
    return source == 0 or IsPlayerAceAllowed(source, 'nexus.permissions.manage')
end

-- ----- Comandos tecnicos -----

RegisterCommand('grantrole', function(source, args)
    if isRateLimited(source) then return end

    local actorSource = actorSourceLabel(source)
    local actorIdentifier = actorIdentifierLabel(source)
    local actorCitizenid = actorCitizenidLabel(source)
    local citizenid, roleName, reason = rawArgs(args)
    local auditCitizenid, auditRole, auditReason = auditSafe(citizenid, roleName, reason)
    local auditPermissionLabel = auditRole and ('role:%s'):format(auditRole) or 'role:unknown'

    if not actorAllowed(source) then
        auditLog({ actor_citizenid = actorCitizenid, actor_source = actorSource, actor_identifier = actorIdentifier,
            target_citizenid = auditCitizenid, permission = auditPermissionLabel, reason = auditReason,
            executed_via = 'grantRole', result = 'denied' })
        return
    end

    if not citizenid or not roleName then
        notifyConsole('Uso: grantrole <citizenid> <role> [motivo]')
        auditLog({ actor_citizenid = actorCitizenid, actor_source = actorSource, actor_identifier = actorIdentifier,
            target_citizenid = auditCitizenid, permission = auditPermissionLabel, reason = auditReason,
            executed_via = 'grantRole', result = 'denied' })
        return
    end

    if not isValidCitizenidFormat(citizenid) or not isValidRoleFormat(roleName) then
        notifyConsole('Formato invalido de citizenid o role.')
        auditLog({ actor_citizenid = actorCitizenid, actor_source = actorSource, actor_identifier = actorIdentifier,
            target_citizenid = auditCitizenid, permission = auditPermissionLabel, reason = auditReason,
            executed_via = 'grantRole', result = 'denied' })
        return
    end

    -- A partir de aqui citizenid/roleName ya estan garantizados dentro de
    -- limites -- se usan SIN truncar en todo lo operativo de abajo.
    local permissionLabel = ('role:%s'):format(roleName)

    if not citizenExists(citizenid) then
        notifyConsole(('citizenid no encontrado: %s'):format(citizenid))
        auditLog({ actor_citizenid = actorCitizenid, actor_source = actorSource, actor_identifier = actorIdentifier,
            target_citizenid = citizenid, permission = permissionLabel, reason = reason,
            executed_via = 'grantRole', result = 'denied' })
        return
    end

    if not roleExists(roleName) then
        notifyConsole(('rol no encontrado: %s'):format(roleName))
        auditLog({ actor_citizenid = actorCitizenid, actor_source = actorSource, actor_identifier = actorIdentifier,
            target_citizenid = citizenid, permission = permissionLabel, reason = reason,
            executed_via = 'grantRole', result = 'denied' })
        return
    end

    -- Escritura + auditoria en una sola transaccion atomica. Forma real
    -- confirmada en oxmysql/dist/build.js:27173-27193 (parseTransaction):
    -- cada elemento es {query, params} emparejado, NO dos arrays paralelos.
    local ok = MySQL.transaction.await({
        {
            [[ INSERT INTO nexus_character_roles (citizenid, role_name, granted_by, reason)
               VALUES (?, ?, ?, ?)
               ON DUPLICATE KEY UPDATE granted_by = VALUES(granted_by), reason = VALUES(reason), granted_at = CURRENT_TIMESTAMP ]],
            { citizenid, roleName, actorIdentifier, reason },
        },
        {
            [[ INSERT INTO nexus_permission_audit_log
                   (actor_citizenid, actor_source, actor_identifier, target_citizenid, target_identifier, permission, reason, executed_via, result)
               VALUES (?, ?, ?, ?, NULL, ?, ?, 'grantRole', 'success') ]],
            { actorCitizenid, actorSource, actorIdentifier, citizenid, permissionLabel, reason },
        },
    })

    if not ok then
        notifyConsole(('ERROR: transaccion fallida al conceder %s a %s'):format(roleName, citizenid))
        auditLog({ actor_citizenid = actorCitizenid, actor_source = actorSource, actor_identifier = actorIdentifier,
            target_citizenid = citizenid, permission = permissionLabel, reason = reason,
            executed_via = 'grantRole', result = 'error' })
        return
    end

    reloadIfNeeded(citizenid)
    notifyConsole(('rol %s concedido a %s'):format(roleName, citizenid))
end, false)

RegisterCommand('revokerole', function(source, args)
    if isRateLimited(source) then return end

    local actorSource = actorSourceLabel(source)
    local actorIdentifier = actorIdentifierLabel(source)
    local actorCitizenid = actorCitizenidLabel(source)
    local citizenid, roleName, reason = rawArgs(args)
    local auditCitizenid, auditRole, auditReason = auditSafe(citizenid, roleName, reason)
    local auditPermissionLabel = auditRole and ('role:%s'):format(auditRole) or 'role:unknown'

    if not actorAllowed(source) then
        auditLog({ actor_citizenid = actorCitizenid, actor_source = actorSource, actor_identifier = actorIdentifier,
            target_citizenid = auditCitizenid, permission = auditPermissionLabel, reason = auditReason,
            executed_via = 'revokeRole', result = 'denied' })
        return
    end

    if not citizenid or not roleName then
        notifyConsole('Uso: revokerole <citizenid> <role> [motivo]')
        auditLog({ actor_citizenid = actorCitizenid, actor_source = actorSource, actor_identifier = actorIdentifier,
            target_citizenid = auditCitizenid, permission = auditPermissionLabel, reason = auditReason,
            executed_via = 'revokeRole', result = 'denied' })
        return
    end

    if not isValidCitizenidFormat(citizenid) or not isValidRoleFormat(roleName) then
        notifyConsole('Formato invalido de citizenid o role.')
        auditLog({ actor_citizenid = actorCitizenid, actor_source = actorSource, actor_identifier = actorIdentifier,
            target_citizenid = auditCitizenid, permission = auditPermissionLabel, reason = auditReason,
            executed_via = 'revokeRole', result = 'denied' })
        return
    end

    local permissionLabel = ('role:%s'):format(roleName)

    if not assignmentExists(citizenid, roleName) then
        notifyConsole(('asignacion inexistente: %s no tiene el rol %s'):format(citizenid, roleName))
        auditLog({ actor_citizenid = actorCitizenid, actor_source = actorSource, actor_identifier = actorIdentifier,
            target_citizenid = citizenid, permission = permissionLabel, reason = reason,
            executed_via = 'revokeRole', result = 'denied' })
        return
    end

    local ok = MySQL.transaction.await({
        {
            'DELETE FROM nexus_character_roles WHERE citizenid = ? AND role_name = ?',
            { citizenid, roleName },
        },
        {
            [[ INSERT INTO nexus_permission_audit_log
                   (actor_citizenid, actor_source, actor_identifier, target_citizenid, target_identifier, permission, reason, executed_via, result)
               VALUES (?, ?, ?, ?, NULL, ?, ?, 'revokeRole', 'success') ]],
            { actorCitizenid, actorSource, actorIdentifier, citizenid, permissionLabel, reason },
        },
    })

    if not ok then
        notifyConsole(('ERROR: transaccion fallida al retirar %s de %s'):format(roleName, citizenid))
        auditLog({ actor_citizenid = actorCitizenid, actor_source = actorSource, actor_identifier = actorIdentifier,
            target_citizenid = citizenid, permission = permissionLabel, reason = reason,
            executed_via = 'revokeRole', result = 'error' })
        return
    end

    reloadIfNeeded(citizenid)
    notifyConsole(('rol %s retirado de %s'):format(roleName, citizenid))
end, false)
