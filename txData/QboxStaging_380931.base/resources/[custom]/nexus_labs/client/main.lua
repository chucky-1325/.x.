local textUiVisible = false
local activeProgress = false
local labProps = {}

local function notify(description, notifyType)
    if GetResourceState('nexus_ui') == 'started' then
        exports.nexus_ui:notify({
            title = 'Laboratorios',
            description = description,
            type = notifyType or 'inform',
        })
        return
    end

    lib.notify({ title = 'Laboratorios', description = description, type = notifyType or 'inform' })
end

local function setTextUi(visible, text)
    if visible and not textUiVisible then
        lib.showTextUI(text or '[E] Laboratorio', {
            position = 'left-center',
            icon = 'flask-vial',
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

local function formatMaterials(items)
    local parts = {}
    for i = 1, #(items or {}) do
        local item = items[i]
        parts[#parts + 1] = ('%sx %s'):format(item.count or 1, item.item)
    end
    return #parts > 0 and table.concat(parts, ', ') or 'sin materiales'
end

local function openLabDetail(lab)
    local recipe = lab.recipe or {}
    local cd = cooldownText(lab.cooldownRemaining)
    local queue = cooldownText(lab.queueRemaining)
    local blocked = lab.active or not lab.unlocked or cd ~= nil or queue ~= nil
    local upgrade = lab.upgradeCost
    local options = {
        {
            title = lab.label,
            description = ('Nivel %s | Condicion %s%% | Riesgo %s%% | Output x%.1f'):format(
                lab.level or 1,
                lab.condition or 100,
                lab.risk or 0,
                tonumber(lab.outputMultiplier) or 1.0
            ),
            icon = 'flask-vial',
            disabled = true,
        },
        {
            title = blocked and 'Produccion bloqueada' or 'Iniciar produccion',
            description = ('%s | %s%s%s'):format(
                recipe.label or lab.type,
                lab.zoneLabel or lab.zoneId,
                cd and (' | CD ' .. cd) or '',
                queue and (' | Cola ' .. queue) or ''
            ),
            icon = blocked and 'lock' or 'play',
            disabled = blocked,
            onSelect = function()
                TriggerServerEvent('nexus_labs:server:produce', lab.id)
            end,
        },
    }

    if upgrade then
        options[#options + 1] = {
            title = ('Mejorar a nivel %s'):format(upgrade.nextLevel),
            description = ('$%s | %s'):format(upgrade.cash or 0, formatMaterials(upgrade.materials)),
            icon = 'angles-up',
            disabled = lab.active or queue ~= nil,
            onSelect = function()
                TriggerServerEvent('nexus_labs:server:upgrade', lab.id)
            end,
        }
    else
        options[#options + 1] = {
            title = 'Mejora maxima',
            description = 'Este laboratorio ya esta al nivel maximo.',
            icon = 'circle-check',
            disabled = true,
        }
    end

    if lab.repairCost then
        options[#options + 1] = {
            title = ('Reparar +%s%% condicion'):format(lab.repairCost.repairAmount or 35),
            description = ('$%s | %s'):format(lab.repairCost.cash or 0, formatMaterials(lab.repairCost.materials)),
            icon = 'screwdriver-wrench',
            disabled = lab.active or queue ~= nil or (tonumber(lab.condition) or 100) >= 100,
            onSelect = function()
                TriggerServerEvent('nexus_labs:server:repair', lab.id)
            end,
        }
    end

    if lab.sabotage then
        options[#options + 1] = {
            title = lab.sabotage.canSabotage and ('Sabotear %s'):format(lab.sabotage.targetGang or 'rival') or 'Sabotaje no disponible',
            description = lab.sabotage.canSabotage
                and ('Daño %s%% | Riesgo %s%% | %s'):format(lab.sabotage.damage or 35, lab.sabotage.risk or 35, formatMaterials(lab.sabotage.materials))
                or 'Solo contra laboratorio en territorio controlado por una banda rival.',
            icon = 'burst',
            disabled = not lab.sabotage.canSabotage or lab.active or queue ~= nil,
            onSelect = function()
                TriggerServerEvent('nexus_labs:server:sabotage', lab.id)
            end,
        }
    end

    options[#options + 1] = {
        title = 'Requisitos',
        description = ('Rango %s | Rep criminal %s | Influencia +%s'):format(
            lab.requiredRank or 0,
            lab.minCriminalReputation or 0,
            lab.influenceReward or 0
        ),
        icon = 'clipboard-list',
        disabled = true,
    }

    lib.registerContext({
        id = 'nexus_labs_detail_menu',
        title = lab.label,
        menu = 'nexus_labs_menu',
        options = options,
    })
    lib.showContext('nexus_labs_detail_menu')
end

local function drawMarkerAt(coords)
    DrawMarker(
        2,
        coords.x, coords.y, coords.z + 0.7,
        0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
        0.58, 0.58, 0.58,
        180, 40, 88, 155,
        false, true, 2, false, nil, nil, false
    )
end

local function spawnProps()
    for labId, lab in pairs(NexusLabsConfig.labs or {}) do
        local model = lab.model
        if model and lab.coords then
            local hash = joaat(model)
            if IsModelInCdimage(hash) then
                RequestModel(hash)
                local timeout = GetGameTimer() + 2500
                while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(25) end
                if HasModelLoaded(hash) then
                    local coords = lab.coords
                    local prop = CreateObject(hash, coords.x, coords.y, coords.z - 1.0, false, false, false)
                    SetEntityHeading(prop, coords.w or 0.0)
                    FreezeEntityPosition(prop, true)
                    SetEntityInvincible(prop, true)
                    labProps[labId] = prop
                    SetModelAsNoLongerNeeded(hash)
                end
            end
        end
    end
end

local function cleanupProps()
    for _, prop in pairs(labProps) do
        if DoesEntityExist(prop) then DeleteEntity(prop) end
    end
    labProps = {}
end

local function openLabs()
    local ok, labs = lib.callback.await('nexus_labs:server:getLabs', false)
    if not ok then
        notify(labs == 'rate_limited' and 'Espera un momento.' or 'No se pudieron cargar laboratorios.', 'error')
        return
    end

    local options = {}
    for i = 1, #(labs or {}) do
        local lab = labs[i]
        local recipe = lab.recipe or {}
        local cd = cooldownText(lab.cooldownRemaining)
        local queue = cooldownText(lab.queueRemaining)
        local disabled = false
        local status = lab.active and ' | ACTIVO' or (queue and (' | Cola %s'):format(queue) or (cd and (' | CD %s'):format(cd) or ''))

        options[#options + 1] = {
            title = lab.label,
            description = ('N%s | %s%% | %s | Riesgo %s%% | Inf +%s%s'):format(
                lab.level or 1,
                lab.condition or 100,
                recipe.label or lab.type,
                lab.risk or 0,
                lab.influenceReward or 0,
                status
            ),
            icon = (not lab.unlocked or cd or queue or lab.active) and 'lock' or 'flask-vial',
            disabled = disabled,
            onSelect = function()
                openLabDetail(lab)
            end,
        }
    end

    lib.registerContext({
        id = 'nexus_labs_menu',
        title = 'Laboratorios ilegales',
        options = options,
    })
    lib.showContext('nexus_labs_menu')
end

exports('openLabs', openLabs)
RegisterCommand(NexusLabsConfig.command, openLabs, false)

local function runLabScene(payload)
    if activeProgress then
        print('[nexus_labs] ignored duplicate physical scene while another action is active')
        return false
    end

    payload = type(payload) == 'table' and payload or {}
    activeProgress = true
    local duration = tonumber(payload.duration) or 12000
    local label = payload.label or 'Procesando lote...'
    local completed

    if GetResourceState('nexus_scene_core') == 'started' and (NexusLabsConfig.sceneCore or {}).enabled ~= false then
        completed = exports.nexus_scene_core:play(payload.sceneId or 'lab_processing', {
            duration = duration,
            label = label,
            targetCoords = payload.coords,
            canCancel = false,
        })
    else
        completed = lib.progressBar({
            duration = duration,
            label = label,
            useWhileDead = false,
            canCancel = false,
            disable = { move = true, car = true, combat = true },
            anim = { dict = 'amb@prop_human_bum_bin@base', clip = 'base' },
        })
    end

    activeProgress = false
    return completed == true
end

RegisterNetEvent('nexus_labs:client:startScene', function(payload)
    runLabScene(payload)
end)

RegisterNetEvent('nexus_labs:client:startProgress', function(labId, duration, label)
    local lab = NexusLabsConfig.labs and NexusLabsConfig.labs[tostring(labId or '')]
    runLabScene({
        labId = labId,
        action = 'production',
        sceneId = 'lab_processing',
        duration = duration,
        label = label,
        coords = lab and lab.coords or nil,
    })
end)

RegisterNetEvent('nexus_labs:client:policeAlert', function(data)
    if type(data) ~= 'table' or not data.coords then return end
    SetNewWaypoint(data.coords.x, data.coords.y)
    notify(('Actividad de laboratorio detectada: %s'):format(data.label or 'laboratorio'), 'warning')
end)

CreateThread(function()
    while true do
        local sleep = 900
        local prompt = nil
        local pedCoords = GetEntityCoords(PlayerPedId())

        for labId, lab in pairs(NexusLabsConfig.labs or {}) do
            local coords = lab.coords
            if coords then
                local distance = #(pedCoords - vector3(coords.x, coords.y, coords.z))
                if distance <= 35.0 then
                    sleep = 0
                    drawMarkerAt(coords)
                    if distance <= (NexusLabsConfig.interactDistance or 3.0) then
                        prompt = '[E] Laboratorio ilegal'
                        if IsControlJustPressed(0, 38) then
                            TriggerServerEvent('nexus_labs:server:produce', labId)
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
    spawnProps()
    print('[nexus_labs] laboratorios cliente cargados')
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if GetResourceState('nexus_scene_core') == 'started' then
        exports.nexus_scene_core:cancel()
    end
    setTextUi(false)
    cleanupProps()
end)
