local zones = {}
local cachedStations = {}
local spawnedProps = {}
local activeStation = nil
local activeStationData = nil
local isOpen = false
local isOpening = false
local textUiVisible = false
local nuiOpenAck = false
local lastOpenAttempt = 0
local lastOpenStation = nil
local setTextUi

local function notify(description, notifyType)
    if GetResourceState('nexus_ui') == 'started' then
        exports.nexus_ui:notify({
            title = 'Crafting',
            description = description,
            type = notifyType or 'inform',
        })
        return
    end

    lib.notify({ title = 'Crafting', description = description, type = notifyType or 'inform' })
end

local function toVector(coords)
    return vector3(tonumber(coords.x), tonumber(coords.y), tonumber(coords.z))
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

local function nui(action, data)
    SendNUIMessage({
        action = action,
        data = data or {},
    })
end

local function closeUi()
    isOpen = false
    isOpening = false
    nuiOpenAck = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    setTextUi(false)
    nui('close')
end

setTextUi = function(visible, text)
    if visible and not textUiVisible then
        lib.showTextUI(text or '[E] Usar banco de crafting', {
            position = 'left-center',
            icon = 'hammer',
        })
        textUiVisible = true
    elseif not visible and textUiVisible then
        lib.hideTextUI()
        textUiVisible = false
    end
end

local function getErrorMessage(reason, detail)
    if reason == 'missing_items' then return 'Te faltan materiales.' end
    if reason == 'no_space' then return 'No tienes espacio suficiente.' end
    if reason == 'too_far' then return 'Estas demasiado lejos de la mesa.' end
    if reason == 'level_locked' then
        local level = detail and detail.requiredLevel or '?'
        return ('Requiere nivel crafting %s.'):format(level)
    end
    if reason == 'classified_recipe' then return 'Receta clasificada.' end
    if reason == 'reputation_locked' then
        local reputation = detail and detail.requiredReputation or '?'
        return ('Requiere reputacion crafting %s.'):format(reputation)
    end
    if reason == 'missing_blueprint' then
        local item = detail and detail.item or 'plano'
        return ('Requiere plano: %s'):format(item)
    end
    if reason == 'station_disabled' then return 'Esta mesa esta desactivada.' end
    if reason == 'no_access' then return 'No tienes acceso a esta mesa.' end
    if reason == 'not_on_duty' then return 'Debes estar de servicio como mecanico.' end
    if reason == 'stock_unavailable' then return 'No hay lotes disponibles en el taller.' end
    if reason == 'active_reservation' then return 'Ya tienes una fabricacion reservada.' end
    if reason == 'schema_not_ready' then return 'El stock del taller no esta disponible.' end
    if reason == 'contracts_unavailable' then return 'El sistema de suministros no esta disponible.' end
    if reason == 'incident_pending' then return 'Incidencia pendiente. La reserva queda bloqueada para revision.' end
    if reason == 'quarantine_active' then return 'Hay una incidencia pendiente en este banco. Los materiales estan retenidos para revision administrativa.' end
    if reason == 'inventory_add_failed' then return 'No se pudo entregar el kit al inventario.' end
    if reason == 'expired' or reason == 'expired_session' then return 'La reserva de stock ha caducado.' end
    if reason == 'station_or_recipe_missing_at_finish' then return 'La mesa o la receta ya no estan disponibles.' end
    if reason == 'unsupported_flow' then return 'Esta sesion de fabricacion no es valida.' end
    if reason == 'station_busy' then return 'Esta mesa ya tiene un trabajo en curso.' end
    if reason == 'station_misconfigured' then return 'Esta mesa no esta configurada correctamente.' end
    if reason == 'invalid_job' then return 'Ese trabajo ya no existe o ya se resolvio.' end
    if reason == 'not_ready' then return 'El trabajo todavia no esta listo.' end
    if reason == 'already_claimed' then return 'Alguien mas esta gestionando ese trabajo ahora mismo.' end
    if reason == 'not_owner' then return 'Solo quien inicio el trabajo puede cancelarlo.' end
    if reason == 'already_ready' then return 'Ya no se puede cancelar: el trabajo esta listo.' end
    if reason == 'invalid_session' then return 'No se pudo identificar tu personaje.' end
    return 'No puedes fabricar esta receta.'
end

local function refreshStation()
    if not activeStation then return end

    local ok, station = lib.callback.await('nexus_crafting:server:getStation', false, activeStation)
    if not ok then
        notify(getErrorMessage(station), 'error')
        closeUi()
        return
    end

    activeStationData = station
    nui('open', station)
