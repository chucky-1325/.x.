local spawnedPeds = {}
local textUiVisible = false
local activeMarket = nil
local lastOpenAttempt = 0
local lastOpenLocation = nil

local function notify(description, notifyType)
    if GetResourceState('nexus_ui') == 'started' then
        exports.nexus_ui:notify({
            title = 'Mercado negro',
            description = description,
            type = notifyType or 'inform',
        })
        return
    end

    lib.notify({ title = 'Mercado negro', description = description, type = notifyType or 'inform' })
end

local function requestModel(model)
    local hash = joaat(model)
    if not IsModelInCdimage(hash) then return nil end

    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do
        Wait(0)
    end

    return HasModelLoaded(hash) and hash or nil
end

local function setTextUi(visible, text)
    if visible and not textUiVisible then
        lib.showTextUI(text or '[E] Hablar', {
            position = 'left-center',
            icon = 'user-secret',
        })
        textUiVisible = true
    elseif not visible and textUiVisible then
        lib.hideTextUI()
        textUiVisible = false
    end
end

local function errorMessage(reason)
    if reason == 'no_access' then return 'Necesitas contactos criminales o reputacion.' end
    if reason == 'no_location_access' then return 'Ese contacto todavia no confia en ti.' end
    if reason == 'too_far' then return 'Estas demasiado lejos del contacto.' end
    if reason == 'rate_limited' then return 'Espera un momento.' end
    return 'El contacto no responde.'
end

local function openMarket(locationId)
    if type(locationId) ~= 'string' then return end

    local now = GetGameTimer()
    if lastOpenLocation == locationId and now - lastOpenAttempt < 1500 then
        return
    end

    lastOpenLocation = locationId
    lastOpenAttempt = now

    print(('[nexus_blackmarket] opening market: %s'):format(locationId))

    local callbackOk, ok, payload = pcall(function()
        return lib.callback.await('nexus_blackmarket:server:getMarket', false, locationId)
    end)

    if not callbackOk then
        print(('[nexus_blackmarket] callback error: %s'):format(ok))
        notify('Error abriendo mercado. Revisa F8/txAdmin.', 'error')
        return
    end

    if not ok then
        print(('[nexus_blackmarket] market rejected: %s -> %s'):format(locationId, tostring(payload)))
        notify(errorMessage(payload), 'error')
        return
    end

    activeMarket = payload.locationId
    local options = {}

    for i = 1, #(payload.catalog or {}) do
        local entry = payload.catalog[i]
        local missing = #(entry.missing or {}) > 0 and (' | Falta: %s'):format(table.concat(entry.missing, ', ')) or ''
        local discount = entry.discount and entry.discount > 0 and (' | Desc %s%%'):format(entry.discount) or ''
        options[#options + 1] = {
            title = entry.label,
            description = ('$%s %s | Stock %s | Heat item %s | Heat zona %s%s%s'):format(entry.price, entry.moneyType, entry.stock, entry.heat, entry.locationHeat or payload.heat or 0, discount, missing),
            icon = entry.unlocked and 'scroll' or 'lock',
            disabled = not entry.unlocked or entry.stock <= 0,
            onSelect = function()
                TriggerServerEvent('nexus_blackmarket:server:buy', activeMarket, entry.id)
            end,
        }
    end

    print(('[nexus_blackmarket] market loaded: %s items=%s'):format(payload.locationId, #options))

    if #options == 0 then
        notify('El catalogo esta vacio.', 'error')
        return
    end

    lib.registerContext({
        id = 'nexus_blackmarket_menu',
        title = ('%s | Heat %s'):format(payload.label, payload.heat or 0),
        options = options,
    })

    lib.showContext('nexus_blackmarket_menu')
end

local function getNearestLocation(maxDistance)
    local coords = GetEntityCoords(PlayerPedId())
    local nearest, nearestDistance = nil, maxDistance or 2.5

    for locationId, location in pairs(NexusBlackmarketConfig.locations) do
        local distance = #(coords - location.coords)
        if distance <= nearestDistance then
            nearest = locationId
            nearestDistance = distance
        end
    end

    return nearest, nearestDistance
end

local function openNearestMarket()
    local locationId = getNearestLocation(NexusBlackmarketConfig.worldUi.interactDistance + 1.0)
    if not locationId then
        notify('No hay contacto cerca.', 'error')
        return
    end

    openMarket(locationId)
end

local function spawnContacts()
    for locationId, location in pairs(NexusBlackmarketConfig.locations) do
        local hash = requestModel(location.model)
        if hash then
            local ped = CreatePed(4, hash, location.coords.x, location.coords.y, location.coords.z - 1.0, location.heading or 0.0, false, false)
            SetEntityInvincible(ped, true)
            SetBlockingOfNonTemporaryEvents(ped, true)
            FreezeEntityPosition(ped, true)
            if location.scenario then
                TaskStartScenarioInPlace(ped, location.scenario, 0, true)
            end
            spawnedPeds[locationId] = ped
            SetModelAsNoLongerNeeded(hash)
        end
    end
end

local function cleanupContacts()
    for _, ped in pairs(spawnedPeds) do
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end

    spawnedPeds = {}
end

exports('openMarket', openMarket)

RegisterCommand(NexusBlackmarketConfig.command, function(_, args)
    openMarket(args[1] or 'rancho_contact')
end, false)

RegisterCommand(NexusBlackmarketConfig.nearestCommand, openNearestMarket, false)

RegisterNetEvent('nexus_blackmarket:client:refresh', function(locationId)
    if activeMarket == locationId then
        openMarket(locationId)
    end
end)

RegisterNetEvent('nexus_blackmarket:client:policeAlert', function(data)
    if type(data) ~= 'table' or not data.coords then return end
    SetNewWaypoint(data.coords.x, data.coords.y)
    notify(('Posible compra clandestina: %s | Heat %s'):format(data.label or 'desconocido', data.heat or 0), 'warning')
end)

CreateThread(function()
    while true do
        local sleep = 800
        local nearest = nil

        if NexusBlackmarketConfig.worldUi.enabled then
            local coords = GetEntityCoords(PlayerPedId())
            for locationId, location in pairs(NexusBlackmarketConfig.locations) do
                local distance = #(coords - location.coords)
                if distance <= NexusBlackmarketConfig.worldUi.drawDistance then
                    sleep = 0
                    DrawMarker(
                        2,
                        location.coords.x,
                        location.coords.y,
                        location.coords.z + 1.05,
                        0.0, 0.0, 0.0,
                        0.0, 0.0, 0.0,
                        NexusBlackmarketConfig.worldUi.markerScale.x,
                        NexusBlackmarketConfig.worldUi.markerScale.y,
                        NexusBlackmarketConfig.worldUi.markerScale.z,
                        NexusBlackmarketConfig.worldUi.color.r,
                        NexusBlackmarketConfig.worldUi.color.g,
                        NexusBlackmarketConfig.worldUi.color.b,
                        NexusBlackmarketConfig.worldUi.color.a,
                        false, true, 2, false, nil, nil, false
                    )

                    if distance <= NexusBlackmarketConfig.worldUi.interactDistance then
                        nearest = location
                        if IsControlJustPressed(0, 38) then
                            openMarket(locationId)
                        end
                    end
                end
            end
        end

        if nearest then
            setTextUi(true, ('[E] Hablar con %s'):format(nearest.label))
        else
            setTextUi(false)
        end

        Wait(sleep)
    end
end)

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Wait(1000)
    spawnContacts()
    print('[nexus_blackmarket] mercado negro cliente cargado')
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    setTextUi(false)
    cleanupContacts()
end)
