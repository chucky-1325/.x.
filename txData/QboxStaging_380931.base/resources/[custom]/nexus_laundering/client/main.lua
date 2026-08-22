local textUiVisible = false
local contactPeds = {}

local function notify(description, notifyType)
    if GetResourceState('nexus_ui') == 'started' then
        exports.nexus_ui:notify({
            title = 'Lavado',
            description = description,
            type = notifyType or 'inform',
        })
        return
    end

    lib.notify({ title = 'Lavado', description = description, type = notifyType or 'inform' })
end

local function setTextUi(visible, text)
    if visible and not textUiVisible then
        lib.showTextUI(text or '[E] Lavar dinero', {
            position = 'left-center',
            icon = 'money-bill-transfer',
        })
        textUiVisible = true
    elseif not visible and textUiVisible then
        lib.hideTextUI()
        textUiVisible = false
    end
end

local function cooldownText(seconds)
    local value = tonumber(seconds) or 0
    if value <= 0 then return nil end
    return value < 60 and ('%ss'):format(value) or ('%sm'):format(math.ceil(value / 60))
end

local function drawMarkerAt(coords)
    DrawMarker(
        2,
        coords.x, coords.y, coords.z + 0.75,
        0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
        0.58, 0.58, 0.58,
        34, 197, 94, 155,
        false, true, 2, false, nil, nil, false
    )
end

local function spawnContacts()
    for locationId, location in pairs(NexusLaunderingConfig.locations or {}) do
        local hash = joaat(location.model or 'a_m_m_business_01')
        if IsModelInCdimage(hash) then
            RequestModel(hash)
            local timeout = GetGameTimer() + 2500
            while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(25) end
            if HasModelLoaded(hash) then
                local coords = location.coords
                local ped = CreatePed(4, hash, coords.x, coords.y, coords.z - 1.0, coords.w or 0.0, false, false)
                SetEntityInvincible(ped, true)
                FreezeEntityPosition(ped, true)
                SetBlockingOfNonTemporaryEvents(ped, true)
                if location.scenario then TaskStartScenarioInPlace(ped, location.scenario, 0, true) end
                contactPeds[locationId] = ped
                SetModelAsNoLongerNeeded(hash)
            end
        end
    end
end

local function cleanupContacts()
    for _, ped in pairs(contactPeds) do
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end
    contactPeds = {}
end

local function requestLaunder(location)
    local input = lib.inputDialog(location.label, {
        {
            type = 'number',
            label = 'Cantidad de dinero sucio',
            description = ('Comision %s%% | Riesgo %s%%'):format(location.commissionPercent or 25, location.risk or 0),
            min = NexusLaunderingConfig.limits.minAmount or 250,
            max = NexusLaunderingConfig.limits.maxAmount or 15000,
            required = true,
        },
    })

    if not input or not input[1] then return end
    TriggerServerEvent('nexus_laundering:server:launder', location.id, input[1])
end

local function openLaundering()
    local ok, locations = lib.callback.await('nexus_laundering:server:getLocations', false)
    if not ok then
        notify(locations == 'rate_limited' and 'Espera un momento.' or 'No se pudieron cargar puntos de lavado.', 'error')
        return
    end

    local options = {}
    for i = 1, #(locations or {}) do
        local location = locations[i]
        local cd = cooldownText(location.cooldownRemaining)
        local disabled = not location.unlocked or cd ~= nil
        options[#options + 1] = {
            title = location.label,
            description = ('Comision %s%% | Riesgo %s%% | Rep %s%s'):format(
                location.commissionPercent or 25,
                location.risk or 0,
                location.minCriminalReputation or 0,
                cd and (' | CD %s'):format(cd) or ''
            ),
            icon = disabled and 'lock' or 'money-bill-transfer',
            disabled = disabled,
            onSelect = function()
                requestLaunder(location)
            end,
        }
    end

    lib.registerContext({
        id = 'nexus_laundering_menu',
        title = 'Lavado de dinero',
        options = options,
    })
    lib.showContext('nexus_laundering_menu')
end

exports('openLaundering', openLaundering)
RegisterCommand(NexusLaunderingConfig.command, openLaundering, false)

RegisterNetEvent('nexus_laundering:client:policeAlert', function(data)
    if type(data) ~= 'table' or not data.coords then return end
    SetNewWaypoint(data.coords.x, data.coords.y)
    notify(('Operacion de lavado detectada: %s'):format(data.label or 'lavado'), 'warning')
end)

CreateThread(function()
    while true do
        local sleep = 900
        local prompt = nil
        local closest = nil
        local pedCoords = GetEntityCoords(PlayerPedId())

        for locationId, location in pairs(NexusLaunderingConfig.locations or {}) do
            local coords = location.coords
            local distance = #(pedCoords - vector3(coords.x, coords.y, coords.z))
            if distance <= 35.0 then
                sleep = 0
                drawMarkerAt(coords)
                if distance <= (NexusLaunderingConfig.interactDistance or 3.0) then
                    prompt = '[E] Lavar dinero'
                    closest = locationId
                end
            end
        end

        if prompt then
            setTextUi(true, prompt)
            if IsControlJustPressed(0, 38) and closest then
                openLaundering()
            end
        else
            setTextUi(false)
        end

        Wait(sleep)
    end
end)

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Wait(500)
    spawnContacts()
    print('[nexus_laundering] lavado cliente cargado')
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    setTextUi(false)
    cleanupContacts()
end)