end

local function runCraftingScene(result, recipe)
    local duration = result.duration or recipe.duration or 5000
    local label = ('Fabricando %s'):format(result.label or recipe.label)
    local sceneConfig = NexusCraftingConfig.sceneCore or {}

    if sceneConfig.enabled ~= false and GetResourceState('nexus_scene_core') == 'started' then
        local category = recipe.category or (activeStationData and activeStationData.category) or 'civil'
        local sceneId = recipe.scene or (sceneConfig.categories and sceneConfig.categories[category]) or sceneConfig.fallback or 'craft_civil'
        return exports.nexus_scene_core:play(sceneId, {
            duration = duration,
            label = label,
            targetCoords = activeStationData and activeStationData.coords or nil,
            canCancel = true,
        })
    end

    local completed = lib.progressBar({
        duration = duration,
        label = label,
        useWhileDead = false,
        canCancel = true,
        disable = {
            move = true,
            car = true,
            combat = true,
        },
        anim = {
            dict = 'mini@repair',
            clip = 'fixing_a_ped',
        },
    })

    return completed == true, completed and 'completed' or 'cancelled'
end

local function craftRecipe(stationId, recipeId, recipe)
    local ok, result, detail = lib.callback.await('nexus_crafting:server:canCraft', false, stationId, recipeId)
    if not ok then
        notify(getErrorMessage(result, detail), 'error')
        refreshStation()
        return
    end

    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    nui('craftProgress', {
        state = 'start',
        label = result.label or recipe.label,
        duration = result.duration or recipe.duration or 5000,
    })

    local completed = runCraftingScene(result, recipe)

    if completed then
        local crafted, finishResult = lib.callback.await(
            'nexus_crafting:server:finishCraft',
            false,
            stationId,
            recipeId,
            result.sessionToken
        )
        if crafted then
            nui('craftProgress', {
                state = 'complete',
                message = ('%s fabricado.'):format(result.label or recipe.label),
            })
        else
            nui('craftProgress', {
                state = 'cancelled',
                cancelled = true,
                message = getErrorMessage(finishResult),
            })
            notify(getErrorMessage(finishResult), 'error')
        end
        Wait(500)
        refreshStation()
        SetNuiFocus(true, true)
    else
        local cancelled, cancelReason = lib.callback.await(
            'nexus_crafting:server:cancelCraft',
            false,
            result.sessionToken
        )
        nui('craftProgress', {
            state = 'cancelled',
            cancelled = true,
            message = cancelled and 'Fabricacion cancelada.' or getErrorMessage(cancelReason),
        })
        SetNuiFocus(true, true)
        notify(cancelled and 'Fabricacion cancelada.' or getErrorMessage(cancelReason), cancelled and 'inform' or 'error')
    end
end

