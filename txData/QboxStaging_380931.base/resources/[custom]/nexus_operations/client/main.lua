local active = nil
local activeConfig = nil
local textUiVisible = false
local lastOpenAttempt = 0
local actionBusy = false
local contactPed = nil

local function notify(description, notifyType)
    if GetResourceState('nexus_ui') == 'started' then
        exports.nexus_ui:notify({
            title = 'Operaciones',
            description = description,
            type = notifyType or 'inform',
        })
        return
    end

    lib.notify({ title = 'Operaciones', description = description, type = notifyType or 'inform' })
end

local function setTextUi(visible, text)
    if visible and not textUiVisible then
        lib.showTextUI(text or '[E] Operacion', {
            position = 'left-center',
            icon = 'people-carry-box',
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

local function drawMarkerAt(coords, color)
    DrawMarker(
        2,
        coords.x, coords.y, coords.z + 0.8,
        0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
        0.62, 0.62, 0.62,
        color.r, color.g, color.b, color.a,
        false, true, 2, false, nil, nil, false
    )
end

local function markRoute(coords)
    if coords then SetNewWaypoint(coords.x, coords.y) end
end

local function cleanupContact()
    if contactPed and DoesEntityExist(contactPed) then
        DeleteEntity(contactPed)
    end

    contactPed = nil
end

local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model or 'a_m_m_business_01')
    if not IsModelInCdimage(hash) then return nil end

    RequestModel(hash)
    local timeout = GetGameTimer() + 3500
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do
        Wait(25)
    end

    return HasModelLoaded(hash) and hash or nil
end

local function spawnContact(operation, coords)
    cleanupContact()
    if not operation or not coords then return end

    local npc = operation.route and operation.route.npc or operation.npc
    local defaults = NexusOperationsConfig.npcDefaults or {}
    local fallback = defaults[operation.type] or {}
    local model = loadModel((npc and npc.model) or fallback.model)
    if not model then return end

    local heading = coords.w or coords.heading or 0.0
    contactPed = CreatePed(4, model, coords.x, coords.y, coords.z - 1.0, heading, false, false)
    SetEntityInvincible(contactPed, true)
    SetBlockingOfNonTemporaryEvents(contactPed, true)
    FreezeEntityPosition(contactPed, true)

    local scenario = (npc and npc.scenario) or fallback.scenario
    if scenario then TaskStartScenarioInPlace(contactPed, scenario, 0, true) end
    SetModelAsNoLongerNeeded(model)
end

local function routeForStage(stage, operation)
    if not operation then return nil end
    local route = operation.route or {}
    if stage == 'pickup' then return route.pickup or operation.pickup end
    if stage == 'dropoff' then return route.dropoff or operation.dropoff end
    if stage == 'extort' then return route.point or operation.point end
    return nil
end

local function coords3(coords)
    if not coords then return nil end
    return vector3(coords.x, coords.y, coords.z)
end

local function performAction(stage)
    if actionBusy then return end
    actionBusy = true

    local ok, payload = lib.callback.await('nexus_operations:server:prepareAction', false, stage)
    if not ok or type(payload) ~= 'table' then
        actionBusy = false
        notify(payload == 'physical_busy' and 'Ya estas realizando otra accion fisica.' or 'No se pudo preparar la operacion.', 'error')
        return
    end

    local completed
    if GetResourceState('nexus_scene_core') == 'started' and (NexusOperationsConfig.sceneCore or {}).enabled ~= false then
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
        TriggerServerEvent('nexus_operations:server:cancelPreparedAction', payload.token)
        return
    end

    if stage == 'pickup' then
        TriggerServerEvent('nexus_operations:server:pickup', payload.token)
    elseif stage == 'dropoff' then
        TriggerServerEvent('nexus_operations:server:deliver', payload.token)
    elseif stage == 'extort' then
        TriggerServerEvent('nexus_operations:server:extort', payload.token)
    end
end

local function openOperations()
    local now = GetGameTimer()
    if now - lastOpenAttempt < 1200 then return end
    lastOpenAttempt = now

    local ok, operations, activeOperation = lib.callback.await('nexus_operations:server:getOperations', false)
    if not ok then
        notify(operations == 'rate_limited' and 'Espera un momento.' or 'No se pudieron cargar operaciones.', 'error')
        return
    end

    local options = {}
    if activeOperation then
        options[#options + 1] = {
            title = 'Cancelar operacion activa',
            description = ('%s | Estado %s'):format(activeOperation.id, activeOperation.stage),
            icon = 'ban',
            onSelect = function()
                TriggerServerEvent('nexus_operations:server:cancel')
            end,
        }
    end

    for i = 1, #(operations or {}) do
        local operation = operations[i]
        local rewards = operation.rewards and operation.rewards.player or {}
        local cd = cooldownText(operation.cooldownRemaining)
        local disabled = activeOperation ~= nil or not operation.unlocked or cd ~= nil
        local status = cd and (' | CD %s'):format(cd) or ''

        options[#options + 1] = {
            title = operation.label,
            description = ('%s | $%s | XP %s | Inf %s | Riesgo %s%%%s%s'):format(
                operation.type,
                rewards.cash or 0,
                rewards.xp or 0,
                operation.influence or 0,
                operation.policeAlertChance or 0,
                status,
                (operation.routeCount and operation.routeCount > 0) and (' | Rutas %s'):format(operation.routeCount) or ''
            ),
            icon = disabled and 'lock' or (operation.type == 'supply' and 'truck-ramp-box' or 'hand-fist'),
            disabled = disabled,
            onSelect = function()
                TriggerServerEvent('nexus_operations:server:start', operation.id)
            end,
        }
    end

    lib.registerContext({
        id = 'nexus_operations_menu',
        title = 'Operaciones de banda',
        options = options,
    })
    lib.showContext('nexus_operations_menu')
end

exports('openOperations', openOperations)

RegisterCommand(NexusOperationsConfig.command, openOperations, false)

RegisterNetEvent('nexus_operations:client:setActive', function(payload, operation)
    active = payload
    activeConfig = operation
    local target = routeForStage(active.stage, activeConfig)
    markRoute(target)
    spawnContact(activeConfig, target)
end)

RegisterNetEvent('nexus_operations:client:clearActive', function()
    active = nil
    activeConfig = nil
    setTextUi(false)
    cleanupContact()
end)

RegisterNetEvent('nexus_operations:client:policeAlert', function(data)
    if type(data) ~= 'table' or not data.coords then return end
    SetNewWaypoint(data.coords.x, data.coords.y)
    notify(('Actividad de banda reportada: %s'):format(data.label or 'operacion'), 'warning')
end)

CreateThread(function()
    while true do
        local sleep = 800
        local prompt = nil

        if active and activeConfig then
            local target = routeForStage(active.stage, activeConfig)
            if target then
                local coords = GetEntityCoords(PlayerPedId())
                local distance = #(coords - coords3(target))
                if distance <= 35.0 then
                    sleep = 0
                    drawMarkerAt(target, active.stage == 'extort'
                        and { r = 255, g = 64, b = 80, a = 160 }
                        or { r = 34, g = 211, b = 238, a = 160 })

                    if distance <= (NexusOperationsConfig.interactDistance or 4.0) then
                        prompt = active.stage == 'pickup' and '[E] Recoger suministros'
                            or (active.stage == 'dropoff' and '[E] Entregar suministros' or '[E] Cobrar proteccion')

                        if IsControlJustPressed(0, 38) then
                            performAction(active.stage)
                        end
                    end
                end
            end
        end

        if prompt then setTextUi(true, prompt) else setTextUi(false) end
        Wait(sleep)
    end
end)

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Wait(500)
    print('[nexus_operations] operaciones cliente cargadas')
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if GetResourceState('nexus_scene_core') == 'started' then
        exports.nexus_scene_core:cancel()
    end
    setTextUi(false)
    cleanupContact()
end)
