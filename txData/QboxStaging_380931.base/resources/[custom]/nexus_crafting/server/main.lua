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

local function createCraftSession(source, stationId, recipeId, duration, reservation)
    local now = GetGameTimer()
    local token = ('%s:%s:%s:%s:%s'):format(source, stationId, recipeId, now, math.random(100000, 999999))
    craftSessions[source] = {
        token = token,
        stationId = stationId,
        recipeId = recipeId,
        startedAt = now,
        duration = math.max(500, tonumber(duration) or 5000),
        reservationId = reservation.reservationId,
        lotId = reservation.lotId,
        citizenid = getCitizenId and getCitizenId(source) or nil,
        expiresAt = reservation.expiresAt,
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

local function consumeCraftSession(source, stationId, recipeId, token)
    local session = craftSessions[source]
    if not session or type(token) ~= 'string' or token ~= session.token then return false, 'invalid_session' end
    if session.stationId ~= stationId or session.recipeId ~= recipeId then return false, 'invalid_session' end

    local elapsed = GetGameTimer() - session.startedAt
    if elapsed < session.duration - 250 then return false, 'too_early' end
    if elapsed > session.duration + 60000 or os.time() > tonumber(session.expiresAt) then
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
    runtimeStations = {}
    if verticalSliceEnabled() then return end

    local rows = NexusCraftingFetchWorkbenches()
    for i = 1, #(rows or {}) do
        runtimeStations[rows[i].id] = normalizeWorkbench(rows[i])
    end
end

local function getStation(stationId)
    if type(stationId) ~= 'string' then return nil end
    if verticalSliceEnabled() and stationId ~= verticalSliceConfig().stationId then return nil end
    return runtimeStations[stationId] or NexusCraftingConfig.stations[stationId]
end

local function getAllStations()
    local stations = {}

    if verticalSliceEnabled() then
        local stationId = verticalSliceConfig().stationId
        local station = NexusCraftingConfig.stations[stationId]
        if station then stations[stationId] = station end
        return stations
    end

    for stationId, station in pairs(NexusCraftingConfig.stations) do
        stations[stationId] = station
    end

    for stationId, station in pairs(runtimeStations) do
        stations[stationId] = station
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
            category = station.category,
            enabled = station.enabled ~= false,
            job = station.job,
            jobs = station.jobs or {},
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
    local allowedTypes = { public = true, job = true, jobs = true, illegal = true }
    if not allowedTypes[stationType] then return nil, 'invalid_type' end
    if not NexusCraftingConfig.categories[category] then return nil, 'invalid_category' end

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
        category = category,
        enabled = enabled,
        job = job,
        jobs = jobs,
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
        if verticalSliceEnabled() then
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

    if verticalSliceEnabled() then
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
    if verticalSliceEnabled() and not verticalSliceRuntimeReady then
        return false, verticalSliceRuntimeReason or 'schema_not_ready'
    end
    local station = getStation(stationId)
    if not station then return false, 'invalid_station' end
    if station.enabled == false and not isEditorAllowed(source) then return false, 'station_disabled' end
    if not hasStationAccess(source, station) then return false, 'no_access' end
    if verticalSliceEnabled() and not isNearStation(source, station) then return false, 'too_far' end

    local category = NexusCraftingUtils.getCategory(station.category)
    local snapshot = verticalSliceEnabled() and getWorkshopStock(source) or nil
    local citizenid = getCitizenId(source)
    local quarantine = verticalSliceEnabled() and citizenid and GetResourceState('nexus_contracts') == 'started'
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
    if verticalSliceEnabled() then
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
            sessionToken = createCraftSession(source, stationId, recipeId, duration, reservation),
            reservationId = reservation.reservationId,
            lotId = reservation.lotId,
        }
    end
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
        sessionToken = createCraftSession(source, stationId, recipeId, duration),
    }
end)

lib.callback.register('nexus_crafting:server:getStations', function(source)
    return getStationSummaries()
end)

