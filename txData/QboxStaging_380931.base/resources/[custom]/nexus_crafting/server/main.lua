local function notify(source, description, notifyType)
    TriggerClientEvent('ox_lib:notify', source, {
        title = 'Crafting',
        description = description,
        type = notifyType or 'inform',
    })
end

local runtimeStations = {}
local getPlayer
local getCitizenId
local lastSensitiveAlertAt = 0
local craftSessions = {}
local fulfillingSessions = {}
local reserveAttempts = {}
local verticalSliceRuntimeReady = false
local verticalSliceRuntimeReason = 'schema_validation_pending'
local readinessProbeGeneration = 0

local function verticalSliceConfig()
    return NexusCraftingConfig.verticalSlice or {}
end

local function verticalSliceEnabled()
    return verticalSliceConfig().enabled == true
end

local function closeVerticalSlice(reason)
    verticalSliceRuntimeReady = false
    verticalSliceRuntimeReason = reason or 'schema_not_ready'
end

local function startReadinessProbe(trigger)
    if not verticalSliceEnabled() then return end

    readinessProbeGeneration = readinessProbeGeneration + 1
    local generation = readinessProbeGeneration
    local timeoutMs = 30000
    local pollMs = 500
    local deadline = GetGameTimer() + timeoutMs
    closeVerticalSlice(('schema_pending:%s'):format(trigger or 'unknown'))

    CreateThread(function()
        local lastReason = 'contracts_unavailable'
        while generation == readinessProbeGeneration and GetGameTimer() <= deadline do
            if GetResourceState('nexus_contracts') == 'started' then
                local ok, ready, reason, state = pcall(function()
                    return exports.nexus_contracts:isMechanicCraftingReady()
                end)
                if ok and ready == true then
                    verticalSliceRuntimeReady = true
                    verticalSliceRuntimeReason = nil
                    print(('[nexus_crafting] banco mecanico Phase 1B cargado (%s)'):format(trigger or 'probe'))
                    return
                end

                lastReason = ok and (reason or state or 'schema_not_ready') or 'contracts_export_failed'
                if ok and state == 'failed' then
                    closeVerticalSlice(lastReason)
                    print(('^1[nexus_crafting] Phase 1B blocked: %s^7'):format(tostring(lastReason)))
                    return
                end
            end
            Wait(pollMs)
        end

        if generation == readinessProbeGeneration then
            closeVerticalSlice(lastReason)
            print(('^1[nexus_crafting] Phase 1B readiness timeout after %sms: %s^7'):format(
                timeoutMs,
                tostring(lastReason)
            ))
        end
    end)
end

local function isVerticalSliceScope(stationId, recipeId)
    local config = verticalSliceConfig()
    return verticalSliceEnabled()
        and stationId == config.stationId
        and recipeId == config.recipeId
end

local function createCraftSession(source, stationId, recipeId, duration, reservation, flow)
    local now = GetGameTimer()
    local token = ('%s:%s:%s:%s:%s'):format(source, stationId, recipeId, now, math.random(100000, 999999))
    craftSessions[source] = {
        token = token,
        stationId = stationId,
        recipeId = recipeId,
        startedAt = now,
        duration = math.max(500, tonumber(duration) or 5000),
        reservationId = reservation and reservation.reservationId or nil,
        lotId = reservation and reservation.lotId or nil,
        citizenid = getCitizenId and getCitizenId(source) or nil,
        expiresAt = reservation and reservation.expiresAt or nil,
        flow = flow, -- 'mechanic' | 'modular', fijado exclusivamente en canCraft; el cliente nunca lo ve ni lo envia
    }
    return token
end

local function reserveAttemptKey(source, stationId, recipeId)
    return ('%s:%s:%s'):format(source, stationId, recipeId)
end

local function allowReserveAttempt(source, stationId, recipeId)
    local key = reserveAttemptKey(source, stationId, recipeId)
    local now = GetGameTimer()
    local lastAttempt = reserveAttempts[key]
    local cooldown = math.max(250, tonumber(verticalSliceConfig().reserveRateLimitMs) or 1500)
    if lastAttempt and now - lastAttempt < cooldown then return false end
    reserveAttempts[key] = now
    return true
end

local function clearReserveAttempt(source, stationId, recipeId)
    reserveAttempts[reserveAttemptKey(source, stationId, recipeId)] = nil
end

-- Solo lectura: valida token/estacion/receta contra craftSessions, sin mover
-- nada. Permite inspeccionar session.flow antes de decidir si se consume.
local function peekCraftSession(source, stationId, recipeId, token)
    local session = craftSessions[source]
    if not session or type(token) ~= 'string' or token ~= session.token then return nil end
    if session.stationId ~= stationId or session.recipeId ~= recipeId then return nil end
    return session
end

local function consumeCraftSession(source, stationId, recipeId, token)
    local session = peekCraftSession(source, stationId, recipeId, token)
    if not session then return false, 'invalid_session' end

    local elapsed = GetGameTimer() - session.startedAt
    if elapsed < session.duration - 250 then return false, 'too_early' end
    local expiresAt = tonumber(session.expiresAt)
    if elapsed > session.duration + 60000 or (expiresAt and os.time() > expiresAt) then
        craftSessions[source] = nil
        return false, 'expired_session', session
    end

    session.phase = 'finishing'
    craftSessions[source] = nil
    fulfillingSessions[source] = session
    return true, nil, session
end

local function cancelCraftSession(source, token)
    local session = craftSessions[source]
    if not session or type(token) ~= 'string' or session.token ~= token then return nil end
    craftSessions[source] = nil
    return session
end

local function decodeJson(value, fallback)
    if type(value) ~= 'string' or value == '' then return fallback end

    local ok, decoded = pcall(json.decode, value)
    if not ok or type(decoded) ~= 'table' then return fallback end

    return decoded
end

local function normalizeWorkbench(row)
    return {
        label = row.label,
        type = row.type or NexusCraftingConfig.defaultAccess.type,
        -- Sin valor por defecto a proposito: una fila sin 'mode' explicito en
        -- BD queda inalcanzable (mismo criterio que las mesas estaticas).
        mode = row.mode,
        owner_gang = row.owner_gang,
        category = row.category or NexusCraftingConfig.defaultAccess.category,
        enabled = tonumber(row.enabled) ~= 0,
        job = row.job,
        jobs = decodeJson(row.jobs, {}),
        model = row.model or NexusCraftingConfig.defaultAccess.model,
        coords = vector3(tonumber(row.x), tonumber(row.y), tonumber(row.z)),
        size = vector3(tonumber(row.sx) or 1.6, tonumber(row.sy) or 1.2, tonumber(row.sz) or 1.2),
        heading = tonumber(row.heading) or 0.0,
        recipes = decodeJson(row.recipes, NexusCraftingConfig.defaultAccess.recipes),
        dynamic = true,
    }
end

local function loadWorkbenches()
    -- Las mesas dinamicas se cargan siempre, independientemente del estado
    -- del subsistema mecanico -- ese ya no decide que mesas son alcanzables.
    runtimeStations = {}

    local rows = NexusCraftingFetchWorkbenches()
    for i = 1, #(rows or {}) do
        runtimeStations[rows[i].id] = normalizeWorkbench(rows[i])
    end
end

-- Valor por defecto seguro: una estacion sin 'mode' explicito (estatica o
-- dinamica) se trata como no reconocida -- invisible en el mundo y no
-- craftable, no solo lo segundo. Esto preserva exactamente el estado actual
-- de las 4 mesas modulares que aun no tienen mode asignado.
local function getStation(stationId)
    if type(stationId) ~= 'string' then return nil end
    local station = runtimeStations[stationId] or NexusCraftingConfig.stations[stationId]
    if not station or not station.mode then return nil end
    return station
end

local function getAllStations()
    local stations = {}

    for stationId, station in pairs(NexusCraftingConfig.stations) do
        if station.mode then stations[stationId] = station end
    end

    for stationId, station in pairs(runtimeStations) do
        if station.mode then stations[stationId] = station end
    end

    return stations
end

