local function formatEntry(entry)
    local pct = 0
    if entry.requiredXp and entry.requiredXp > 0 then
        pct = math.floor((entry.currentXp / entry.requiredXp) * 100)
    end

    return ('Nivel %s | Rep %s | %s/%s XP (%s%%)'):format(
        entry.level or 1,
        entry.reputation or 0,
        entry.currentXp or 0,
        entry.requiredXp or 0,
        pct
    )
end

local function openProgression()
    local data = lib.callback.await('nexus_progression:server:get', false) or {}
    local options = {}

    for domain, meta in pairs(NexusProgressionConfig.domains) do
        local entry = data[domain] or {
            level = 1,
            reputation = 0,
            currentXp = 0,
            requiredXp = NexusProgressionUtils.getRequiredXp(1),
        }

        options[#options + 1] = {
            title = meta.label,
            description = formatEntry(entry),
            icon = meta.icon,
            progress = entry.requiredXp > 0 and math.floor((entry.currentXp / entry.requiredXp) * 100) or 0,
            colorScheme = 'blue',
        }
    end

    lib.registerContext({
        id = 'nexus_progression_menu',
        title = 'Progresion NEXUS',
        options = options,
    })

    lib.showContext('nexus_progression_menu')
end

exports('openProgression', openProgression)

RegisterCommand('progreso', openProgression, false)

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Wait(500)
    print('[nexus_progression] progresion cliente cargada')
end)