local function describeIngredients(recipe)
    local parts = {}
    for i = 1, #(recipe.ingredients or {}) do
        local ingredient = recipe.ingredients[i]
        parts[#parts + 1] = ('%sx %s'):format(ingredient.count, ingredient.item)
    end
    return table.concat(parts, ', ')
end

local function openStationFallback(stationId, station)
    local options = {}

    for i = 1, #(station.recipes or {}) do
        local entry = station.recipes[i]
        local recipe = entry.data
        local locked = not entry.unlocked
        local missing = #(entry.missing or {}) > 0

        options[#options + 1] = {
            title = recipe.label,
            description = ('Resultado: %sx %s | Materiales: %s'):format(
                recipe.output.count or 1,
                recipe.output.item,
                describeIngredients(recipe)
            ),
            icon = 'hammer',
            disabled = locked or missing,
            metadata = {
                { label = 'Nivel requerido', value = recipe.requiredLevel or 1 },
                { label = 'XP crafting', value = recipe.xp or 0 },
                { label = 'Estado', value = locked and (entry.lockedReason or 'Bloqueada') or (missing and 'Faltan materiales' or 'Disponible') },
            },
            onSelect = function()
                craftRecipe(stationId, entry.id, recipe)
            end,
        }
    end

    lib.registerContext({
        id = 'nexus_crafting_fallback',
        title = station.label or 'Mesa de crafting',
        options = options,
    })

    lib.showContext('nexus_crafting_fallback')
end

-- ============================================================
-- Sistema de trabajos persistentes (mesas type='gang'). UI minima via
-- ox_lib context, separada por completo de la NUI del flujo sincrono.
-- ============================================================

local function formatCountdown(seconds)
    seconds = math.max(0, math.floor(seconds))
    local minutes = math.floor(seconds / 60)
    local secs = seconds % 60
    if minutes > 0 then return ('%dm %ds'):format(minutes, secs) end
    return ('%ds'):format(secs)
end

local function openJobStation(stationId, station)
    local job = lib.callback.await('nexus_crafting:server:getStationJob', false, stationId)
    local options = {}

    if not job then
        for i = 1, #(station.recipes or {}) do
            local entry = station.recipes[i]
            local recipe = entry.data
            options[#options + 1] = {
                title = recipe.label,
                description = ('Duracion: %ss'):format(math.ceil((tonumber(recipe.duration) or 5000) / 1000)),
                icon = 'hammer',
                disabled = not entry.unlocked or #(entry.missing or {}) > 0,
                onSelect = function()
                    local ok, result = lib.callback.await('nexus_crafting:server:startJob', false, stationId, entry.id)
                    if ok then
                        notify(('Trabajo iniciado: %s'):format(result and result.label or recipe.label), 'success')
                    else
                        notify(getErrorMessage(result), 'error')
                    end
                end,
            }
        end
    else
        local now = tonumber(job.server_now)
        local ready = now >= tonumber(job.ready_at)

        if ready then
            options[#options + 1] = {
                title = 'Retirar resultado',
                description = (station.type == 'gang' and job.owner_gang) and 'Verifica si es tuyo antes de confirmar.' or nil,
                icon = 'box-open',
                onSelect = function()
                    local ok, result = lib.callback.await('nexus_crafting:server:collectJob', false, job.job_key)
                    if ok then
                        notify(result and result.isTheft and 'Has robado el trabajo.' or 'Has retirado el trabajo.', result and result.isTheft and 'inform' or 'success')
                    else
                        notify(getErrorMessage(result), 'error')
                    end
                end,
            }
        else
            options[#options + 1] = {
                title = 'Trabajo en curso',
                description = ('Listo en %s'):format(formatCountdown(tonumber(job.ready_at) - now)),
                icon = 'clock',
                disabled = true,
            }
            options[#options + 1] = {
                title = 'Cancelar trabajo',
                description = 'Solo si tu iniciaste este trabajo.',
                icon = 'ban',
                onSelect = function()
                    local ok, result = lib.callback.await('nexus_crafting:server:cancelJob', false, job.job_key)
                    if ok then
                        notify('Trabajo cancelado.', 'inform')
                    else
                        notify(getErrorMessage(result), 'error')
                    end
                end,
            }
        end
    end

    lib.registerContext({
        id = 'nexus_crafting_job_station',
        title = station.label or 'Mesa de banda',
        options = options,
    })
    lib.showContext('nexus_crafting_job_station')
end

local function openStation(stationId)
    if isOpening or isOpen then return end

    if type(stationId) ~= 'string' then
        notify('Mesa invalida.', 'error')
        return
    end

    local now = GetGameTimer()
    if lastOpenStation == stationId and now - lastOpenAttempt < 1500 then
        return
    end

    lastOpenStation = stationId
    lastOpenAttempt = now

    isOpening = true
    print(('[nexus_crafting] opening station: %s'):format(stationId))
    local ok, station = lib.callback.await('nexus_crafting:server:getStation', false, stationId)
    if not ok then
        print(('[nexus_crafting] station rejected: %s -> %s'):format(stationId, tostring(station)))
        notify(getErrorMessage(station), 'error')
        isOpening = false
        return
    end

    activeStation = stationId
    activeStationData = station

    if station.type == 'gang' then
        isOpening = false
        openJobStation(stationId, station)
        return
    end

    isOpen = true
    nuiOpenAck = false
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)

    local timeout = GetGameTimer() + 8000
    while isOpen and not nuiOpenAck and GetGameTimer() < timeout do
        nui('open', station)
        Wait(150)
    end

    if not nuiOpenAck then
        print(('[nexus_crafting] NUI open timeout for station: %s'):format(stationId))
        closeUi()
        notify('NUI no respondio. Abriendo menu seguro.', 'inform')
        openStationFallback(stationId, station)
        return
    end

    isOpening = false
end

local function cleanupZones()
    if GetResourceState('ox_target') ~= 'started' then return end

    for _, zone in pairs(zones) do
        exports.ox_target:removeZone(zone)
    end

    zones = {}
end

local function cleanupProps()
    for _, entity in pairs(spawnedProps) do
        if DoesEntityExist(entity) then DeleteEntity(entity) end
    end

    spawnedProps = {}
end

