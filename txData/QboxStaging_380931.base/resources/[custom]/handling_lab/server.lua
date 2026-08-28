local lastCommandAt = {}

local function notify(source, message)
    TriggerClientEvent('handling_lab:client:notify', source, message)
end

local function canUse(source)
    if source <= 0 then return false end

    if Config.RequireAce then
        local ready = GetResourceState('nexus_permissions') == 'started'
        local allowed = ready and exports.nexus_permissions:hasPermission(source, 'handling_lab.use')
        if not allowed then
            notify(source, 'Sin permiso.')
            return false
        end
    end

    local now = GetGameTimer()
    if now - (lastCommandAt[source] or 0) < Config.CommandCooldownMs then
        return false
    end

    lastCommandAt[source] = now
    return true
end

RegisterCommand('handlingtest', function(source, args)
    if not canUse(source) then return end

    local mode = string.lower(args[1] or '')
    if mode ~= 'stock' and mode ~= 'v1' and mode ~= 'v2' and mode ~= 'v3' and mode ~= 'v4'
        and mode ~= 'brakea' and mode ~= 'brakeb' and mode ~= 'brakec' and mode ~= 'braked'
        and mode ~= 'sport' then
        notify(source, 'Uso: /handlingtest stock|v1|v2|v3|v4|brakea|brakeb|brakec|braked (sport = alias de v2)')
        return
    end

    TriggerClientEvent('handling_lab:client:command', source, 'test', mode)
end, false)

RegisterCommand('handlingreset', function(source)
    if not canUse(source) then return end
    TriggerClientEvent('handling_lab:client:command', source, 'reset')
end, false)

RegisterCommand('handlingcheck', function(source)
    if not canUse(source) then return end
    TriggerClientEvent('handling_lab:client:command', source, 'check')
end, false)

RegisterCommand('handlingstats', function(source, args)
    if not canUse(source) then return end

    local option = string.lower(args[1] or 'toggle')
    if option ~= 'toggle' and option ~= 'reset' then
        notify(source, 'Uso: /handlingstats [reset]')
        return
    end

    TriggerClientEvent('handling_lab:client:command', source, 'stats', option)
end, false)

AddEventHandler('playerDropped', function()
    lastCommandAt[source] = nil
end)