local function getStationSummaries()
    local summaries = {}

    for stationId, station in pairs(getAllStations()) do
        summaries[#summaries + 1] = {
            id = stationId,
            label = station.label,
            type = station.type,
            mode = station.mode,
            category = station.category,
            enabled = station.enabled ~= false,
            job = station.job,
            jobs = station.jobs or {},
            ownerGang = station.owner_gang,
            model = station.model or NexusCraftingConfig.defaultAccess.model,
            coords = { x = station.coords.x, y = station.coords.y, z = station.coords.z },
            size = { x = station.size.x, y = station.size.y, z = station.size.z },
            heading = station.heading or 0.0,
            recipes = station.recipes or {},
            dynamic = station.dynamic == true,
        }
    end

    return summaries
end

local function refreshClients()
    TriggerClientEvent('nexus_crafting:client:refreshWorkbenches', -1, getStationSummaries())
end

local function isEditorAllowed(source)
    return source == 0 or IsPlayerAceAllowed(source, NexusCraftingConfig.editor.ace)
end

local function sanitizeWorkbenchPayload(source, data)
    if type(data) ~= 'table' then return nil, 'invalid_payload' end

    local id = tostring(data.id or ''):lower():gsub('[^%w_%-]', '')
    if id == '' or #id > 64 then return nil, 'invalid_id' end

    local label = tostring(data.label or NexusCraftingConfig.editor.defaultLabel):sub(1, 96)
    local stationType = tostring(data.type or NexusCraftingConfig.defaultAccess.type)
    local category = tostring(data.category or NexusCraftingConfig.defaultAccess.category)
    local enabled = data.enabled ~= false
    local allowedTypes = { public = true, job = true, jobs = true, illegal = true, gang = true }
    if not allowedTypes[stationType] then return nil, 'invalid_type' end
    if not NexusCraftingConfig.categories[category] then return nil, 'invalid_category' end

    -- 'mode' explicito, valor por defecto seguro: sin mode reconocido, la
    -- mesa queda inalcanzable (getStation/getAllStations la filtran). Por
    -- ahora el editor solo puede crear mode='job' -- no reactiva el flujo
    -- mecanico ni las mesas modulares legacy.
    local mode = data.mode ~= nil and tostring(data.mode):sub(1, 16) or nil
    if mode ~= nil and mode ~= 'job' then return nil, 'invalid_mode' end

    local ownerGang = data.ownerGang and tostring(data.ownerGang):lower():gsub('[^%w_%-]', ''):sub(1, 64) or nil
    if mode == 'job' then
        if stationType ~= 'gang' then return nil, 'job_mode_requires_gang_type' end
        if not ownerGang or ownerGang == '' then return nil, 'owner_gang_required' end
    else
        ownerGang = nil
    end

    local recipes = {}
    for i = 1, #(data.recipes or NexusCraftingConfig.defaultAccess.recipes) do
        local recipeId = tostring((data.recipes or {})[i] or '')
        if NexusCraftingConfig.recipes[recipeId] then
            recipes[#recipes + 1] = recipeId
        end
    end
    if #recipes == 0 then recipes = NexusCraftingConfig.defaultAccess.recipes end

    local coords = data.coords or {}
    local size = data.size or {}
    local job = data.job and tostring(data.job):sub(1, 64) or nil
    local jobs = type(data.jobs) == 'table' and data.jobs or {}
    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    if not x or not y or not z then return nil, 'invalid_coords' end
    local model = tostring(data.model or NexusCraftingConfig.defaultAccess.model):sub(1, 96)

    return {
        id = id,
        label = label,
        type = stationType,
        mode = mode,
        category = category,
        enabled = enabled,
        job = job,
        jobs = jobs,
        ownerGang = ownerGang,
        model = model,
        recipes = recipes,
        coords = vector3(x, y, z),
        size = vector3(tonumber(size.x) or NexusCraftingConfig.editor.defaultSize.x, tonumber(size.y) or NexusCraftingConfig.editor.defaultSize.y, tonumber(size.z) or NexusCraftingConfig.editor.defaultSize.z),
        heading = tonumber(data.heading) or NexusCraftingConfig.editor.defaultHeading,
        createdBy = getCitizenId(source),
    }
end

getPlayer = function(source)
    if GetResourceState('qbx_core') ~= 'started' then return nil end
    return exports.qbx_core:GetPlayer(source)
end

getCitizenId = function(source)
    local player = getPlayer(source)
    return player and player.PlayerData and player.PlayerData.citizenid or nil
end

local function getCriminalProgress(source)
    local citizenid = getCitizenId(source)
    if not citizenid or GetResourceState('nexus_progression') ~= 'started' then
        return { level = 1, xp = 0, reputation = 0 }
    end

    local progression = exports.nexus_progression:getProgressionByCitizen(citizenid)
    local criminal = progression and progression.criminal or {}

    return {
        level = tonumber(criminal.level) or 1,
        xp = tonumber(criminal.xp) or 0,
        reputation = tonumber(criminal.reputation) or 0,
    }
end

local function hasStationAccess(source, station)
    if not station then return false end
    if station.enabled == false then return false end
    if station.type == 'public' then return true end

    local player = getPlayer(source)
    local data = player and player.PlayerData or {}

    if station.type == 'job' then
        local job = data.job
        if station.mode == 'mechanic' then
            local grade = job and job.grade
            grade = type(grade) == 'table' and grade.level or grade
            return job
                and job.name == verticalSliceConfig().job
                and job.onduty == true
                and (tonumber(grade) or 0) >= (tonumber(verticalSliceConfig().minimumGrade) or 0)
        end
        return job and job.name == station.job
    end

    if station.type == 'jobs' then
        local job = data.job or {}
        local requiredGrade = station.jobs and station.jobs[job.name]
        return requiredGrade ~= nil and tonumber(job.grade and job.grade.level or 0) >= tonumber(requiredGrade or 0)
    end

    if station.type == 'illegal' then
        if GetResourceState('nexus_gangs') == 'started' then
            local gang = exports.nexus_gangs:getPlayerGang(source)
            if gang and gang.name and gang.name ~= 'none' then return true end
        end

        if data.gang and data.gang.name and data.gang.name ~= 'none' then return true end

        local requiredRep = tonumber(NexusCraftingConfig.illegalAccess and NexusCraftingConfig.illegalAccess.minimumCriminalReputation or 0)
        return (tonumber(getCriminalProgress(source).reputation) or 0) >= requiredRep
    end

    -- Mesas de banda: solo usadas por el sistema de trabajos persistentes
    -- (nexus_crafting:server:startJob), nunca por el flujo sincrono de canCraft.
    if station.type == 'gang' then
        -- Abrir/ver la mesa es publico -- el gate de banda propietaria vive
        -- exclusivamente en startJob. collectJob (retiro, incluido el robo)
        -- tampoco pasa por esta funcion.
        return true
    end

    return false
end

local function getCraftingProgress(source)
    local citizenid = getCitizenId(source)
    if not citizenid or GetResourceState('nexus_progression') ~= 'started' then
        return { level = 1, xp = 0, reputation = 0 }
    end

    local progression = exports.nexus_progression:getProgressionByCitizen(citizenid)
    local crafting = progression and progression.crafting or {}

    return {
        level = tonumber(crafting.level) or 1,
        xp = tonumber(crafting.xp) or 0,
        reputation = tonumber(crafting.reputation) or 0,
        currentXp = tonumber(crafting.currentXp) or 0,
        requiredXp = tonumber(crafting.requiredXp) or 1000,
    }
end

local function hasRequiredLevel(source, recipe)
    local progress = getCraftingProgress(source)
    return progress.level >= tonumber(recipe.requiredLevel or 1), progress
end

local function hasRecipeVisibility(progress, recipe)
    local level = tonumber(recipe.hiddenUntilLevel or 0)
    local reputation = tonumber(recipe.hiddenUntilReputation or 0)

    return (tonumber(progress.level) or 1) >= level and (tonumber(progress.reputation) or 0) >= reputation
end

local function hasRequiredReputation(progress, recipe)
    local reputation = tonumber(recipe.requiredReputation or recipe.hiddenUntilReputation or 0)
    return (tonumber(progress.reputation) or 0) >= reputation, reputation
end

local function hasBlueprint(source, recipe)
    if not recipe.blueprint then return true, nil, 0 end

    local count = exports.ox_inventory:GetItemCount(source, recipe.blueprint)
    return count > 0, recipe.blueprint, count
end

local function classifiedRecipe(recipeId, recipe)
    return {
        id = recipeId,
        hidden = true,
        unlocked = false,
        lockedReason = 'Clasificado',
        data = {
            label = 'Clasificado',
            category = recipe.category or 'illegal',
            output = { item = 'classified', count = 1 },
            ingredients = {},
            duration = recipe.duration or 5000,
            requiredLevel = recipe.hiddenUntilLevel or recipe.requiredLevel or 1,
            hiddenUntilLevel = recipe.hiddenUntilLevel,
            hiddenUntilReputation = recipe.hiddenUntilReputation,
            sensitive = recipe.sensitive == true,
            risk = recipe.risk,
        },
        missing = {},
    }
end

local function isNearStation(source, station)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return false end

    local coords = GetEntityCoords(ped)
    return #(coords - station.coords) <= NexusCraftingConfig.interactDistance
end

local function getPublicRecipes(stationId)
    local station = getStation(stationId)
    local recipes = {}

    if not station then return recipes end

    for i = 1, #(station.recipes or {}) do
        local recipeId = station.recipes[i]
        local recipe = NexusCraftingUtils.getRecipe(recipeId)
        if recipe then
            recipes[#recipes + 1] = {
                id = recipeId,
                data = NexusCraftingUtils.copyRecipe(recipe),
            }
        end
    end

    return recipes
end

local getMissingIngredients

local function getWorkshopStock(source)
    if GetResourceState('nexus_contracts') ~= 'started' then return nil, 'contracts_unavailable' end
    return exports.nexus_contracts:getMechanicStockSnapshot(source)
end

local function getStationRecipesForPlayer(source, stationId)
    local station = getStation(stationId)
    local recipes = {}

    if not station then return recipes end

    if station.mode == 'mechanic' then
        if not isVerticalSliceScope(stationId, verticalSliceConfig().recipeId) then return recipes end
        local recipeId = verticalSliceConfig().recipeId
        local recipe = NexusCraftingUtils.getRecipe(recipeId)
        if not recipe then return recipes end
        local snapshot = getWorkshopStock(source)
        local available = snapshot and tonumber(snapshot.available) or 0
        local missing = {}
        if available < 1 then
            for i = 1, #(recipe.ingredients or {}) do
                local ingredient = recipe.ingredients[i]
                missing[#missing + 1] = {
                    item = ingredient.item,
                    required = ingredient.count,
                    current = 0,
                }
            end
        end
        recipes[1] = {
            id = recipeId,
            data = NexusCraftingUtils.copyRecipe(recipe),
            hidden = false,
            unlocked = available > 0,
            lockedReason = available > 0 and nil or 'Stock del taller agotado',
            missing = missing,
            workshopStock = snapshot,
        }
        return recipes
    end

    local progress = getCraftingProgress(source)
    for i = 1, #(station.recipes or {}) do
        local recipeId = station.recipes[i]
        local recipe = NexusCraftingUtils.getRecipe(recipeId)
        if recipe then
            local publicRecipe = NexusCraftingUtils.copyRecipe(recipe)
            local missing = getMissingIngredients(source, recipe)
            local requiredLevel = tonumber(recipe.requiredLevel or 1)
            local visible = hasRecipeVisibility(progress, recipe)
            local hasRep, requiredReputation = hasRequiredReputation(progress, recipe)
            local blueprintOk, blueprintItem, blueprintCount = hasBlueprint(source, recipe)

            if not visible then
                recipes[#recipes + 1] = classifiedRecipe(recipeId, recipe)
            else
                local unlocked = progress.level >= requiredLevel and hasRep and blueprintOk
                local lockedReason = nil

                if progress.level < requiredLevel then
                    lockedReason = ('Requiere nivel %s'):format(requiredLevel)
                elseif not hasRep then
                    lockedReason = ('Requiere reputacion %s'):format(requiredReputation)
                elseif not blueprintOk then
                    lockedReason = 'Plano requerido'
                end

                recipes[#recipes + 1] = {
                    id = recipeId,
                    data = publicRecipe,
                    hidden = false,
                    unlocked = unlocked,
                    lockedReason = lockedReason,
                    missing = missing,
                    blueprint = blueprintItem,
                    hasBlueprint = blueprintOk,
                    blueprintCount = blueprintCount,
                    requiredReputation = requiredReputation,
                    risk = recipe.risk,
                    sensitive = recipe.sensitive == true,
                }
            end
        end
    end

    return recipes
end

local function notifyPoliceRisk(source, station, recipe, chance)
    if not NexusCraftingConfig.sensitiveAlert.enabled then return false end
    if chance <= 0 or math.random(100) > chance then return false end

    local now = os.time()
    local cooldown = tonumber(NexusCraftingConfig.sensitiveAlert.cooldownSeconds or 120)
    if now - lastSensitiveAlertAt < cooldown then return false end

    lastSensitiveAlertAt = now
    local coords = station.coords

    for _, playerId in ipairs(GetPlayers()) do
        local target = tonumber(playerId)
        local player = getPlayer(target)
        local job = player and player.PlayerData and player.PlayerData.job
        if job and NexusCraftingConfig.sensitiveAlert.policeJobs[job.name] then
            TriggerClientEvent('ox_lib:notify', target, {
                title = 'Alerta industrial',
                description = ('Actividad sospechosa detectada: %s'):format(recipe.label),
                type = 'warning',
            })
            TriggerClientEvent('nexus_crafting:client:sensitiveAlert', target, {
                label = recipe.label,
                coords = { x = coords.x, y = coords.y, z = coords.z },
            })
        end
    end

    return true
end

local function applyTerritoryRisk(source, station, chance)
    if GetResourceState('nexus_territories') ~= 'started' then return chance, nil end

    local context = exports.nexus_territories:getControlContext(source, station.coords)
    if context and context.rivalInControlledZone then
        chance = chance + (tonumber(context.benefits.rivalAlertBonusPercent) or 0)
    end

    return chance, context
end

getMissingIngredients = function(source, recipe)
    local missing = {}

    for i = 1, #(recipe.ingredients or {}) do
        local ingredient = recipe.ingredients[i]
        local count = exports.ox_inventory:GetItemCount(source, ingredient.item)
        if count < ingredient.count then
            missing[#missing + 1] = {
                item = ingredient.item,
                required = ingredient.count,
                current = count,
            }
        end
    end

    return missing
end

local function removeIngredients(source, recipe)
    for i = 1, #recipe.ingredients do
        local ingredient = recipe.ingredients[i]
        local removed = exports.ox_inventory:RemoveItem(source, ingredient.item, ingredient.count)
        if not removed then return false end
    end

    return true
end

local function refundIngredients(source, recipe)
    for i = 1, #(recipe.ingredients or {}) do
        local ingredient = recipe.ingredients[i]
        exports.ox_inventory:AddItem(source, ingredient.item, ingredient.count)
    end
end

lib.callback.register('nexus_crafting:server:getStation', function(source, stationId)
    local station = getStation(stationId)
    if not station then return false, 'invalid_station' end
    if station.mode == 'mechanic' and not verticalSliceRuntimeReady then
        return false, verticalSliceRuntimeReason or 'schema_not_ready'
    end
    if station.enabled == false and not isEditorAllowed(source) then return false, 'station_disabled' end
    if not hasStationAccess(source, station) then return false, 'no_access' end
    if station.mode == 'mechanic' and not isNearStation(source, station) then return false, 'too_far' end

    local category = NexusCraftingUtils.getCategory(station.category)
    local snapshot = station.mode == 'mechanic' and getWorkshopStock(source) or nil
    local citizenid = getCitizenId(source)
    local quarantine = station.mode == 'mechanic' and citizenid and GetResourceState('nexus_contracts') == 'started'
        and exports.nexus_contracts:isMechanicCraftQuarantined(citizenid)
        or nil
    return true, {
        id = stationId,
        label = station.label,
        type = station.type,
        category = station.category or 'civil',
        enabled = station.enabled ~= false,
        categoryLabel = snapshot
            and ('Stock taller: %s disponible | %s reservado'):format(snapshot.available, snapshot.reserved)
            or category.label,
        categoryVariant = category.variant,
        progress = getCraftingProgress(source),
        recipes = getStationRecipesForPlayer(source, stationId),
        quarantine = quarantine,
    }
end)

lib.callback.register('nexus_crafting:server:canCraft', function(source, stationId, recipeId)
    local station = getStation(stationId)
    local recipe = NexusCraftingUtils.getRecipe(recipeId)

    if not station or not recipe then return false, 'invalid_recipe' end
    if station.mode == 'job' then return false, 'use_job_system' end
    if station.mode == 'mechanic' then
        if not verticalSliceRuntimeReady then
            return false, verticalSliceRuntimeReason or 'schema_not_ready'
        end
        -- Rechazo temprano de UX -- no sustituye el guard de reserveMechanicCraft,
        -- que sigue siendo la validacion final obligatoria mas abajo en la cadena.
        -- Se evalua ANTES de cualquier llamada que pueda crear una reserva real.
        do
            local citizenid = getCitizenId(source)
            if citizenid and GetResourceState('nexus_contracts') == 'started' then
                local quarantine = exports.nexus_contracts:isMechanicCraftQuarantined(citizenid)
                if quarantine then return false, 'quarantine_active' end
            end
        end
        if not isVerticalSliceScope(stationId, recipeId) then return false, 'recipe_not_allowed' end
        local config = verticalSliceConfig()
        if recipe.output.item ~= config.outputItem or tonumber(recipe.output.count) ~= config.outputCount then
            return false, 'invalid_output'
        end
        if station.enabled == false then return false, 'station_disabled' end
        if not hasStationAccess(source, station) then return false, 'no_access' end
        if not isNearStation(source, station) then return false, 'too_far' end
        if GetResourceState('nexus_contracts') ~= 'started' then return false, 'contracts_unavailable' end
        local ready = exports.nexus_contracts:isMechanicCraftingReady()
        if ready ~= true then return false, 'schema_not_ready' end
        if not exports.ox_inventory:CanCarryItem(source, config.outputItem, config.outputCount) then
            return false, 'no_space'
        end
        if not allowReserveAttempt(source, stationId, recipeId) then return false, 'rate_limited' end

        local reservation, reserveReason = exports.nexus_contracts:reserveMechanicCraft(source, stationId, recipeId)
        if not reservation then return false, reserveReason or 'stock_unavailable' end

        local duration = math.max(500, tonumber(recipe.duration) or 5000)
        return true, {
            label = recipe.label,
            duration = duration,
            sessionToken = createCraftSession(source, stationId, recipeId, duration, reservation, 'mechanic'),
            reservationId = reservation.reservationId,
            lotId = reservation.lotId,
        }
    end
    -- Valor por defecto seguro: una estacion sin mode='modular' explicito
    -- nunca cae en el flujo sincrono, aunque haya superado los chequeos de
    -- arriba (getStation ya la habria bloqueado antes de llegar aqui, pero
    -- esta es la segunda barrera, no la unica).
    if station.mode ~= 'modular' then return false, 'station_disabled' end
    if station.enabled == false then return false, 'station_disabled' end
    if not NexusCraftingUtils.recipeAllowedAtStation(station, recipeId) then return false, 'recipe_not_allowed' end
    if not hasStationAccess(source, station) then return false, 'no_access' end
    if not isNearStation(source, station) then return false, 'too_far' end
    local unlocked, progress = hasRequiredLevel(source, recipe)
    if not unlocked then return false, 'level_locked', { requiredLevel = recipe.requiredLevel or 1, currentLevel = progress.level } end
    if not hasRecipeVisibility(progress, recipe) then return false, 'classified_recipe' end

    local hasRep, requiredReputation = hasRequiredReputation(progress, recipe)
    if not hasRep then return false, 'reputation_locked', { requiredReputation = requiredReputation, currentReputation = progress.reputation or 0 } end

    local blueprintOk, blueprintItem, blueprintCount = hasBlueprint(source, recipe)
    if not blueprintOk then return false, 'missing_blueprint', { item = blueprintItem, current = blueprintCount, required = 1 } end

    if not exports.ox_inventory:CanCarryItem(source, recipe.output.item, recipe.output.count or 1) then return false, 'no_space' end

    local missing = getMissingIngredients(source, recipe)
    if #missing > 0 then return false, 'missing_items', missing end

    local duration = math.max(500, tonumber(recipe.duration) or 5000)
    return true, {
        label = recipe.label,
        duration = duration,
        sensitive = recipe.sensitive == true,
        risk = recipe.risk,
        blueprint = recipe.blueprint,
        sessionToken = createCraftSession(source, stationId, recipeId, duration, nil, 'modular'),
    }
end)

lib.callback.register('nexus_crafting:server:getStations', function(source)
    return getStationSummaries()
end)

lib.callback.register('nexus_crafting:server:editorList', function(source)
    if not isEditorAllowed(source) then return false, 'no_access' end

    return true, {
        stations = getStationSummaries(),
        recipes = NexusCraftingConfig.recipes,
        categories = NexusCraftingConfig.categories,
        defaultAccess = NexusCraftingConfig.defaultAccess,
    }
end)

local function addedItemSlot(response)
    if type(response) ~= 'table' then return nil end
    if tonumber(response.slot) then return tonumber(response.slot) end
    local first = response[1]
    if type(first) ~= 'table' then return nil end
    if type(first.item) == 'table' and tonumber(first.item.slot) then return tonumber(first.item.slot) end
    return tonumber(first.slot)
end

local function outputMetadata(session)
    return {
        craftReservationId = session.reservationId,
        sourceLotId = session.lotId,
        type = 'mechanic_repairkit',
    }
end

local function metadataMatchesOutput(metadata, session)
    return type(metadata) == 'table'
        and metadata.craftReservationId == session.reservationId
        and metadata.sourceLotId == session.lotId
        and metadata.type == 'mechanic_repairkit'
end

local function findExactOutputSlot(source, session, preferredSlot)
    local config = verticalSliceConfig()
    local slots = exports.ox_inventory:GetSlotsWithItem(source, config.outputItem) or {}
    for i = 1, #slots do
        local slot = slots[i]
        if metadataMatchesOutput(slot.metadata, session)
            and (not preferredSlot or tonumber(slot.slot) == tonumber(preferredSlot)) then
            return slot
        end
    end
end

local function removeExactOutput(source, session, preferredSlot)
    local slot = findExactOutputSlot(source, session, preferredSlot)
    if not slot then return false end
    return exports.ox_inventory:RemoveItem(
        source,
        verticalSliceConfig().outputItem,
        verticalSliceConfig().outputCount,
        slot.metadata,
        slot.slot,
        false,
        true
    ) == true
end

local function releaseOrBlock(source, session, reason)
    if not session.reservationId then return true end
    local released = exports.nexus_contracts:releaseMechanicCraft(source, session.reservationId, reason)
    if released == true then return true end
    exports.nexus_contracts:markMechanicCraftAmbiguous(source, session.reservationId, reason .. '_release_failed')
    return false
end

-- Solo limpieza de tracking. Nunca toca la reserva en nexus_contracts.
-- Usar tras un exito mecanico (la reserva ya se consumio via
-- completeMechanicCraft y session.reservationId sigue poblado, pero no hay
-- nada pendiente que liberar) y como paso final de abortFinishingSession.
local function clearFulfillingSession(source, session)
    if fulfillingSessions[source] == session then fulfillingSessions[source] = nil end
end

-- Reserva PENDIENTE (no completada): intenta liberarla o, si el release
-- falla, la deja en cuarentena. Despues limpia el tracking. NUNCA usar tras
-- un completeMechanicCraft exitoso.
local function abortFinishingSession(source, session, reason)
    local released = releaseOrBlock(source, session, reason)
    clearFulfillingSession(source, session)
    return released
end

local finishModularCraft -- forward-declaration: debe existir antes de finishMechanicCraft/finishCraft

lib.callback.register('nexus_crafting:server:cancelCraft', function(source, sessionToken)
    local session = cancelCraftSession(source, sessionToken)
    if not session then return false, 'invalid_session' end
    if releaseOrBlock(source, session, 'player_cancelled') then
        clearReserveAttempt(source, session.stationId, session.recipeId)
        return true
    end
    notify(source, 'Incidencia pendiente. La reserva queda bloqueada para revision.', 'error')
    return false, 'incident_pending'
end)

local function finishMechanicCraft(source, session)
    local config = verticalSliceConfig()
    if not exports.ox_inventory:CanCarryItem(source, config.outputItem, config.outputCount) then
        local released = abortFinishingSession(source, session, 'inventory_full')
        if released then clearReserveAttempt(source, session.stationId, session.recipeId) end
        return false, 'no_space'
    end

    local began, beginData = exports.nexus_contracts:beginMechanicCraft(source, session.reservationId)
    if began ~= true then
        local released = abortFinishingSession(source, session, 'begin_failed')
        if released then clearReserveAttempt(source, session.stationId, session.recipeId) end
        if not released then return false, 'incident_pending' end
        return false, beginData or 'transition_failed'
    end
    session.phase = 'fulfilling'
    if type(beginData) ~= 'table' or beginData.lotId ~= session.lotId then
        exports.nexus_contracts:markMechanicCraftAmbiguous(source, session.reservationId, 'begin_lot_mismatch')
        clearFulfillingSession(source, session)
        return false, 'incident_pending'
    end

    local metadata = outputMetadata(session)
    local added, response = exports.ox_inventory:AddItem(
        source,
        config.outputItem,
        config.outputCount,
        metadata
    )
    if not added then
        local released = abortFinishingSession(source, session, 'inventory_add_failed')
        if released then clearReserveAttempt(source, session.stationId, session.recipeId) end
        if not released then return false, 'incident_pending' end
        return false, 'inventory_add_failed'
    end

    local slotNumber = addedItemSlot(response)
    local outputSlot = findExactOutputSlot(source, session, slotNumber)
        or (slotNumber and findExactOutputSlot(source, session, nil))
    if not outputSlot then
        exports.nexus_contracts:markMechanicCraftAmbiguous(source, session.reservationId, 'output_slot_unresolved')
        clearFulfillingSession(source, session)
        return false, 'incident_pending'
    end

    local completed, completeReason = exports.nexus_contracts:completeMechanicCraft(
        source,
        session.reservationId
    )
    if completed ~= true then
        if removeExactOutput(source, session, outputSlot.slot) then
            local released = abortFinishingSession(source, session, 'stock_commit_failed')
            if released then clearReserveAttempt(source, session.stationId, session.recipeId) end
            if not released then return false, 'incident_pending' end
            return false, completeReason or 'stock_commit_failed'
        end
        exports.nexus_contracts:markMechanicCraftAmbiguous(source, session.reservationId, 'stock_commit_failed_output_not_recoverable')
        clearFulfillingSession(source, session)
        return false, 'incident_pending'
    end

    -- Exito: la reserva ya se consumio via completeMechanicCraft.
    -- session.reservationId sigue poblado (no se autoborra) -- por eso aqui
    -- NUNCA se llama abortFinishingSession/releaseOrBlock, solo tracking.
    clearFulfillingSession(source, session)
    clearReserveAttempt(source, session.stationId, session.recipeId)
    notify(source, 'Has fabricado 1x kit de reparacion.', 'success')
    return true, {
        item = config.outputItem,
        count = config.outputCount,
        lotId = session.lotId,
    }
end

lib.callback.register('nexus_crafting:server:finishCraft', function(source, stationId, recipeId, sessionToken)
    local peeked = peekCraftSession(source, stationId, recipeId, sessionToken)
    if not peeked then return false, 'invalid_session' end

    if peeked.flow == 'mechanic' and not verticalSliceRuntimeReady then
        -- La sesion NO se toca: sigue en craftSessions, reintentable.
        return false, verticalSliceRuntimeReason or 'schema_not_ready'
    end

    if GetResourceState('nexus_bridge') == 'started'
        and not exports.nexus_bridge:rateLimit(source, NexusCraftingConfig.rateLimitBucket) then
        return false, 'rate_limited'
    end

    local sessionOk, sessionReason, session = consumeCraftSession(source, stationId, recipeId, sessionToken)
    if not sessionOk then
        if session and sessionReason == 'expired_session' then
            local released = abortFinishingSession(source, session, 'ttl_expired')
            if released then clearReserveAttempt(source, session.stationId, session.recipeId) end
        end
        return false, sessionReason
    end

    local station = getStation(session.stationId)
    local recipe = NexusCraftingUtils.getRecipe(session.recipeId)
    if not station or not recipe then
        local released = abortFinishingSession(source, session, 'station_or_recipe_missing_at_finish')
        if released then clearReserveAttempt(source, session.stationId, session.recipeId) end
        return false, 'station_or_recipe_missing_at_finish'
    end

    if session.flow == 'mechanic' then
        return finishMechanicCraft(source, session)
    elseif session.flow == 'modular' then
        return finishModularCraft(source, session, station, recipe)
    end

    local released = abortFinishingSession(source, session, 'unsupported_flow')
    if released then clearReserveAttempt(source, session.stationId, session.recipeId) end
    return false, 'unsupported_flow'
end)

RegisterNetEvent('nexus_crafting:server:saveWorkbench', function(data)
    local src = source
    if not isEditorAllowed(src) then return notify(src, 'No tienes permiso para editar mesas.', 'error') end
    if GetResourceState('nexus_bridge') == 'started' and not exports.nexus_bridge:rateLimit(src, 'admin') then return end

    local bench, reason = sanitizeWorkbenchPayload(src, data)
    if not bench then return notify(src, ('Mesa invalida: %s'):format(reason), 'error') end

    NexusCraftingSaveWorkbench(bench)
    runtimeStations[bench.id] = {
        label = bench.label,
        type = bench.type,
        mode = bench.mode,
        category = bench.category,
        enabled = bench.enabled ~= false,
        job = bench.job,
        jobs = bench.jobs,
        owner_gang = bench.ownerGang,
        model = bench.model,
        coords = bench.coords,
        size = bench.size,
        heading = bench.heading,
        recipes = bench.recipes,
        dynamic = true,
    }

    refreshClients()
    notify(src, ('Mesa guardada: %s'):format(bench.id), 'success')
end)

RegisterNetEvent('nexus_crafting:server:deleteWorkbench', function(stationId)
    local src = source
    if not isEditorAllowed(src) then return notify(src, 'No tienes permiso para editar mesas.', 'error') end
    if type(stationId) ~= 'string' or not runtimeStations[stationId] then
        return notify(src, 'Solo se pueden eliminar mesas dinamicas.', 'error')
    end
    local activeJob = MySQL.scalar.await(
        'SELECT id FROM nexus_crafting_jobs WHERE station_id = ? AND active_station_key IS NOT NULL',
        { stationId }
    )
    if activeJob then
        return notify(src, 'No se puede eliminar: hay un trabajo activo en esta mesa.', 'error')
    end

    NexusCraftingDeleteWorkbench(stationId)
    runtimeStations[stationId] = nil
    refreshClients()
    notify(src, ('Mesa eliminada: %s'):format(stationId), 'success')
end)

finishModularCraft = function(source, session, station, recipe)
    local stationId, recipeId = session.stationId, session.recipeId

    if station.enabled == false then
        local released = abortFinishingSession(source, session, 'station_disabled')
        if released then clearReserveAttempt(source, stationId, recipeId) end
        notify(source, 'Esta mesa esta desactivada.', 'error')
        return false, 'station_disabled'
    end
    if not NexusCraftingUtils.recipeAllowedAtStation(station, recipeId) then
        local released = abortFinishingSession(source, session, 'recipe_not_allowed')
        if released then clearReserveAttempt(source, stationId, recipeId) end
        return false, 'recipe_not_allowed'
    end
    if not hasStationAccess(source, station) then
        local released = abortFinishingSession(source, session, 'no_access')
        if released then clearReserveAttempt(source, stationId, recipeId) end
        notify(source, 'No tienes acceso a esta mesa.', 'error')
        return false, 'no_access'
    end
    if not isNearStation(source, station) then
        local released = abortFinishingSession(source, session, 'too_far')
        if released then clearReserveAttempt(source, stationId, recipeId) end
        notify(source, 'Estas demasiado lejos de la mesa.', 'error')
        return false, 'too_far'
    end
    local unlocked, progress = hasRequiredLevel(source, recipe)
    if not unlocked then
        local released = abortFinishingSession(source, session, 'level_locked')
        if released then clearReserveAttempt(source, stationId, recipeId) end
        notify(source, ('Requiere nivel crafting %s.'):format(recipe.requiredLevel or 1), 'error')
        return false, 'level_locked'
    end
    if not hasRecipeVisibility(progress, recipe) then
        local released = abortFinishingSession(source, session, 'classified_recipe')
        if released then clearReserveAttempt(source, stationId, recipeId) end
        notify(source, 'Receta clasificada.', 'error')
        return false, 'classified_recipe'
    end

    local hasRep, requiredReputation = hasRequiredReputation(progress, recipe)
    if not hasRep then
        local released = abortFinishingSession(source, session, 'reputation_locked')
        if released then clearReserveAttempt(source, stationId, recipeId) end
        notify(source, ('Requiere reputacion crafting %s.'):format(requiredReputation), 'error')
        return false, 'reputation_locked'
    end

    local blueprintOk, blueprintItem = hasBlueprint(source, recipe)
    if not blueprintOk then
        local released = abortFinishingSession(source, session, 'missing_blueprint')
        if released then clearReserveAttempt(source, stationId, recipeId) end
        notify(source, ('Requiere plano: %s'):format(blueprintItem), 'error')
        return false, 'missing_blueprint'
    end

    local missing = getMissingIngredients(source, recipe)
    if #missing > 0 then
        local released = abortFinishingSession(source, session, 'missing_items')
        if released then clearReserveAttempt(source, stationId, recipeId) end
        notify(source, 'Te faltan materiales.', 'error')
        return false, 'missing_items'
    end

    if not exports.ox_inventory:CanCarryItem(source, recipe.output.item, recipe.output.count or 1) then
        local released = abortFinishingSession(source, session, 'no_space')
        if released then clearReserveAttempt(source, stationId, recipeId) end
        notify(source, 'No tienes espacio suficiente.', 'error')
        return false, 'no_space'
    end

    if not removeIngredients(source, recipe) then
        local released = abortFinishingSession(source, session, 'ingredients_consume_failed')
        if released then clearReserveAttempt(source, stationId, recipeId) end
        notify(source, 'No se pudieron consumir los materiales.', 'error')
        return false, 'ingredients_consume_failed'
    end

    local added = exports.ox_inventory:AddItem(source, recipe.output.item, recipe.output.count or 1)
    if not added then
        refundIngredients(source, recipe)
        local released = abortFinishingSession(source, session, 'inventory_add_failed')
        if released then clearReserveAttempt(source, stationId, recipeId) end
        notify(source, 'No se pudo entregar el resultado.', 'error')
        return false, 'inventory_add_failed'
    end

    -- Exito: session.reservationId siempre es nil en flow='modular', asi que
    -- solo hace falta limpiar tracking -- no hay nada que abortFinishingSession
    -- pudiera liberar, pero se mantiene la simetria con el flujo mecanico.
    clearFulfillingSession(source, session)
    clearReserveAttempt(source, stationId, recipeId)

    local citizenid = getCitizenId(source)
    local chance = recipe.risk and tonumber(recipe.risk.policeAlertChance or 0) or 0
    local territoryContext
    chance, territoryContext = applyTerritoryRisk(source, station, chance)
    local policeAlert = recipe.sensitive == true and notifyPoliceRisk(source, station, recipe, chance) or false

    if citizenid then
        NexusCraftingLog(citizenid, stationId, recipeId, recipe.output)
        if recipe.sensitive == true then
            NexusCraftingLogSensitive({
                citizenid = citizenid,
                source = source,
                stationId = stationId,
                recipeId = recipeId,
                output = recipe.output,
                blueprint = recipe.blueprint,
                policeAlert = policeAlert,
                riskChance = chance,
                coords = station.coords,
            })
        end

        if GetResourceState('nexus_progression') == 'started' then
            exports.nexus_progression:addProgression(citizenid, 'crafting', recipe.xp or 0, recipe.reputation or 0)
            TriggerClientEvent('nexus_progression:client:tick', source, 'crafting', recipe.xp or 0, recipe.reputation or 0)

            local criminalConfig = NexusCraftingConfig.criminalProgression or {}
            local shouldRewardCriminal = criminalConfig.enabled
                and (station.type == 'illegal' or recipe.category == 'illegal')
                and (not criminalConfig.sensitiveOnly or recipe.sensitive == true)

            if shouldRewardCriminal then
                local criminalXp = math.floor((tonumber(recipe.xp) or 0) * (tonumber(criminalConfig.xpMultiplier) or 0.25))
                local criminalRep = tonumber(criminalConfig.reputation) or 1
                exports.nexus_progression:addProgression(citizenid, 'criminal', criminalXp, criminalRep)
                TriggerClientEvent('nexus_progression:client:tick', source, 'criminal', criminalXp, criminalRep)

                if GetResourceState('nexus_territories') == 'started' then
                    exports.nexus_territories:addInfluenceAtCoords(source, station.coords, criminalRep, 'illegal_crafting')
                end
            end
        end
    end

    local territoryText = territoryContext and territoryContext.rivalInControlledZone and (' | territorio rival: %s'):format(territoryContext.owner) or ''
    notify(source, ('Has creado: %sx %s%s'):format(recipe.output.count or 1, recipe.label, territoryText), 'success')
    return true, { item = recipe.output.item, count = recipe.output.count or 1 }
end

AddEventHandler('playerDropped', function()
    craftSessions[source] = nil
    fulfillingSessions[source] = nil
    local prefix = ('%s:'):format(source)
    for key in pairs(reserveAttempts) do
        if key:sub(1, #prefix) == prefix then reserveAttempts[key] = nil end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == 'nexus_contracts' and verticalSliceEnabled() then
        readinessProbeGeneration = readinessProbeGeneration + 1
        closeVerticalSlice('contracts_restarting')
        print('[nexus_crafting] Phase 1B closed while nexus_contracts restarts')
        return
    end
    -- Este barrido cubre sesiones de AMBOS flow (mecanico y modular), asi que
    -- ya no depende de verticalSliceEnabled() -- debe correr aunque el
    -- subsistema mecanico este apagado y solo haya sesiones modulares en curso.
    if resource ~= GetCurrentResourceName() then return end

    -- craftSessions: releaseOrBlock ya es no-op seguro para sesiones modulares
    -- (sin reservationId), asi que este bucle corre siempre, sin depender de
    -- nexus_contracts.
    for src, session in pairs(craftSessions) do
        releaseOrBlock(src, session, 'crafting_resource_stopped')
    end

    for src, session in pairs(fulfillingSessions) do
        if session.flow == 'mechanic' then
            -- Solo esta rama necesita nexus_contracts de verdad.
            if GetResourceState('nexus_contracts') == 'started' then
                local queued, queueReason = exports.nexus_contracts:queueMechanicCraftAmbiguousFromCraftingStop(
                    session.reservationId,
                    session.citizenid,
                    'crafting_resource_stopped_while_fulfilling'
                )
                if queued ~= true then
                    print(('^1[nexus_crafting] failed to queue ambiguous fulfilling reservation=%s reason=%s^7'):format(
                        tostring(session.reservationId),
                        tostring(queueReason)
                    ))
                end
            else
                print(('^1[nexus_crafting] sesion mecanica abandonada en fulfillingSessions sin nexus_contracts disponible para escalar, source=%s reservationId=%s^7'):format(
                    tostring(src),
                    tostring(session.reservationId)
                ))
            end
        else
            print(('[nexus_crafting] sesion modular abandonada en fulfillingSessions al detener el recurso, source=%s citizenid=%s'):format(
                tostring(src),
                tostring(session.citizenid)
            ))
        end
    end
end)

AddEventHandler('nexus_contracts:server:craftingSchemaChanged', function()
    startReadinessProbe('contracts_schema_signal')
end)

AddEventHandler('onResourceStart', function(resource)
    if resource == 'nexus_contracts' and verticalSliceEnabled() then
        startReadinessProbe('contracts_resource_start')
        return
    end
    if resource ~= GetCurrentResourceName() then return end
    loadWorkbenches()
    if verticalSliceEnabled() then
        startReadinessProbe('crafting_resource_start')
    end
    print(('[nexus_crafting] crafting cargado (subsistema mecanico: %s)'):format(
        verticalSliceEnabled() and 'activo' or 'inactivo'
    ))
end)

-- ============================================================
-- Sistema de trabajos persistentes por mesa (Fase 1)
-- Subsistema completamente separado del flujo mecanico de reservas
-- (nexus_contracts) y del flujo sincrono anterior (craftSessions /
-- fulfillingSessions / finishCraft). No comparte tablas ni sesiones.
-- ============================================================

local JOB_EXPIRY_SECONDS = 72 * 3600
local JOB_CLAIM_LEASE_SECONDS = 30
local JOB_PREPARING_STALE_SECONDS = 120

local function generateJobToken(prefix, source)
    return ('%s-%s-%s-%s'):format(prefix, GetGameTimer(), math.random(100000, 999999), tostring(source))
end

local function insertJobEvent(jobId, eventType, actorCitizenid, details)
    MySQL.insert.await([[
        INSERT INTO nexus_crafting_job_events (job_id, event_type, actor_citizenid, transition_key, details)
        VALUES (?, ?, ?, ?, ?)
    ]], {
        jobId,
        eventType,
        actorCitizenid,
        ('%s:%s:%s:%s'):format(jobId, eventType, GetGameTimer(), math.random(100000, 999999)),
        details and json.encode(details) or nil,
    })
end

local function getJobByKey(jobKey)
    if type(jobKey) ~= 'string' then return nil end
    return MySQL.single.await('SELECT * FROM nexus_crafting_jobs WHERE job_key = ?', { jobKey })
end

-- Remueve ingredientes uno a uno, sin usar removeIngredients() (esa funcion no
-- informa que se removio exactamente si falla a medio camino). Aqui se necesita
-- saber con certeza que compensar, no adivinar.
local function commitJobIngredients(source, recipe)
    local removed = {}
    for i = 1, #(recipe.ingredients or {}) do
        local ingredient = recipe.ingredients[i]
        local ok = exports.ox_inventory:RemoveItem(source, ingredient.item, ingredient.count)
        if not ok then
            return false, removed
        end
        removed[#removed + 1] = { item = ingredient.item, count = ingredient.count }
    end
    return true, removed
end

local function compensateJobIngredients(source, removedList)
    local allOk = true
    for i = 1, #removedList do
        local ok = exports.ox_inventory:AddItem(source, removedList[i].item, removedList[i].count)
        if not ok then allOk = false end
    end
    return allOk
end

local function revertJobClaim(jobId, claimKey, claimAction)
    MySQL.update.await([[
        UPDATE nexus_crafting_jobs
        SET state='in_progress', claim_action=NULL, claim_actor_citizenid=NULL, claim_key=NULL, claim_started_at=NULL
        WHERE id=? AND state='claiming' AND claim_action=? AND claim_key=?
    ]], { jobId, claimAction, claimKey })
end

lib.callback.register('nexus_crafting:server:getStationJob', function(source, stationId)
    if type(stationId) ~= 'string' then return nil end
    local job = MySQL.single.await([[
        SELECT job_key, recipe_id, station_type, owner_gang, state, ready_at,
               initiator_citizenid, initiator_gang
        FROM nexus_crafting_jobs
        WHERE station_id = ? AND active_station_key IS NOT NULL
    ]], { stationId })
    if not job then return nil end
    -- El cliente no tiene os.time() garantizado (es una API server-only en
    -- FiveM) -- se manda la hora del servidor junto con ready_at para que
    -- calcule la cuenta regresiva sin depender de ningun native de tiempo.
    job.server_now = os.time()
    return job
end)

lib.callback.register('nexus_crafting:server:startJob', function(source, stationId, recipeId)
    local station = getStation(stationId)
    local recipe = NexusCraftingUtils.getRecipe(recipeId)
    if not station or not recipe then return false, 'invalid_recipe' end
    if station.enabled == false then return false, 'station_disabled' end
    if not NexusCraftingUtils.recipeAllowedAtStation(station, recipeId) then return false, 'recipe_not_allowed' end

    if station.type == 'gang' then
        if not station.owner_gang or station.owner_gang == '' then return false, 'station_misconfigured' end
        if GetResourceState('nexus_gangs') ~= 'started' then return false, 'no_access' end
        local gang = exports.nexus_gangs:getPlayerGang(source)
        if not (gang and gang.name == station.owner_gang) then return false, 'no_access' end
    elseif not hasStationAccess(source, station) then
        return false, 'no_access'
    end
    if not isNearStation(source, station) then return false, 'too_far' end

    local unlocked, progress = hasRequiredLevel(source, recipe)
    if not unlocked then return false, 'level_locked' end
    if not hasRecipeVisibility(progress, recipe) then return false, 'classified_recipe' end
    if not hasRequiredReputation(progress, recipe) then return false, 'reputation_locked' end
    if not hasBlueprint(source, recipe) then return false, 'missing_blueprint' end
    if #getMissingIngredients(source, recipe) > 0 then return false, 'missing_items' end

    local citizenid = getCitizenId(source)
    if not citizenid then return false, 'invalid_session' end

    local gangData = GetResourceState('nexus_gangs') == 'started' and exports.nexus_gangs:getPlayerGang(source) or nil
    local initiatorGang = gangData and gangData.name ~= 'none' and gangData.name or nil

    local jobKey = generateJobToken('JOB', source)
    local readyAt = os.time() + math.ceil((tonumber(recipe.duration) or 5000) / 1000)
    local outputSnapshot = json.encode({
        item = recipe.output.item,
        count = recipe.output.count or 1,
    })

    -- pcall: no se puede confirmar con certeza si un choque contra la UNIQUE KEY
    -- de active_station_key (mesa ocupada) devuelve nil limpio o lanza un error
    -- Lua a traves de oxmysql -- se cubre cualquiera de los dos casos igual.
    local insertOk, jobId = pcall(function()
        return MySQL.insert.await([[
            INSERT INTO nexus_crafting_jobs
                (job_key, station_id, recipe_id, initiator_citizenid, initiator_gang,
                 station_type, owner_gang, output_snapshot, state, ready_at, active_station_key)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'preparing', ?, ?)
        ]], {
            jobKey, stationId, recipeId, citizenid, initiatorGang,
            station.type, station.owner_gang, outputSnapshot, readyAt, stationId,
        })
    end)

    if not insertOk or not jobId or jobId == 0 then
        return false, 'station_busy'
    end

    insertJobEvent(jobId, 'started', citizenid, { stationId = stationId, recipeId = recipeId })

    local committed, removedList = commitJobIngredients(source, recipe)
    if not committed then
        local refunded = compensateJobIngredients(source, removedList)
        MySQL.update.await([[
            UPDATE nexus_crafting_jobs
            SET state = IF(?, 'cancelled', 'refund_pending'), active_station_key = NULL,
                cancel_reason = 'ingredients_commit_failed', ingredients_snapshot = ?
            WHERE id = ? AND state = 'preparing'
        ]], { refunded, json.encode(removedList), jobId })
        insertJobEvent(jobId,
            refunded and 'ingredients_commit_failed_refunded' or 'ingredients_commit_failed_unrefunded',
            citizenid, { removed = removedList })
        return false, 'missing_items'
    end

    MySQL.update.await(
        "UPDATE nexus_crafting_jobs SET state='in_progress', ingredients_snapshot=? WHERE id=? AND state='preparing'",
        { json.encode(removedList), jobId }
    )
    insertJobEvent(jobId, 'ingredients_committed', citizenid, {})

    notify(source, ('Trabajo iniciado: %s'):format(recipe.label), 'success')
    return true, { jobKey = jobKey, readyAt = readyAt, label = recipe.label }
end)

lib.callback.register('nexus_crafting:server:collectJob', function(source, jobKey)
    local job = getJobByKey(jobKey)
    if not job then return false, 'invalid_job' end
    local station = getStation(job.station_id)
    if not station or not isNearStation(source, station) then return false, 'too_far' end
    if job.state ~= 'in_progress' then return false, 'invalid_job' end
    if os.time() < tonumber(job.ready_at) then return false, 'not_ready' end

    local citizenid = getCitizenId(source)
    if not citizenid then return false, 'invalid_session' end

    local claimKey = generateJobToken('CLAIM', source)
    local claimedRows = MySQL.update.await([[
        UPDATE nexus_crafting_jobs
        SET state='claiming', claim_action='collect', claim_actor_citizenid=?,
            claim_key=?, claim_started_at=UNIX_TIMESTAMP()
        WHERE job_key=? AND state='in_progress' AND ready_at <= UNIX_TIMESTAMP()
    ]], { citizenid, claimKey, jobKey })

    if claimedRows ~= 1 then return false, 'already_claimed' end

    -- Revalidar cercania: el jugador pudo alejarse entre el pre-chequeo y ganar el claim.
    if not isNearStation(source, station) then
        revertJobClaim(job.id, claimKey, 'collect')
        return false, 'too_far'
    end

    local outputSnapshot = json.decode(job.output_snapshot)
    local gangData = GetResourceState('nexus_gangs') == 'started' and exports.nexus_gangs:getPlayerGang(source) or nil
    local collectorGang = gangData and gangData.name or 'none'
    local isTheft = (job.station_type == 'gang') and (collectorGang ~= job.owner_gang)

    local added = exports.ox_inventory:AddItem(source, outputSnapshot.item, outputSnapshot.count)
    if not added then
        revertJobClaim(job.id, claimKey, 'collect')
        return false, 'no_space'
    end

    local finalizedRows = MySQL.update.await([[
        UPDATE nexus_crafting_jobs
        SET state='collected', active_station_key=NULL, collected_at=NOW(),
            collected_by_citizenid=?, is_theft=?,
            claim_action=NULL, claim_actor_citizenid=NULL, claim_key=NULL, claim_started_at=NULL
        WHERE id=? AND state='claiming' AND claim_action='collect' AND claim_key=?
    ]], { citizenid, isTheft and 1 or 0, job.id, claimKey })

    if finalizedRows ~= 1 then
        local removedBack = exports.ox_inventory:RemoveItem(source, outputSnapshot.item, outputSnapshot.count)
        insertJobEvent(job.id,
            removedBack and 'collect_finalize_failed_compensated' or 'collect_finalize_failed_uncompensated',
            citizenid, { claim_key = claimKey })
        MySQL.update.await(
            "UPDATE nexus_crafting_jobs SET state='ambiguous', active_station_key=NULL WHERE id=? AND state='claiming' AND claim_action='collect' AND claim_key=?",
            { job.id, claimKey }
        )
        return false, 'incident_pending'
    end

    insertJobEvent(job.id, isTheft and 'stolen' or 'collected', citizenid, { is_theft = isTheft })

    if isTheft then
        local initiatorPlayer = exports.qbx_core:GetPlayerByCitizenId(job.initiator_citizenid)
        if initiatorPlayer then
            notify(initiatorPlayer.PlayerData.source,
                ('Te han robado un trabajo en %s.'):format(station.label or job.station_id), 'error')
        end
    end

    notify(source,
        isTheft and ('Has robado: %sx %s'):format(outputSnapshot.count, outputSnapshot.item)
                 or ('Has retirado: %sx %s'):format(outputSnapshot.count, outputSnapshot.item),
        'success')
    return true, { item = outputSnapshot.item, count = outputSnapshot.count, isTheft = isTheft }
end)

lib.callback.register('nexus_crafting:server:cancelJob', function(source, jobKey)
    local job = getJobByKey(jobKey)
    if not job then return false, 'invalid_job' end
    local station = getStation(job.station_id)
    if not station or not isNearStation(source, station) then return false, 'too_far' end

    local citizenid = getCitizenId(source)
    if not citizenid then return false, 'invalid_session' end
    if job.initiator_citizenid ~= citizenid then return false, 'not_owner' end
    if job.state ~= 'in_progress' then return false, 'invalid_job' end
    if os.time() >= tonumber(job.ready_at) then return false, 'already_ready' end

    local claimKey = generateJobToken('CLAIM', source)
    local claimedRows = MySQL.update.await([[
        UPDATE nexus_crafting_jobs
        SET state='claiming', claim_action='cancel', claim_actor_citizenid=?,
            claim_key=?, claim_started_at=UNIX_TIMESTAMP()
        WHERE job_key=? AND initiator_citizenid=? AND state='in_progress' AND ready_at > UNIX_TIMESTAMP()
    ]], { citizenid, claimKey, jobKey, citizenid })

    if claimedRows ~= 1 then return false, 'already_claimed' end

    if not isNearStation(source, station) then
        revertJobClaim(job.id, claimKey, 'cancel')
        return false, 'too_far'
    end

    local ingredients = json.decode(job.ingredients_snapshot or '[]') or {}
    local refunded = true
    for i = 1, #ingredients do
        local ok = exports.ox_inventory:AddItem(source, ingredients[i].item, ingredients[i].count)
        if not ok then refunded = false end
    end

    local finalizedRows = MySQL.update.await([[
        UPDATE nexus_crafting_jobs
        SET state = IF(?, 'cancelled', 'refund_pending'), active_station_key = NULL, cancel_reason = 'player_cancelled',
            claim_action=NULL, claim_actor_citizenid=NULL, claim_key=NULL, claim_started_at=NULL
        WHERE id=? AND state='claiming' AND claim_action='cancel' AND claim_key=?
    ]], { refunded, job.id, claimKey })

    if finalizedRows ~= 1 then
        insertJobEvent(job.id, 'cancel_finalize_failed', citizenid, { claim_key = claimKey, refunded = refunded })
        MySQL.update.await(
            "UPDATE nexus_crafting_jobs SET state='ambiguous', active_station_key=NULL WHERE id=? AND state='claiming' AND claim_action='cancel' AND claim_key=?",
            { job.id, claimKey }
        )
        return false, 'incident_pending'
    end

    insertJobEvent(job.id, refunded and 'cancelled' or 'refund_failed', citizenid, { refunded = refunded })
    notify(source,
        refunded and 'Trabajo cancelado, materiales devueltos.'
                  or 'Trabajo cancelado. Hubo un problema devolviendo materiales; queda registrado para revision.',
        refunded and 'success' or 'error')
    return true
end)

CreateThread(function()
    Wait(5000)
    MySQL.update.await(
        "UPDATE nexus_crafting_jobs SET state='ambiguous', active_station_key=NULL WHERE state='preparing' AND started_at < NOW() - INTERVAL 2 MINUTE"
    )

    while true do
        Wait(60000)
        MySQL.update.await(
            "UPDATE nexus_crafting_jobs SET state='expired', active_station_key=NULL WHERE state='in_progress' AND ready_at <= UNIX_TIMESTAMP() - ?",
            { JOB_EXPIRY_SECONDS }
        )
        MySQL.update.await(
            "UPDATE nexus_crafting_jobs SET state='ambiguous', active_station_key=NULL WHERE state='claiming' AND claim_started_at < UNIX_TIMESTAMP() - ?",
            { JOB_CLAIM_LEASE_SECONDS }
        )
    end
end)