local function spawnWorkbenchProps(stations)
    cleanupProps()

    for i = 1, #(stations or {}) do
        local station = stations[i]
        local model = station.model or NexusCraftingConfig.defaultAccess.model
        local hash = requestModel(model)
        if hash then
            local coords = toVector(station.coords)
            local entity = CreateObjectNoOffset(hash, coords.x, coords.y, coords.z, false, false, false)
            SetEntityHeading(entity, station.heading or 0.0)
            FreezeEntityPosition(entity, true)
            SetEntityInvincible(entity, true)
            SetEntityAlpha(entity, station.enabled == false and 125 or 245, false)
            spawnedProps[station.id] = entity
            SetModelAsNoLongerNeeded(hash)
        end
    end
end

local function createTargetZones(stations)
    if GetResourceState('ox_target') ~= 'started' then return end

    cleanupZones()
    for i = 1, #(stations or {}) do
        local station = stations[i]
        zones[station.id] = exports.ox_target:addBoxZone({
            coords = toVector(station.coords),
            size = vector3(station.size.x, station.size.y, station.size.z),
            rotation = station.heading or 0.0,
            debug = NexusCraftingConfig.debug,
            options = {
                {
                    name = 'nexus_crafting_' .. station.id,
                    icon = 'fa-solid fa-hammer',
                    label = station.label,
                    onSelect = function()
                        openStation(station.id)
                    end,
                },
            },
        })
    end
end

local function refreshWorkbenches(stations)
    cachedStations = stations or lib.callback.await('nexus_crafting:server:getStations', false) or {}
    createTargetZones(cachedStations)
    spawnWorkbenchProps(cachedStations)
end

local function drawText3d(coords, text)
    local onScreen, x, y = World3dToScreen2d(coords.x, coords.y, coords.z)
    if not onScreen then return end

    SetTextScale(0.32, 0.32)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(248, 250, 252, 235)
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

local function getNearestStation(maxDistance)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local nearest, nearestDistance = nil, maxDistance or 2.0

    for i = 1, #cachedStations do
        local station = cachedStations[i]
        local distance = #(coords - toVector(station.coords))
        if distance <= nearestDistance then
            nearest = station
            nearestDistance = distance
        end
    end

    return nearest, nearestDistance
end

local function getClosestStation()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local closest, closestDistance = nil, 999999.0

    for i = 1, #cachedStations do
        local station = cachedStations[i]
        local distance = #(coords - toVector(station.coords))
        if distance < closestDistance then
            closest = station
            closestDistance = distance
        end
    end

    return closest, closestDistance
end

local function openNearestStation()
    if #cachedStations == 0 then
        refreshWorkbenches()
    end

    local maxDistance = NexusCraftingConfig.worldUi.interactDistance + 1.0
    local nearest = getNearestStation(maxDistance)
    if not nearest then
        local closest, closestDistance = getClosestStation()
        if closest then
            notify(('Mesa mas cercana: %s a %.1fm. Acercate mas.'):format(closest.label, closestDistance), 'error')
        else
            notify('No hay mesas de crafting cargadas en cliente. Usa /craftreload.', 'error')
        end
        return
    end

    openStation(nearest.id)
end

