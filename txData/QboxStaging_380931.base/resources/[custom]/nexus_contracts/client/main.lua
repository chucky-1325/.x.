local spawnedPeds = {}
local active = nil
local activeConfig = nil
local textUiVisible = false
local lastOpenAttempt = 0
local actionBusy = false
local activeRouteBlip = nil

local function notify(description, notifyType)
    if GetResourceState('nexus_ui') == 'started' then
        exports.nexus_ui:notify({
            title = 'Suministros',
            description = description,
            type = notifyType or 'inform',
        })
        return
    end
    lib.notify({ title = 'Suministros', description = description, type = notifyType or 'inform' })
end

local function requestModel(model)
    local hash = joaat(model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(0) end
    return HasModelLoaded(hash) and hash or nil
end

local function setTextUi(visible, text)
    if visible and not textUiVisible then
        lib.showTextUI(text or '[E] Interactuar', { position = 'left-center', icon = 'truck-ramp-box' })
        textUiVisible = true
    elseif not visible and textUiVisible then
        lib.hideTextUI()
        textUiVisible = false
    end
end

local function clearActiveRoute()
    if activeRouteBlip and DoesBlipExist(activeRouteBlip) then
        SetBlipRoute(activeRouteBlip, false)
        RemoveBlip(activeRouteBlip)
    end
    activeRouteBlip = nil
end

local function setActiveRoute(target, stage)
    clearActiveRoute()
    SetNewWaypoint(target.x, target.y)

    activeRouteBlip = AddBlipForCoord(target.x, target.y, target.z)
    SetBlipSprite(activeRouteBlip, stage == 'pickup' and 478 or 446)
    SetBlipColour(activeRouteBlip, stage == 'pickup' and 3 or 5)
    SetBlipScale(activeRouteBlip, 0.85)
    SetBlipAsShortRange(activeRouteBlip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(stage == 'pickup' and 'Recoger suministros' or 'Entregar al taller')
    EndTextCommandSetBlipName(activeRouteBlip)
    SetBlipRoute(activeRouteBlip, true)
    SetBlipRouteColour(activeRouteBlip, stage == 'pickup' and 3 or 5)
end

local function setActive(payload, contract)
    active = payload
    activeConfig = contract
    if not active or not activeConfig then return end
    local target = active.stage == 'pickup' and activeConfig.pickup or activeConfig.dropoff
    setActiveRoute(target, active.stage)
end

local function openContracts()
    local now = GetGameTimer()
    if now - lastOpenAttempt < 1500 then return end
    lastOpenAttempt = now

    local ok, contracts, activeContract = lib.callback.await('nexus_contracts:server:getContracts', false)
    if not ok then
        notify(contracts == 'schema_not_ready'
            and 'La migracion de staging 002 no esta aplicada.'
            or 'No se pudo consultar el proveedor.', 'error')
        return
    end

    if activeContract then setActive(activeContract, NexusContractsConfig.contracts.civil_mechanic_supply) end
    local options = {}
    if activeContract and activeContract.stage == 'pickup' then
        options[#options + 1] = {
            title = 'Cancelar reserva',
            description = 'Libera la plaza antes de recoger el lote.',
            icon = 'ban',
            onSelect = function() TriggerServerEvent('nexus_contracts:server:cancel') end,
        }
    elseif activeContract then
        options[#options + 1] = {
            title = 'Lote en transito',
            description = 'El lote recogido debe entregarse antes de su vencimiento.',
            icon = 'truck-fast',
            disabled = true,
        }
    end

    for i = 1, #(contracts or {}) do
        local contract = contracts[i]
        local disabled = activeContract ~= nil or not contract.unlocked
        options[#options + 1] = {
            title = contract.label,
            description = ('3x metalscrap | 2x iron | 2x plastic | Stock %s/%s | Plazas %s/%s'):format(
                contract.stock or 0,
                contract.maxStock or 5,
                contract.capacity or 0,
                contract.maxStock or 5
            ),
            icon = disabled and 'warehouse' or 'truck-ramp-box',
            disabled = disabled,
            onSelect = function()
                TriggerServerEvent('nexus_contracts:server:start', contract.id)
            end,
        }
    end

    lib.registerContext({
        id = 'nexus_contracts_menu',
        title = 'Proveedor civil',
        options = options,
    })
    lib.showContext('nexus_contracts_menu')
end

local function spawnContacts()
    for contactId, contact in pairs(NexusContractsConfig.contacts) do
        local hash = requestModel(contact.model)
        if hash then
            local ped = CreatePed(4, hash, contact.coords.x, contact.coords.y, contact.coords.z - 1.0,
                contact.heading or 0.0, false, false)
            SetEntityInvincible(ped, true)
            SetBlockingOfNonTemporaryEvents(ped, true)
            FreezeEntityPosition(ped, true)
            if contact.scenario then TaskStartScenarioInPlace(ped, contact.scenario, 0, true) end
            spawnedPeds[contactId] = ped
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

local function drawMarkerAt(coords, color)
    DrawMarker(2, coords.x, coords.y, coords.z + 0.8, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        0.55, 0.55, 0.55, color.r, color.g, color.b, color.a, false, true, 2, false, nil, nil, false)
end

local function performContractAction(stage)
    if actionBusy then return end
    actionBusy = true
    local ok, payload = lib.callback.await('nexus_contracts:server:prepareAction', false, stage)
    if not ok or type(payload) ~= 'table' then
        actionBusy = false
        notify(payload == 'physical_busy' and 'Ya estas realizando otra accion fisica.'
            or 'No se pudo preparar la accion.', 'error')
        return
    end

    local completed
    if GetResourceState('nexus_scene_core') == 'started'
        and (NexusContractsConfig.sceneCore or {}).enabled ~= false then
        completed = exports.nexus_scene_core:play(payload.sceneId, {
            duration = payload.duration,
            label = payload.label,
            targetCoords = payload.coords,
            canCancel = true,
        })
    else
        completed = lib.progressBar({
            duration = payload.duration,
            label = payload.label,
            useWhileDead = false,
            canCancel = true,
            disable = { move = true, car = true, combat = true },
            anim = { dict = 'mp_common', clip = 'givetake1_a' },
        })
    end

    actionBusy = false
    if not completed then
        TriggerServerEvent('nexus_contracts:server:cancelPreparedAction', payload.token)
        return
    end
    TriggerServerEvent(stage == 'pickup'
        and 'nexus_contracts:server:pickup'
        or 'nexus_contracts:server:deliver', payload.token)
end

exports('openContracts', openContracts)
RegisterCommand(NexusContractsConfig.command, openContracts, false)

local openQuarantinePanel

local function requestQuarantineList()
    local list, err = lib.callback.await('nexus_contracts:server:listCraftQuarantines', false)
    if err then
        notify('No tienes acceso a esta herramienta.', 'error')
        return nil
    end
    return list or {}
end

local function confirmReservationId(expectedId)
    local input = lib.inputDialog('Confirmar recuperacion', {
        {
            type = 'input',
            label = 'Escribe el reservation_id exacto para confirmar',
            required = true,
        },
    })
    if not input or not input[1] then return false end
    return tostring(input[1]) == expectedId
end

local function runQuarantineRecovery(reservationId, route, routeLabel)
    if not confirmReservationId(reservationId) then
        notify('Confirmacion incorrecta. Cancelado.', 'error')
        return
    end

    local ok, result = lib.callback.await('nexus_contracts:server:recoverCraftQuarantine', false, reservationId, route)
    if ok then
        notify(('%s completado para %s.'):format(routeLabel, reservationId), 'success')
    else
        notify(('%s fallo: %s'):format(routeLabel, tostring(result)), 'error')
    end
    openQuarantinePanel()
end

openQuarantinePanel = function()
    local list = requestQuarantineList()
    if not list then return end

    if #list == 0 then
        notify('No hay cuarentenas de crafting pendientes.', 'inform')
        return
    end

    local options = {}
    for i = 1, #list do
        local item = list[i]
        options[#options + 1] = {
            title = item.reservationId,
            description = ('Citizenid: %s | Motivo: %s'):format(item.citizenid, item.incidentReason or '-'),
            icon = 'fa-solid fa-triangle-exclamation',
            arrow = true,
            onSelect = function()
                lib.registerContext({
                    id = 'nexus_craft_quarantine_detail',
                    title = item.reservationId,
                    menu = 'nexus_craft_quarantine_list',
                    options = {
                        {
                            title = 'Reintegrar materiales',
                            description = 'Devuelve el stock al pool disponible.',
                            icon = 'fa-solid fa-rotate-left',
                            onSelect = function()
                                runQuarantineRecovery(item.reservationId, 'reintegrar', 'Reintegrar')
                            end,
                        },
                        {
                            title = 'Cerrar / descartar',
                            description = 'Descarta el stock, libera el slot del lote.',
                            icon = 'fa-solid fa-ban',
                            onSelect = function()
                                runQuarantineRecovery(item.reservationId, 'cerrar', 'Cerrar')
                            end,
                        },
                    },
                })
                lib.showContext('nexus_craft_quarantine_detail')
            end,
        }
    end

    lib.registerContext({
        id = 'nexus_craft_quarantine_list',
        title = 'Cuarentenas de Crafting',
        options = options,
    })
    lib.showContext('nexus_craft_quarantine_list')
end

exports('openQuarantinePanel', openQuarantinePanel)
RegisterCommand(NexusContractsConfig.quarantineAdminCommand, openQuarantinePanel, false)

RegisterNetEvent('nexus_contracts:client:setActive', function(payload, contract)
    setActive(payload, contract)
end)

RegisterNetEvent('nexus_contracts:client:clearActive', function()
    active = nil
    activeConfig = nil
    clearActiveRoute()
    setTextUi(false)
end)

CreateThread(function()
    while true do
        local sleep = 800
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local prompt = nil

        for _, contact in pairs(NexusContractsConfig.contacts) do
            local distance = #(coords - contact.coords)
            if distance <= 10.0 then
                sleep = 0
                drawMarkerAt(contact.coords, { r = 45, g = 190, b = 220, a = 150 })
                if distance <= NexusContractsConfig.interactDistance then
                    prompt = '[E] Consultar suministros'
                    if IsControlJustPressed(0, 38) then openContracts() end
                end
            end
        end

        if active and activeConfig then
            local target = active.stage == 'pickup' and activeConfig.pickup or activeConfig.dropoff
            local distance = #(coords - target)
            if distance <= 35.0 then
                sleep = 0
                drawMarkerAt(target, { r = 0, g = 210, b = 255, a = 160 })
                if distance <= 4.0 then
                    prompt = active.stage == 'pickup' and '[E] Cargar lote' or '[E] Descargar lote'
                    if IsControlJustPressed(0, 38) then performContractAction(active.stage) end
                end
            end
        end

        setTextUi(prompt ~= nil, prompt)
        Wait(sleep)
    end
end)

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Wait(1000)
    spawnContacts()
    local ok, _, activeContract = lib.callback.await('nexus_contracts:server:getContracts', false)
    if ok and activeContract then setActive(activeContract, NexusContractsConfig.contracts.civil_mechanic_supply) end
    print('[nexus_contracts] suministro mecanico staging cliente cargado')
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if GetResourceState('nexus_scene_core') == 'started' then exports.nexus_scene_core:cancel() end
    clearActiveRoute()
    setTextUi(false)
    cleanupContacts()
end)