lib.callback.register('nexus_crafting:server:editorList', function(source)
    if verticalSliceEnabled() then return false, 'vertical_slice_locked' end
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
    local released = exports.nexus_contracts:releaseMechanicCraft(source, session.reservationId, reason)
    if released == true then return true end
    exports.nexus_contracts:markMechanicCraftAmbiguous(source, session.reservationId, reason .. '_release_failed')
    return false
end

lib.callback.register('nexus_crafting:server:cancelCraft', function(source, sessionToken)
    if not verticalSliceEnabled() then return false, 'unsupported_profile' end
    if not verticalSliceRuntimeReady then
        return false, verticalSliceRuntimeReason or 'schema_not_ready'
    end
    local session = cancelCraftSession(source, sessionToken)
    if not session then return false, 'invalid_session' end
    if releaseOrBlock(source, session, 'player_cancelled') then
        clearReserveAttempt(source, session.stationId, session.recipeId)
        return true
    end
    notify(source, 'Incidencia pendiente. La reserva queda bloqueada para revision.', 'error')
    return false, 'incident_pending'
end)

lib.callback.register('nexus_crafting:server:finishCraft', function(source, stationId, recipeId, sessionToken)
    if not verticalSliceRuntimeReady then
        return false, verticalSliceRuntimeReason or 'schema_not_ready'
    end
    if not isVerticalSliceScope(stationId, recipeId) then return false, 'recipe_not_allowed' end
    if GetResourceState('nexus_bridge') == 'started'
        and not exports.nexus_bridge:rateLimit(source, NexusCraftingConfig.rateLimitBucket) then
        return false, 'rate_limited'
    end

    local sessionOk, sessionReason, session = consumeCraftSession(source, stationId, recipeId, sessionToken)
    if not sessionOk then
        if session and sessionReason == 'expired_session' then
            if releaseOrBlock(source, session, 'ttl_expired') then
                clearReserveAttempt(source, session.stationId, session.recipeId)
            end
        end
        return false, sessionReason
    end

    local function stopTracking(resetReserveLimit)
        if fulfillingSessions[source] == session then fulfillingSessions[source] = nil end
        if resetReserveLimit then clearReserveAttempt(source, session.stationId, session.recipeId) end
    end

    local config = verticalSliceConfig()
    if not exports.ox_inventory:CanCarryItem(source, config.outputItem, config.outputCount) then
        local released = releaseOrBlock(source, session, 'inventory_full')
        stopTracking(released)
        return false, 'no_space'
    end

    local began, beginData = exports.nexus_contracts:beginMechanicCraft(source, session.reservationId)
    if began ~= true then
        local released = releaseOrBlock(source, session, 'begin_failed')
        stopTracking(released)
        if not released then return false, 'incident_pending' end
        return false, beginData or 'transition_failed'
    end
    session.phase = 'fulfilling'
    if type(beginData) ~= 'table' or beginData.lotId ~= session.lotId then
        exports.nexus_contracts:markMechanicCraftAmbiguous(
            source,
            session.reservationId,
            'begin_lot_mismatch'
        )
        stopTracking(false)
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
        local released = releaseOrBlock(source, session, 'inventory_add_failed')
        stopTracking(released)
        if not released then return false, 'incident_pending' end
        return false, 'inventory_add_failed'
    end

    local slotNumber = addedItemSlot(response)
    local outputSlot = findExactOutputSlot(source, session, slotNumber)
        or (slotNumber and findExactOutputSlot(source, session, nil))
    if not outputSlot then
        exports.nexus_contracts:markMechanicCraftAmbiguous(
            source,
            session.reservationId,
            'output_slot_unresolved'
        )
        stopTracking(false)
        return false, 'incident_pending'
    end

    local completed, completeReason = exports.nexus_contracts:completeMechanicCraft(
        source,
        session.reservationId
    )
    if completed ~= true then
        if removeExactOutput(source, session, outputSlot.slot) then
            local released = releaseOrBlock(source, session, 'stock_commit_failed')
            stopTracking(released)
            if not released then return false, 'incident_pending' end
            return false, completeReason or 'stock_commit_failed'
        end
        exports.nexus_contracts:markMechanicCraftAmbiguous(
            source,
            session.reservationId,
            'stock_commit_failed_output_not_recoverable'
        )
        stopTracking(false)
        return false, 'incident_pending'
    end

    stopTracking(true)
    notify(source, 'Has fabricado 1x kit de reparacion.', 'success')
    return true, {
        item = config.outputItem,
        count = config.outputCount,
        lotId = session.lotId,
    }
end)

RegisterNetEvent('nexus_crafting:server:saveWorkbench', function(data)
    local src = source
    if verticalSliceEnabled() then return notify(src, 'El editor esta bloqueado en el perfil F1B.', 'error') end
    if not isEditorAllowed(src) then return notify(src, 'No tienes permiso para editar mesas.', 'error') end
    if GetResourceState('nexus_bridge') == 'started' and not exports.nexus_bridge:rateLimit(src, 'admin') then return end

    local bench, reason = sanitizeWorkbenchPayload(src, data)
    if not bench then return notify(src, ('Mesa invalida: %s'):format(reason), 'error') end

    NexusCraftingSaveWorkbench(bench)
    runtimeStations[bench.id] = {
        label = bench.label,
        type = bench.type,
        category = bench.category,
        enabled = bench.enabled ~= false,
        job = bench.job,
        jobs = bench.jobs,
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
    if verticalSliceEnabled() then return notify(src, 'El editor esta bloqueado en el perfil F1B.', 'error') end
    if not isEditorAllowed(src) then return notify(src, 'No tienes permiso para editar mesas.', 'error') end
    if type(stationId) ~= 'string' or not runtimeStations[stationId] then
        return notify(src, 'Solo se pueden eliminar mesas dinamicas.', 'error')
    end

    NexusCraftingDeleteWorkbench(stationId)
    runtimeStations[stationId] = nil
    refreshClients()
    notify(src, ('Mesa eliminada: %s'):format(stationId), 'success')
end)

RegisterNetEvent('nexus_crafting:server:craft', function(stationId, recipeId, sessionToken)
    local src = source
    if verticalSliceEnabled() then
        print(('[nexus_crafting] blocked legacy craft event source=%s station=%s recipe=%s'):format(
            src,
            tostring(stationId),
            tostring(recipeId)
        ))
        return
    end
    local station = getStation(stationId)
    local recipe = NexusCraftingUtils.getRecipe(recipeId)

    if GetResourceState('nexus_bridge') == 'started' then
        if not exports.nexus_bridge:rateLimit(src, NexusCraftingConfig.rateLimitBucket) then return end
    end

    if not station or not recipe then return end
    local sessionOk, sessionReason = consumeCraftSession(src, stationId, recipeId, sessionToken)
    if not sessionOk then
        print(('[nexus_crafting] blocked craft without valid elapsed session source=%s station=%s recipe=%s reason=%s'):format(
            src,
            tostring(stationId),
            tostring(recipeId),
            tostring(sessionReason)
        ))
        return notify(src, 'La sesion de fabricacion no es valida.', 'error')
    end
    if station.enabled == false then return notify(src, 'Esta mesa esta desactivada.', 'error') end
    if not NexusCraftingUtils.recipeAllowedAtStation(station, recipeId) then return end
    if not hasStationAccess(src, station) then return notify(src, 'No tienes acceso a esta mesa.', 'error') end
    if not isNearStation(src, station) then return notify(src, 'Estas demasiado lejos de la mesa.', 'error') end
    local unlocked, progress = hasRequiredLevel(src, recipe)
    if not unlocked then return notify(src, ('Requiere nivel crafting %s.'):format(recipe.requiredLevel or 1), 'error') end
    if not hasRecipeVisibility(progress, recipe) then return notify(src, 'Receta clasificada.', 'error') end

    local hasRep, requiredReputation = hasRequiredReputation(progress, recipe)
    if not hasRep then return notify(src, ('Requiere reputacion crafting %s.'):format(requiredReputation), 'error') end

    local blueprintOk, blueprintItem = hasBlueprint(src, recipe)
    if not blueprintOk then return notify(src, ('Requiere plano: %s'):format(blueprintItem), 'error') end

    local missing = getMissingIngredients(src, recipe)
    if #missing > 0 then return notify(src, 'Te faltan materiales.', 'error') end

    if not exports.ox_inventory:CanCarryItem(src, recipe.output.item, recipe.output.count or 1) then
        return notify(src, 'No tienes espacio suficiente.', 'error')
    end

    if not removeIngredients(src, recipe) then
        return notify(src, 'No se pudieron consumir los materiales.', 'error')
    end

    local added = exports.ox_inventory:AddItem(src, recipe.output.item, recipe.output.count or 1)
    if not added then
        refundIngredients(src, recipe)
        return notify(src, 'No se pudo entregar el resultado.', 'error')
    end

    local citizenid = getCitizenId(src)
    local chance = recipe.risk and tonumber(recipe.risk.policeAlertChance or 0) or 0
    local territoryContext
    chance, territoryContext = applyTerritoryRisk(src, station, chance)
    local policeAlert = recipe.sensitive == true and notifyPoliceRisk(src, station, recipe, chance) or false

    if citizenid then
        NexusCraftingLog(citizenid, stationId, recipeId, recipe.output)
        if recipe.sensitive == true then
            NexusCraftingLogSensitive({
                citizenid = citizenid,
                source = src,
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
            TriggerClientEvent('nexus_progression:client:tick', src, 'crafting', recipe.xp or 0, recipe.reputation or 0)

            local criminalConfig = NexusCraftingConfig.criminalProgression or {}
            local shouldRewardCriminal = criminalConfig.enabled
                and (station.type == 'illegal' or recipe.category == 'illegal')
                and (not criminalConfig.sensitiveOnly or recipe.sensitive == true)

            if shouldRewardCriminal then
                local criminalXp = math.floor((tonumber(recipe.xp) or 0) * (tonumber(criminalConfig.xpMultiplier) or 0.25))
                local criminalRep = tonumber(criminalConfig.reputation) or 1
                exports.nexus_progression:addProgression(citizenid, 'criminal', criminalXp, criminalRep)
                TriggerClientEvent('nexus_progression:client:tick', src, 'criminal', criminalXp, criminalRep)

                if GetResourceState('nexus_territories') == 'started' then
                    exports.nexus_territories:addInfluenceAtCoords(src, station.coords, criminalRep, 'illegal_crafting')
                end
            end
        end
    end

    local territoryText = territoryContext and territoryContext.rivalInControlledZone and (' | territorio rival: %s'):format(territoryContext.owner) or ''
    notify(src, ('Has creado: %sx %s%s'):format(recipe.output.count or 1, recipe.label, territoryText), 'success')
end)

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
    if resource ~= GetCurrentResourceName() or not verticalSliceEnabled() then return end
    if GetResourceState('nexus_contracts') ~= 'started' then return end
    for src, session in pairs(craftSessions) do
        releaseOrBlock(src, session, 'crafting_resource_stopped')
    end
    for src, session in pairs(fulfillingSessions) do
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
        return
    end
    print('[nexus_crafting] crafting modular cargado')
end)
