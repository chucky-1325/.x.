local tabletOpen = false

local function clearTabletFocus()
    tabletOpen = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)

    if SetNuiZIndex then
        SetNuiZIndex(0)
    end

    SendNUIMessage({ action = 'close' })
end

local function openExternal(app)
    if type(app) ~= 'table' or type(app.external) ~= 'table' then return false end

    local external = app.external
    if GetResourceState(external.resource) ~= 'started' then return false end
    if external.resource == 'qbx_mdt' and external.export == 'openMdt' then
        clearTabletFocus()
        Wait(100)
        exports.qbx_mdt:openMdt()
        return true
    end

    return false
end

local function notify(description, notifyType)
    if GetResourceState('nexus_ui') == 'started' then
        exports.nexus_ui:notify({
            title = 'Tablet',
            description = description,
            type = notifyType or 'inform',
        })
        return
    end

    lib.notify({ title = 'Tablet', description = description, type = notifyType or 'inform' })
end

local function closeTablet()
    clearTabletFocus()
end

local function localFallbackDashboard()
    return {
        identity = { callsign = 'NEXUS/CLANDESTINE', mode = 'illegal' },
        gang = { name = 'none', label = 'Red clandestina', tag = 'NET', rankLabel = 'Offline' },
        progress = {
            criminal = { level = 1, reputation = 0 },
            crafting = { level = 1, reputation = 0 },
        },
        assets = { locations = {}, garageVehicles = {} },
        contracts = { contracts = {}, active = nil },
        operations = { operations = {}, active = nil },
        operationLogs = {},
        members = { members = {}, permissions = {}, rank = 0, isBoss = false },
        audit = {},
        labs = { labs = {}, logs = {} },
        laundering = { locations = {}, logs = {} },
        markets = {},
        territories = {},
        airdrop = nil,
    }
end

local function openIllegalTablet(app)
    tabletOpen = true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    if SetNuiZIndex then
        SetNuiZIndex(60)
    end
    SendNUIMessage({
        action = 'open',
        app = app,
        dashboard = localFallbackDashboard(),
    })

    CreateThread(function()
        local callbackOk, ok, payload = pcall(function()
            return lib.callback.await('nexus_tablet:server:getIllegalDashboard', false)
        end)

        if not tabletOpen then return end

        if callbackOk and ok then
            SendNUIMessage({ action = 'update', dashboard = payload })
            return
        end

        notify((payload == 'rate_limited' and 'Espera un momento.') or 'Dashboard parcial: algunos modulos no respondieron.', 'warning')
    end)
end

local function openTablet(appId)
    appId = appId or NexusTabletConfig.defaultApp

    local ok, app = lib.callback.await('nexus_tablet:server:canOpen', false, appId)
    if not ok then
        if GetResourceState('nexus_ui') == 'started' then
            exports.nexus_ui:notify({
                title = 'Tablet',
                description = 'No tienes acceso a esta aplicacion.',
                type = 'error',
            })
        else
            lib.notify({
                title = 'Tablet',
                description = 'No tienes acceso a esta aplicacion.',
                type = 'error',
            })
        end
        return
    end

    if openExternal(app) then return end
    if appId == 'illegal' then
        openIllegalTablet(app)
        return
    end

    if GetResourceState('nexus_ui') == 'started' then
        exports.nexus_ui:notify({
            title = app.label or 'Tablet',
            description = 'Modulo preparado para la siguiente fase.',
            type = 'inform',
        })
    end
end

exports('openTablet', openTablet)
exports('closeTablet', closeTablet)

local function runTabletAction(action)
    if action == 'refresh' then
        local callbackOk, ok, payload = pcall(function()
            return lib.callback.await('nexus_tablet:server:getIllegalDashboard', false)
        end)

        if callbackOk and ok and tabletOpen then
            SendNUIMessage({ action = 'update', dashboard = payload })
        else
            notify('No se pudo actualizar el dashboard.', 'error')
        end
        return
    end

    closeTablet()
    Wait(150)

    if action == 'contracts' then
        if GetResourceState('nexus_contracts') == 'started' then
            exports.nexus_contracts:openContracts()
        else
            notify('Contratos no iniciado.', 'error')
        end
    elseif action == 'members' then
        if GetResourceState('nexus_gangs') == 'started' then
            exports.nexus_gangs:openGangManagement()
        else
            notify('Bandas no iniciado.', 'error')
        end
    elseif action == 'operations' then
        if GetResourceState('nexus_operations') == 'started' then
            exports.nexus_operations:openOperations()
        else
            notify('Operaciones no iniciado.', 'error')
        end
    elseif action == 'labs' then
        if GetResourceState('nexus_labs') == 'started' then
            exports.nexus_labs:openLabs()
        else
            notify('Laboratorios no iniciado.', 'error')
        end
    elseif action == 'laundering' then
        if GetResourceState('nexus_laundering') == 'started' then
            exports.nexus_laundering:openLaundering()
        else
            notify('Lavado no iniciado.', 'error')
        end
    elseif action == 'blackmarket' then
        if GetResourceState('nexus_blackmarket') == 'started' then
            ExecuteCommand('blackmarketnear')
        else
            notify('Mercado negro no iniciado.', 'error')
        end
    elseif action == 'assets' then
        if GetResourceState('nexus_gangs') == 'started' then
            exports.nexus_gangs:openGangAssets()
        else
            notify('Bandas no iniciado.', 'error')
        end
    elseif action == 'territories' then
        if GetResourceState('nexus_territories') == 'started' then
            exports.nexus_territories:openTerritories()
        else
            notify('Territorios no iniciado.', 'error')
        end
    elseif action == 'crafting' then
        if GetResourceState('nexus_crafting') == 'started' then
            exports.nexus_crafting:openCrafting('illegal_bench')
        else
            notify('Crafting no iniciado.', 'error')
        end
    else
        notify('Accion no disponible.', 'error')
    end
end

RegisterNUICallback('close', function(_, cb)
    closeTablet()
    cb({ ok = true })
end)

RegisterNUICallback('action', function(data, cb)
    cb({ ok = true })
    CreateThread(function()
        runTabletAction(data and data.action)
    end)
end)

RegisterCommand(NexusTabletConfig.command, function(_, args)
    openTablet(args and args[1] or NexusTabletConfig.defaultApp)
end, false)

RegisterKeyMapping(NexusTabletConfig.command, 'Abrir tablet NEXUS', 'keyboard', 'F7')

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Wait(500)
    print('[nexus_tablet] shell modular cargado')
end)

CreateThread(function()
    while true do
        if tabletOpen and IsControlJustReleased(0, 322) then
            closeTablet()
        end

        Wait(tabletOpen and 0 or 500)
    end
end)