local function debugCrafting()
    if #cachedStations == 0 then
        refreshWorkbenches()
    end

    local closest, distance = getClosestStation()
    if closest then
        notify(('Mesas cargadas: %s | cercana: %s %.1fm'):format(#cachedStations, closest.id, distance), 'inform')
        print(('[nexus_crafting] debug count=%s closest=%s distance=%.2f'):format(#cachedStations, closest.id, distance))
    else
        notify('Mesas cargadas: 0. Revisa txAdmin/server callback.', 'error')
        print('[nexus_crafting] debug count=0')
    end
end

local function parseCsv(value)
    local result = {}
    for token in tostring(value or ''):gmatch('[^,]+') do
        local item = token:gsub('^%s+', ''):gsub('%s+$', '')
        if item ~= '' then result[#result + 1] = item end
    end
    return result
end

local function parseJobs(value)
    local jobs = {}
    for _, entry in ipairs(parseCsv(value)) do
        local name, grade = entry:match('([^:]+):?(%d*)')
        if name and name ~= '' then
            jobs[name] = tonumber(grade) or 0
        end
    end
    return jobs
end

local function getPlacementCoords(distance)
    local ped = PlayerPedId()
    local origin = GetGameplayCamCoord()
    local rotation = GetGameplayCamRot(2)
    local pitch = math.rad(rotation.x)
    local yaw = math.rad(rotation.z)
    local direction = vector3(-math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch))
    local target = origin + direction * (distance or NexusCraftingConfig.editor.placementDistance)

    return vector3(target.x, target.y, target.z), GetEntityHeading(ped)
end

local function groundSnap(coords)
    local found, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 2.0, false)
    if found then return vector3(coords.x, coords.y, groundZ) end
    return coords
end

local function runPlacement(model)
    local hash = requestModel(model)
    if not hash then
        notify('Modelo de banco invalido.', 'error')
        return nil
    end

    local coords, heading = getPlacementCoords()
    coords = groundSnap(coords)
    local preview = CreateObjectNoOffset(hash, coords.x, coords.y, coords.z, false, false, false)
    SetEntityAlpha(preview, 170, false)
    SetEntityCollision(preview, false, false)
    FreezeEntityPosition(preview, true)

    local placed = nil
    while not placed do
        DisableControlAction(0, 24, true)
        DisableControlAction(0, 25, true)

        coords = getPlacementCoords()
        coords = groundSnap(coords)

        if IsControlPressed(0, 174) then heading = heading - 1.2 end
        if IsControlPressed(0, 175) then heading = heading + 1.2 end

        SetEntityCoordsNoOffset(preview, coords.x, coords.y, coords.z, false, false, false)
        SetEntityHeading(preview, heading)
        DrawMarker(1, coords.x, coords.y, coords.z + 0.02, 0.0, 0.0, 0.0, 0.0, 0.0, heading, 1.4, 1.4, 0.04, 0, 210, 255, 150, false, false, 2, false, nil, nil, false)
        drawText3d(vector3(coords.x, coords.y, coords.z + 1.25), '~b~Crafting Editor~s~\nENTER colocar | ESC cancelar\nFlechas izquierda/derecha rotar')

        if IsControlJustPressed(0, 191) then
            placed = { coords = coords, heading = heading }
        elseif IsControlJustPressed(0, 322) then
            placed = false
        end

        Wait(0)
    end

    DeleteEntity(preview)
    SetModelAsNoLongerNeeded(hash)
    return placed
end

local function openWorkbenchForm(existing)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local station = existing or {}
    local defaults = NexusCraftingConfig.defaultAccess

    local input = lib.inputDialog(existing and 'Editar banco de trabajo' or 'Crear banco de trabajo', {
        { type = 'input', label = 'ID', required = true, default = station.id or ('bench_' .. math.floor(GetGameTimer())) },
        { type = 'input', label = 'Nombre', required = true, default = station.label or NexusCraftingConfig.editor.defaultLabel },
        { type = 'select', label = 'Acceso', required = true, default = station.type or defaults.type, options = {
            { label = 'Publico', value = 'public' },
            { label = 'Job unico', value = 'job' },
            { label = 'Varios jobs', value = 'jobs' },
            { label = 'Ilegal gang', value = 'illegal' },
            { label = 'Banda (trabajos persistentes)', value = 'gang' },
        } },
        { type = 'select', label = 'Categoria', required = true, default = station.category or defaults.category, options = {
            { label = 'Civil', value = 'civil' },
            { label = 'Mecanico', value = 'mechanic' },
            { label = 'EMS', value = 'ems' },
            { label = 'Policia', value = 'police' },
            { label = 'Mercado negro', value = 'illegal' },
        } },
        { type = 'input', label = 'Job unico', default = station.job or '' },
        { type = 'input', label = 'Jobs varios job:grado', default = station.jobsText or '' },
        { type = 'input', label = 'Recetas separadas por coma', required = true, default = station.recipesText or table.concat(station.recipes or defaults.recipes, ',') },
        { type = 'select', label = 'Modelo 3D', required = true, default = station.model or defaults.model, options = NexusCraftingConfig.editor.models },
        { type = 'number', label = 'Size X', default = station.size and station.size.x or NexusCraftingConfig.editor.defaultSize.x },
        { type = 'number', label = 'Size Y', default = station.size and station.size.y or NexusCraftingConfig.editor.defaultSize.y },
        { type = 'number', label = 'Size Z', default = station.size and station.size.z or NexusCraftingConfig.editor.defaultSize.z },
        { type = 'checkbox', label = 'Mesa activa', checked = station.enabled ~= false },
        { type = 'select', label = 'Modo', required = true, default = station.mode or '', options = {
            { label = 'Ninguno (mesa inalcanzable)', value = '' },
            { label = 'Trabajo persistente (mode=job)', value = 'job' },
        } },
        { type = 'input', label = 'Banda propietaria (owner_gang, solo modo job + acceso banda)', default = station.ownerGang or '' },
    })

    if not input then return end

    if not existing then
        local placement = runPlacement(input[8])
        if not placement then return end
        coords = placement.coords
        heading = placement.heading
    end

    TriggerServerEvent('nexus_crafting:server:saveWorkbench', {
        id = input[1],
        label = input[2],
        type = input[3],
        category = input[4],
        job = input[5] ~= '' and input[5] or nil,
        jobs = parseJobs(input[6]),
        recipes = parseCsv(input[7]),
        model = input[8],
        coords = { x = coords.x, y = coords.y, z = coords.z },
        heading = heading,
        size = { x = input[9], y = input[10], z = input[11] },
        enabled = input[12] ~= false,
        mode = input[13] ~= '' and input[13] or nil,
        ownerGang = input[14] ~= '' and input[14] or nil,
    })
end

local function prepareStationForEdit(station)
    local copy = {}
    for key, value in pairs(station or {}) do copy[key] = value end

    copy.recipesText = table.concat(copy.recipes or {}, ',')
    if type(copy.jobs) == 'table' then
        local parts = {}
        for job, grade in pairs(copy.jobs) do
            parts[#parts + 1] = ('%s:%s'):format(job, grade)
        end
        table.sort(parts)
        copy.jobsText = table.concat(parts, ',')
    end

    return copy
end

local function saveStationOverride(station, coords, heading, enabled)
    TriggerServerEvent('nexus_crafting:server:saveWorkbench', {
        id = station.id,
        label = station.label,
        type = station.type,
        category = station.category,
        job = station.job,
        jobs = station.jobs or {},
        recipes = station.recipes or NexusCraftingConfig.defaultAccess.recipes,
        model = station.model or NexusCraftingConfig.defaultAccess.model,
        coords = {
            x = coords and coords.x or station.coords.x,
            y = coords and coords.y or station.coords.y,
            z = coords and coords.z or station.coords.z,
        },
        heading = heading or station.heading or 0.0,
        size = station.size or NexusCraftingConfig.editor.defaultSize,
        enabled = enabled,
        mode = station.mode,
        ownerGang = station.ownerGang,
    })
end

local function moveWorkbench(station)
    local placement = runPlacement(station.model or NexusCraftingConfig.defaultAccess.model)
    if not placement then return end
    saveStationOverride(station, placement.coords, placement.heading, station.enabled ~= false)
end

local function toggleWorkbench(station)
    saveStationOverride(station, station.coords, station.heading, station.enabled == false)
end

local function setWorkbenchWaypoint(station)
    SetNewWaypoint(station.coords.x, station.coords.y)
    notify(('Waypoint: %s'):format(station.label), 'inform')
end

local function stationStatus(station)
    local access = station.type or 'public'
    local state = station.enabled == false and 'Desactivada' or 'Activa'
    local origin = station.dynamic and 'SQL' or 'Config'
    return ('%s | %s | %s | %s'):format(state, origin, station.category or 'civil', access)
end

local function openWorkbenchActions(station)
    local options = {
        {
            title = 'Editar configuracion',
            description = 'Nombre, acceso, categoria, recetas, modelo, size y estado.',
            icon = 'pen-to-square',
            onSelect = function()
                openWorkbenchForm(prepareStationForEdit(station))
            end,
        },
        {
            title = 'Mover con preview 3D',
            description = 'Recoloca esta mesa con ghost, rotacion y snap al suelo.',
            icon = 'arrows-up-down-left-right',
            onSelect = function()
                moveWorkbench(station)
            end,
        },
        {
            title = station.enabled == false and 'Activar mesa' or 'Desactivar mesa',
            description = station.enabled == false and 'Vuelve a permitir uso a jugadores.' or 'Bloquea uso sin eliminar configuracion.',
            icon = station.enabled == false and 'toggle-on' or 'toggle-off',
            onSelect = function()
                toggleWorkbench(station)
            end,
        },
        {
            title = 'Marcar waypoint',
            description = ('%.2f, %.2f, %.2f'):format(station.coords.x, station.coords.y, station.coords.z),
            icon = 'map-pin',
            onSelect = function()
                setWorkbenchWaypoint(station)
            end,
        },
        {
            title = 'Eliminar override dinamico',
            description = station.dynamic and 'Elimina la mesa SQL.' or 'Esta mesa es de config; primero se edita como override.',
            icon = 'trash',
            disabled = not station.dynamic,
            onSelect = function()
                TriggerServerEvent('nexus_crafting:server:deleteWorkbench', station.id)
            end,
        },
    }

    lib.registerContext({
        id = 'nexus_crafting_editor_actions_' .. station.id,
        title = station.label,
        menu = 'nexus_crafting_editor',
        options = options,
    })

    lib.showContext('nexus_crafting_editor_actions_' .. station.id)
end

local function openWorkbenchList(stations)
    local options = {}

    table.sort(stations, function(a, b)
        return tostring(a.label) < tostring(b.label)
    end)

    for i = 1, #stations do
        local station = stations[i]
        local selectedStation = station
        options[#options + 1] = {
            title = station.label,
            description = stationStatus(station),
            icon = station.enabled == false and 'ban' or 'hammer',
            onSelect = function()
                openWorkbenchActions(selectedStation)
            end,
        }
    end

    lib.registerContext({
        id = 'nexus_crafting_editor_list',
        title = 'Mesas de crafting',
        menu = 'nexus_crafting_editor',
        options = options,
    })

    lib.showContext('nexus_crafting_editor_list')
end

local function openEditor()
    local ok, payload = lib.callback.await('nexus_crafting:server:editorList', false)
    if not ok then
        notify('No tienes permiso para abrir el editor.', 'error')
        return
    end

    local nearest = getNearestStation(4.0)
    local recipeIds = {}
    for recipeId in pairs(payload.recipes or {}) do
        recipeIds[#recipeIds + 1] = recipeId
    end
    table.sort(recipeIds)

    local options = {
        {
            title = 'Crear banco aqui',
            description = 'Crea un banco en tu posicion actual y lo sincroniza en vivo.',
            icon = 'plus',
            onSelect = function()
                openWorkbenchForm()
            end,
        },
        {
            title = 'Ver todas las mesas',
            description = ('Gestionar %s mesas activas/configuradas.'):format(#(payload.stations or {})),
            icon = 'list',
            onSelect = function()
                openWorkbenchList(payload.stations or {})
            end,
        },
    }

    if nearest then
        options[#options + 1] = {
            title = 'Gestionar banco cercano',
            description = ('%s | %.1fm'):format(nearest.label, #(GetEntityCoords(PlayerPedId()) - toVector(nearest.coords))),
            icon = 'screwdriver-wrench',
            onSelect = function()
                openWorkbenchActions(nearest)
            end,
        }
    end

    options[#options + 1] = {
        title = 'Recetas disponibles',
        description = 'IDs: ' .. table.concat(recipeIds, ', '),
        icon = 'list',
    }

    lib.registerContext({
        id = 'nexus_crafting_editor',
        title = 'Editor Crafting',
        options = options,
    })

    lib.showContext('nexus_crafting_editor')
end

exports('openCrafting', function(stationId)
    openStation(stationId or activeStation or NexusCraftingConfig.verticalSlice.stationId)
end)

RegisterCommand(NexusCraftingConfig.command, function(_, args)
    openStation(args[1] or NexusCraftingConfig.verticalSlice.stationId)
end, false)

RegisterCommand(NexusCraftingConfig.nearestCommand, openNearestStation, false)
RegisterKeyMapping(NexusCraftingConfig.nearestCommand, 'Usar mesa de crafting cercana', 'keyboard', 'E')

RegisterCommand('craftreload', function()
    refreshWorkbenches()
    notify(('Bancos recargados: %s'):format(#cachedStations), 'inform')
end, false)

RegisterCommand('craftdebug', debugCrafting, false)

RegisterCommand('craftclose', function()
    closeUi()
    notify('Interfaz de crafting cerrada.', 'inform')
end, false)

RegisterCommand('craftnuitest', function()
    isOpen = true
    isOpening = true
    nuiOpenAck = false
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    nui('diagnostic', {
        label = 'NUI TEST',
        message = 'Si ves este panel, html/index.html esta cargando correctamente.',
    })

    SetTimeout(8000, function()
        if nuiOpenAck then return end
        print('[nexus_crafting] NUI diagnostic timeout')
        closeUi()
        notify('La NUI de crafting no carga. Revisar ui_page/fxmanifest/cache.', 'error')
    end)
end, false)

RegisterCommand(NexusCraftingConfig.editorCommand, openEditor, false)

RegisterNetEvent('nexus_crafting:client:refreshWorkbenches', function(stations)
    refreshWorkbenches(stations)
    notify('Bancos de crafting actualizados.', 'inform')
end)

RegisterNetEvent('nexus_crafting:client:sensitiveAlert', function(data)
    if type(data) ~= 'table' or type(data.coords) ~= 'table' then return end

    SetNewWaypoint(data.coords.x + 0.0, data.coords.y + 0.0)
    notify(('Alerta marcada: %s'):format(data.label or 'actividad sospechosa'), 'warning')
end)

RegisterNUICallback('close', function(_, cb)
    closeUi()
    cb({ ok = true })
end)

RegisterNUICallback('opened', function(_, cb)
    nuiOpenAck = true
    isOpening = false
    cb({ ok = true })
end)

RegisterNUICallback('ready', function(data, cb)
    local source = data and data.source or 'app'
    print(('[nexus_crafting] NUI ready: %s'):format(source))
    cb({ ok = true })
end)

RegisterNUICallback('uiError', function(data, cb)
    local message = data and data.message or 'unknown'
    print(('[nexus_crafting] NUI error: %s'):format(message))
    cb({ ok = true })
end)

RegisterNUICallback('craft', function(data, cb)
    local recipeId = data and data.recipeId
    if type(recipeId) ~= 'string' or not activeStationData then
        cb({ ok = false })
        return
    end

    local recipe = nil
    for i = 1, #(activeStationData.recipes or {}) do
        local entry = activeStationData.recipes[i]
        if entry.id == recipeId then
            recipe = entry.data
            break
        end
    end

    cb({ ok = true })
    if recipe then
        craftRecipe(activeStation, recipeId, recipe)
    else
        notify('Receta invalida.', 'error')
    end
end)

RegisterNUICallback('refresh', function(_, cb)
    refreshStation()
    cb({ ok = true })
end)

CreateThread(function()
    while true do
        local sleep = 800
        local nearestPrompt = nil
        if NexusCraftingConfig.worldUi.enabled and #cachedStations > 0 then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)

            for i = 1, #cachedStations do
                local station = cachedStations[i]
                local stationCoords = toVector(station.coords)
                local distance = #(coords - stationCoords)

                if distance <= NexusCraftingConfig.worldUi.drawDistance then
                    sleep = 0
                    DrawMarker(
                        43,
                        stationCoords.x,
                        stationCoords.y,
                        stationCoords.z + 0.92,
                        0.0, 0.0, 0.0,
                        0.0, 0.0, station.heading or 0.0,
                        NexusCraftingConfig.worldUi.markerScale.x,
                        NexusCraftingConfig.worldUi.markerScale.y,
                        NexusCraftingConfig.worldUi.markerScale.z,
                        NexusCraftingConfig.worldUi.color.r,
                        NexusCraftingConfig.worldUi.color.g,
                        NexusCraftingConfig.worldUi.color.b,
                        NexusCraftingConfig.worldUi.color.a,
                        false, true, 2, false, nil, nil, false
                    )
                    drawText3d(vector3(stationCoords.x, stationCoords.y, stationCoords.z + 1.05), ('~b~%s~s~\n[E] Usar'):format(station.label))
                    if station.enabled == false then
                        drawText3d(vector3(stationCoords.x, stationCoords.y, stationCoords.z + 1.22), '~r~Desactivada~s~')
                    end

                    if distance <= NexusCraftingConfig.worldUi.interactDistance then
                        nearestPrompt = station
                    end

                    if distance <= NexusCraftingConfig.worldUi.interactDistance and (
                        IsControlJustPressed(0, 38)
                        or IsControlJustReleased(0, 38)
                        or IsDisabledControlJustPressed(0, 38)
                        or IsDisabledControlJustReleased(0, 38)
                    ) then
                        openStation(station.id)
                    end
                end
            end
        end

        if nearestPrompt and not isOpen then
            setTextUi(true, ('[E] Usar %s'):format(nearestPrompt.label))
        else
            setTextUi(false)
        end

        Wait(sleep)
    end
end)

CreateThread(function()
    while true do
        if isOpen then
            if IsDisabledControlJustPressed(0, 322)
                or IsDisabledControlJustPressed(0, 177)
                or IsControlJustPressed(0, 322)
                or IsControlJustPressed(0, 177)
            then
                closeUi()
                notify('Interfaz de crafting cerrada.', 'inform')
            end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Wait(1000)
    closeUi()
    refreshWorkbenches()
    print(('[nexus_crafting] manifest ui_page=%s'):format(GetResourceMetadata(resource, 'ui_page', 0) or 'nil'))
    print('[nexus_crafting] crafting cliente cargado')
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if GetResourceState('nexus_scene_core') == 'started' then
        exports.nexus_scene_core:cancel()
    end
    if isOpen then closeUi() end
    setTextUi(false)
    cleanupZones()
    cleanupProps()
end)
