local activeContracts = {}
local sourceCitizenIds = {}
local schemaReady = false
local craftingSchemaReady = false
local craftingSchemaState = 'pending'
local craftingSchemaReason = 'schema_validation_pending'

local function setCraftingSchemaState(state, reason)
    craftingSchemaState = state
    craftingSchemaReason = reason
    craftingSchemaReady = state == 'ready'
    TriggerEvent('nexus_contracts:server:craftingSchemaChanged')
end

local function physicalSubject(stage, lotId)
    return ('nexus_contracts:%s:%s'):format(tostring(stage), tostring(lotId))
end

local function beginPhysicalAction(source, stage, lotId, duration)
    if GetResourceState('nexus_bridge') ~= 'started' then return nil, 'security_unavailable' end
    return exports.nexus_bridge:beginTimedAction(source, 'physical', physicalSubject(stage, lotId), duration)
end

local function consumePhysicalAction(source, stage, lotId, token)
    if GetResourceState('nexus_bridge') ~= 'started' then return false, 'security_unavailable' end
    return exports.nexus_bridge:consumeTimedAction(source, 'physical', physicalSubject(stage, lotId), token)
end

local function cancelPhysicalAction(source, token)
    if GetResourceState('nexus_bridge') ~= 'started' then return false end
    return exports.nexus_bridge:cancelTimedAction(source, 'physical', token)
end

local function getPlayer(source)
    source = tonumber(source)
    if not source or source <= 0 or GetResourceState('qbx_core') ~= 'started' then return nil end
    return exports.qbx_core:GetPlayer(source)
end

local function getCitizenId(source)
    local player = getPlayer(source)
    local citizenid = player and player.PlayerData and player.PlayerData.citizenid
    if citizenid then sourceCitizenIds[source] = citizenid end
    return citizenid
end

local function notify(source, description, notifyType)
    TriggerClientEvent('ox_lib:notify', source, {
        title = 'Suministros',
        description = description,
        type = notifyType or 'inform',
    })
end

local function notifyPendingIncident(source)
    notify(source, 'Incidencia pendiente. El lote queda bloqueado para revision.', 'error')
end

local function rateLimit(source)
    source = tonumber(source)
    if not source or source <= 0 then return false end
    if GetResourceState('nexus_bridge') ~= 'started' then return false end
    return exports.nexus_bridge:rateLimit(source, NexusContractsConfig.rateLimitBucket or 'default')
end

local function isNear(source, coords, distance)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return false end
    return #(GetEntityCoords(ped) - coords) <= (distance or NexusContractsConfig.interactDistance)
end

local function supplyConfig()
    return NexusContractsConfig.supply
end

local function mechanicCraftingConfig()
    return NexusContractsConfig.mechanicCrafting
end

local function contractConfig()
    return NexusContractsConfig.contracts.civil_mechanic_supply
end

local function packageItem()
    return NexusContractsConfig.packageItem or 'nexus_contract_package'
end

local function packageMetadataType()
    return 'mechanic_supply'
end

local function generateLotId(citizenid)
    local suffix = tostring(citizenid):gsub('[^%w]', ''):sub(-8)
    return ('NXS-%d-%06d-%s'):format(os.time(), math.random(0, 999999), suffix)
end

local function metadataForLot(lot)
    return {
        lotId = lot.lot_id,
        ownerCitizenId = lot.citizenid,
        destination = lot.destination,
        expiresAt = tonumber(lot.expires_at),
        type = packageMetadataType(),
    }
end

local function metadataMatchesLot(metadata, lot)
    if type(metadata) ~= 'table' then return false end
    return metadata.lotId == lot.lot_id
        and metadata.ownerCitizenId == lot.citizenid
        and metadata.destination == lot.destination
        and tonumber(metadata.expiresAt) == tonumber(lot.expires_at)
        and metadata.type == packageMetadataType()
end

local function persistedContents(lot)
    local ok, contents = pcall(json.decode, lot.contents or '')
    if not ok or type(contents) ~= 'table' then return nil end
    if tonumber(contents.metalscrap) ~= 3
        or tonumber(contents.iron) ~= 2
        or tonumber(contents.plastic) ~= 2 then
        return nil
    end
    return {
        metalscrap = 3,
        iron = 2,
        plastic = 2,
    }
end

local function getExactPackageSlot(source, lot)
    if GetResourceState('ox_inventory') ~= 'started' then return nil end
    local slots = exports.ox_inventory:GetSlotsWithItem(source, packageItem()) or {}
    for i = 1, #slots do
        local slot = slots[i]
        if metadataMatchesLot(slot.metadata, lot)
            and (not lot.package_slot or tonumber(slot.slot) == tonumber(lot.package_slot)) then
            return slot
        end
    end
end

local function getSupplyPackageSlots(source)
    if GetResourceState('ox_inventory') ~= 'started' then return {} end
    return exports.ox_inventory:GetSlotsWithItem(source, packageItem()) or {}
end

local function getRecoverablePackageSlot(source, lot, supplySlots)
    if not lot or lot.state ~= 'reserved' then return nil end
    if lot.contract_type ~= supplyConfig().type or lot.destination ~= contractConfig().destination then return nil end
    if os.time() > tonumber(lot.expires_at) then return nil end

    supplySlots = supplySlots or getSupplyPackageSlots(source)
    if #supplySlots ~= 1 then return nil end

    local slot = getExactPackageSlot(source, lot)
    if not slot or os.time() > tonumber(slot.metadata.expiresAt) then return nil end
    return slot
end

local function getAddedItemSlot(response)
    if type(response) ~= 'table' then return nil end

    if tonumber(response.slot) then
        return tonumber(response.slot)
    end

    local first = response[1]
    if type(first) ~= 'table' then return nil end

    if type(first.item) == 'table' and tonumber(first.item.slot) then
        return tonumber(first.item.slot)
    end

    return tonumber(first.slot)
end

local terminalPackageStates = {
    cancelled = true,
    expired = true,
    lost = true,
    delivered = true,
    consumed = true,
}

local function cleanupTerminalPackages(source)
    local slots = getSupplyPackageSlots(source)
    local ambiguous = false
    for i = 1, #slots do
        local slot = slots[i]
        local metadata = slot.metadata or {}
        local lot = metadata.lotId and NexusContractsGetLot(metadata.lotId) or nil
        if lot and terminalPackageStates[lot.state] and metadataMatchesLot(metadata, lot) then
            exports.ox_inventory:RemoveItem(
                source,
                packageItem(),
                1,
                slot.metadata,
                slot.slot,
                true,
                true
            )
        elseif lot and lot.state == 'ambiguous' then
            ambiguous = true
        end
    end
    return ambiguous
end

local function removeExactPackage(source, lot)
    local slot = getExactPackageSlot(source, lot)
    if not slot then return false end
    local removed = exports.ox_inventory:RemoveItem(
        source,
        packageItem(),
        1,
        slot.metadata,
        slot.slot,
        false,
        true
    )
    return removed == true
end

local function stageForState(state)
    if state == 'reserved' then return 'pickup' end
    if state == 'picked_up' then return 'dropoff' end
end

local function runtimeContract(lot)
    if not lot then return nil end
    local stage = stageForState(lot.state)
    if not stage then return nil end
    return {
        id = supplyConfig().type,
        lotId = lot.lot_id,
        citizenid = lot.citizenid,
        stage = stage,
        expiresAt = tonumber(lot.expires_at),
    }
end

local function syncActiveContract(source)
    local citizenid = getCitizenId(source)
    if not citizenid or not schemaReady then return nil end
    local lot = NexusContractsGetActiveLot(citizenid)
    local active = runtimeContract(lot)
    activeContracts[source] = active
    return active, lot
end

local function clearClientActive(source)
    activeContracts[source] = nil
    cancelPhysicalAction(source)
    TriggerClientEvent('nexus_contracts:client:clearActive', source)
end

local function sendClientActive(source, active)
    if active then
        TriggerClientEvent('nexus_contracts:client:setActive', source, {
            id = active.id,
            lotId = active.lotId,
            stage = active.stage,
            expiresAt = active.expiresAt,
        }, contractConfig())
    else
        TriggerClientEvent('nexus_contracts:client:clearActive', source)
    end
end

local function buildContractList(source, blocked)
    local snapshot = craftingSchemaReady and NexusContractsGetMechanicStockSnapshot(supplyConfig().stockKey) or nil
    local stock = snapshot and snapshot.total or NexusContractsGetStock(supplyConfig().stockKey)
    local capacity = NexusContractsGetReservedCapacity()
    return {
        {
            id = supplyConfig().type,
            type = supplyConfig().type,
            label = contractConfig().label,
            description = contractConfig().description,
            contents = supplyConfig().contents,
            stock = stock,
            capacity = capacity,
            maxStock = supplyConfig().maxLots,
            unlocked = not blocked and capacity < supplyConfig().maxLots,
        },
    }
end

local function isCraftingCaller()
    return GetInvokingResource() == 'nexus_crafting'
end

local function mechanicAuthorization(source, stationId, recipeId, requireDistance)
    if not craftingSchemaReady then return nil, nil, 'schema_not_ready' end
    source = tonumber(source)
    if not source or source <= 0 then return nil, nil, 'invalid_source' end

    local config = mechanicCraftingConfig()
    if stationId ~= nil and tostring(stationId) ~= config.stationId then return nil, nil, 'invalid_station' end
    if recipeId ~= nil and tostring(recipeId) ~= config.recipeId then return nil, nil, 'invalid_recipe' end

    local player = getPlayer(source)
    local playerData = player and player.PlayerData
    local job = playerData and playerData.job
    local citizenid = playerData and playerData.citizenid
    local grade = job and job.grade
    grade = type(grade) == 'table' and grade.level or grade

    if not citizenid or not job or job.name ~= config.job then return nil, nil, 'no_access' end
    if job.onduty ~= true then return nil, nil, 'not_on_duty' end
    if (tonumber(grade) or 0) < (tonumber(config.minimumGrade) or 0) then return nil, nil, 'grade_locked' end
    if requireDistance ~= false and not isNear(source, config.coords, config.maxDistance) then
        return nil, nil, 'too_far'
    end

    sourceCitizenIds[source] = citizenid
    return player, citizenid
end

local function generateCraftReservationId(citizenid)
    local suffix = tostring(citizenid):gsub('[^%w]', ''):sub(-8)
    return ('NXC-%d-%06d-%s'):format(os.time(), math.random(0, 999999), suffix)
end

local function validateCraftReservation(source, reservationId, expectedState, requireDistance)
    local _, citizenid, reason = mechanicAuthorization(source, nil, nil, requireDistance)
    if not citizenid then return nil, reason end
    if type(reservationId) ~= 'string' or reservationId == '' then return nil, 'invalid_reservation' end

    local reservation = NexusContractsGetMechanicCraftReservation(reservationId)
    local config = mechanicCraftingConfig()
    if not reservation or reservation.citizenid ~= citizenid then return nil, 'invalid_owner' end
    if reservation.station_id ~= config.stationId
        or reservation.recipe_id ~= config.recipeId
        or reservation.output_item ~= config.outputItem
        or tonumber(reservation.output_count) ~= config.outputCount then
        return nil, 'invalid_scope'
    end
    if expectedState and reservation.state ~= expectedState then return nil, 'invalid_state' end
    if os.time() > tonumber(reservation.expires_at) then return nil, 'expired' end
    return reservation
end

local function validateCraftReservationOwner(source, reservationId)
    source = tonumber(source)
    local citizenid = source and getCitizenId(source) or nil
    if not citizenid or type(reservationId) ~= 'string' or reservationId == '' then
        return nil, 'invalid_owner'
    end

    local reservation = NexusContractsGetMechanicCraftReservation(reservationId)
    local config = mechanicCraftingConfig()
    if not reservation or reservation.citizenid ~= citizenid then return nil, 'invalid_owner' end
    if reservation.station_id ~= config.stationId
        or reservation.recipe_id ~= config.recipeId
        or reservation.output_item ~= config.outputItem
        or tonumber(reservation.output_count) ~= config.outputCount then
        return nil, 'invalid_scope'
    end
    return reservation
end

exports('isMechanicCraftingReady', function()
    if not isCraftingCaller() then return false, 'unauthorized_resource' end
    if not craftingSchemaReady then
        return false, craftingSchemaReason or 'schema_not_ready', craftingSchemaState
    end
    return true, nil, 'ready'
end)

exports('isMechanicCraftQuarantined', function(citizenid)
    if not isCraftingCaller() then return nil end
    if type(citizenid) ~= 'string' or citizenid == '' then return nil end
    local active = NexusContractsGetActiveMechanicCraft(citizenid)
    if not active or active.state ~= 'ambiguous' then return nil end
    return {
        reservationId = active.reservation_id,
        incidentReason = active.incident_reason,
        since = active.finalized_at,
    }
end)

exports('getMechanicStockSnapshot', function(source)
    if not isCraftingCaller() then return nil, 'unauthorized_resource' end
    local _, _, reason = mechanicAuthorization(source, nil, nil, true)
    if reason then return nil, reason end
    local snapshot = NexusContractsGetMechanicStockSnapshot(mechanicCraftingConfig().stockKey)
    if not snapshot then return nil, 'database_error' end
    return snapshot
end)

exports('reserveMechanicCraft', function(source, stationId, recipeId)
    if not isCraftingCaller() then return nil, 'unauthorized_resource' end
    local _, citizenid, reason = mechanicAuthorization(source, stationId, recipeId, true)
    if not citizenid then return nil, reason end

    local config = mechanicCraftingConfig()
    local reservationId = generateCraftReservationId(citizenid)
    local expiresAt = os.time() + math.max(30, tonumber(config.reservationSeconds) or 90)
    local reservation, reserveReason = NexusContractsReserveMechanicCraft({
        reservationId = reservationId,
        citizenid = citizenid,
        stationId = config.stationId,
        recipeId = config.recipeId,
        outputItem = config.outputItem,
        outputCount = config.outputCount,
        stockKey = config.stockKey,
        contents = config.contents,
        expiresAt = expiresAt,
    })
    if not reservation then return nil, reserveReason end
    return {
        reservationId = reservation.reservation_id,
        lotId = reservation.lot_id,
        expiresAt = tonumber(reservation.expires_at),
    }
end)

exports('getMechanicCraftReservation', function(source, reservationId)
    if not isCraftingCaller() then return nil, 'unauthorized_resource' end
    local reservation, reason = validateCraftReservation(source, reservationId, nil, false)
    if not reservation then return nil, reason end
    return reservation
end)

exports('beginMechanicCraft', function(source, reservationId)
    if not isCraftingCaller() then return false, 'unauthorized_resource' end
    local reservation, reason = validateCraftReservation(source, reservationId, 'reserved', true)
    if not reservation then return false, reason end
    if not NexusContractsBeginMechanicCraft(reservationId, reservation.citizenid) then
        return false, 'transition_failed'
    end
    return true, {
        lotId = reservation.lot_id,
        citizenid = reservation.citizenid,
    }
end)

exports('completeMechanicCraft', function(source, reservationId)
    if not isCraftingCaller() then return false, 'unauthorized_resource' end
    local reservation, reason = validateCraftReservation(source, reservationId, 'fulfilling', true)
    if not reservation then return false, reason end
    return NexusContractsCompleteMechanicCraft(reservationId, reservation.citizenid)
end)

exports('releaseMechanicCraft', function(source, reservationId, reason)
    if not isCraftingCaller() then return false, 'unauthorized_resource' end
    local reservation, validationReason = validateCraftReservationOwner(source, reservationId)
    if not reservation then return false, validationReason end

    local releaseReason = tostring(reason or 'cancelled'):sub(1, 120)
    if reservation.state == 'reserved' then
        local target = releaseReason == 'ttl_expired' and 'expired' or 'cancelled'
        return NexusContractsReleaseMechanicCraft(
            reservationId,
            reservation.citizenid,
            'reserved',
            target,
            releaseReason
        )
    end
    if reservation.state == 'fulfilling' then
        return NexusContractsReleaseMechanicCraft(
            reservationId,
            reservation.citizenid,
            'fulfilling',
            'failed',
            releaseReason
        )
    end
    if reservation.state == 'cancelled'
        or reservation.state == 'expired'
        or reservation.state == 'failed' then
        return true, 'already_released'
    end
    return false, 'invalid_state'
end)

exports('markMechanicCraftAmbiguous', function(source, reservationId, reason)
    if not isCraftingCaller() then return false, 'unauthorized_resource' end
    local reservation, validationReason = validateCraftReservationOwner(source, reservationId)
    if not reservation then return false, validationReason end
    return NexusContractsMarkMechanicCraftAmbiguous(
        reservationId,
        reservation.citizenid,
        tostring(reason or 'inventory_sql_uncertain'):sub(1, 120)
    )
end)

exports('queueMechanicCraftAmbiguousFromCraftingStop', function(reservationId, citizenid, reason)
    if GetInvokingResource() ~= 'nexus_crafting' then
        return false, 'unauthorized_resource'
    end

    -- Validacion de tipo/vacio ANTES de cualquier tostring(): tostring(nil)
    -- produce "nil" (una cadena no vacia), asi que convertir primero
    -- enmascararia un argumento ausente en vez de rechazarlo.
    if type(reservationId) ~= 'string' or reservationId == '' then
        return false, 'invalid_reservation_id'
    end
    if type(citizenid) ~= 'string' or citizenid == '' then
        return false, 'invalid_citizenid'
    end

    -- Copia a valores primitivos ya validados, sin conservar ninguna
    -- referencia al entorno de nexus_crafting dentro del hilo nuevo.
    local reservationIdCopy = reservationId
    local citizenidCopy = citizenid
    local reasonCopy = tostring(reason or 'unknown'):sub(1, 120)

    CreateThread(function()
        local blocked = NexusContractsMarkMechanicCraftAmbiguous(reservationIdCopy, citizenidCopy, reasonCopy)
        if blocked ~= true then
            print(('^1[nexus_contracts] ADVERTENCIA: no se pudo confirmar ambiguous para reservation=%s citizen=%s reason=%s^7')
                :format(reservationIdCopy, citizenidCopy, reasonCopy))
        end
    end)

    return true
end)

local function logRejectedDelivery(citizenid, lot, reason)
    if lot then
        NexusContractsLogEvent(lot.lot_id, citizenid, 'double_delivery_rejected', {
            reason = reason,
            state = lot.state,
        })
    end
end

local function blockInvalidDelivery(source, citizenid, lot, reason)
    local blockable = lot and (
        lot.state == 'reserved'
        or lot.state == 'picked_up'
        or lot.state == 'delivery_pending'
    )
    if blockable then
        if not NexusContractsMarkAmbiguous(lot.lot_id, citizenid, reason) then
            print(('[nexus_contracts] CRITICAL: invalid delivery lock failed lot=%s reason=%s'):format(
                tostring(lot.lot_id),
                tostring(reason)
            ))
        end
        notifyPendingIncident(source)
    end
    logRejectedDelivery(citizenid, lot, reason)
    return blockable
end

lib.callback.register('nexus_contracts:server:getContracts', function(source)
    if not schemaReady then return false, 'schema_not_ready' end
    if not rateLimit(source) then return false, 'rate_limited' end

    local active, lot = syncActiveContract(source)
    if active and lot and os.time() > tonumber(lot.expires_at) then
        local finalized = false
        if lot.state == 'reserved' then
            finalized = NexusContractsExpireReserved(lot.lot_id, lot.citizenid)
        elseif lot.state == 'picked_up' then
            finalized = NexusContractsLosePickedUp(lot.lot_id, lot.citizenid, 'expired')
        end
        if finalized then
            clearClientActive(source)
            active = nil
            lot = nil
        else
            notifyPendingIncident(source)
        end
    end

    if lot and lot.state == 'ambiguous' then
        notifyPendingIncident(source)
    elseif not active then
        local ambiguous = cleanupTerminalPackages(source)
        if ambiguous then
            notifyPendingIncident(source)
        elseif #getSupplyPackageSlots(source) > 0 then
            notify(source, 'Tienes un lote no valido. No puede entregarse y requiere revision.', 'error')
        end
    end

    return true, buildContractList(source, lot ~= nil and active == nil), active
end)

lib.callback.register('nexus_contracts:server:prepareAction', function(source, requestedStage)
    if not schemaReady then return false, 'schema_not_ready' end
    if not rateLimit(source) then return false, 'rate_limited' end

    local active = activeContracts[source] or syncActiveContract(source)
    local stage = tostring(requestedStage or '')
    if not active or active.stage ~= stage or (stage ~= 'pickup' and stage ~= 'dropoff') then
        return false, 'invalid_stage'
    end

    local lot = NexusContractsGetLot(active.lotId)
    if not lot or lot.citizenid ~= getCitizenId(source) then return false, 'invalid_owner' end
    if lot.state == 'ambiguous' then
        notifyPendingIncident(source)
        return false, 'incident_pending'
    end
    if stageForState(lot.state) ~= stage then return false, 'invalid_state' end
    if os.time() > tonumber(lot.expires_at) then return false, 'expired' end

    local contract = contractConfig()
    local coords = stage == 'pickup' and contract.pickup or contract.dropoff
    if not isNear(source, coords, 5.0) then return false, 'too_far' end
    if stage == 'pickup' then
        local supplySlots = getSupplyPackageSlots(source)
        if #supplySlots > 0 then
            if not getRecoverablePackageSlot(source, lot, supplySlots) then
                return false, 'already_carrying'
            end
        elseif not exports.ox_inventory:CanCarryItem(source, packageItem(), 1) then
            return false, 'no_space'
        end
    end
    if stage == 'dropoff' and not getExactPackageSlot(source, lot) then return false, 'missing_package' end

    local duration = tonumber((NexusContractsConfig.actionDurations or {})[stage])
        or (stage == 'pickup' and 4500 or 5500)
    local token, reason, normalizedDuration = beginPhysicalAction(source, stage, lot.lot_id, duration)
    if not token then return false, reason == 'busy' and 'physical_busy' or reason end

    local scenes = NexusContractsConfig.sceneCore or {}
    return true, {
        token = token,
        duration = normalizedDuration or duration,
        sceneId = scenes[stage] or (stage == 'pickup' and 'package_pickup' or 'package_delivery'),
        label = stage == 'pickup' and 'Cargando lote...' or 'Descargando lote...',
        coords = { x = coords.x, y = coords.y, z = coords.z },
    }
end)

exports('getDashboardContracts', function(source)
    source = tonumber(source)
    if not source or source <= 0 or not schemaReady then return { contracts = {}, active = nil } end
    local active = activeContracts[source] or syncActiveContract(source)
    return {
        contracts = buildContractList(source, NexusContractsGetActiveLot(getCitizenId(source)) ~= nil and active == nil),
        active = active and {
            id = active.id,
            lotId = active.lotId,
            stage = active.stage,
            expiresAt = active.expiresAt,
        } or nil,
    }
end)

exports('getDutyboardSnapshot', function(source)
    source = tonumber(source)
    if not source or source <= 0 then return nil end
    local citizenid = getCitizenId(source)
    if not citizenid then return nil end

    local lot = schemaReady and NexusContractsGetActiveLot(citizenid) or nil
    local craft = craftingSchemaReady and NexusContractsGetActiveMechanicCraft(citizenid) or nil

    return {
        lot = lot and { id = lot.id, state = lot.state } or nil,
        craft = craft and {
            reservationId = craft.reservation_id,
            state = craft.state,
            incidentReason = craft.incident_reason,
        } or nil,
    }
end)

RegisterNetEvent('nexus_contracts:server:start', function(contractId)
    local src = source
    if not schemaReady or not rateLimit(src) then return end
    if tostring(contractId or '') ~= supplyConfig().type then return end

    local citizenid = getCitizenId(src)
    local player = getPlayer(src)
    if not citizenid or not player then return notify(src, 'No se pudo validar tu personaje.', 'error') end
    local supplier = NexusContractsConfig.contacts.civil_supplier
    if not supplier or not isNear(src, supplier.coords, 5.0) then
        return notify(src, 'Debes aceptar el transporte junto al proveedor.', 'error')
    end

    local existing = NexusContractsGetActiveLot(citizenid)
    if existing then
        if existing.state == 'ambiguous' then return notifyPendingIncident(src) end
        activeContracts[src] = runtimeContract(existing)
        sendClientActive(src, activeContracts[src])
        return notify(src, 'Ya tienes un lote activo.', 'error')
    end
    if #getSupplyPackageSlots(src) > 0 then
        return notify(src, 'Ya llevas un lote de suministros.', 'error')
    end

    local lotId = generateLotId(citizenid)
    local expiresAt = os.time() + (contractConfig().durationSeconds or 1200)
    local created, reason = NexusContractsCreateSupplyLot({
        lotId = lotId,
        contractType = supplyConfig().type,
        citizenid = citizenid,
        ownerName = GetPlayerName(src),
        destination = contractConfig().destination,
        contents = supplyConfig().contents,
        expiresAt = expiresAt,
    })

    if not created then
        if reason == 'audit_log_failed' then return notifyPendingIncident(src) end
        local message = reason == 'capacity_or_active_lot'
            and 'El taller no tiene capacidad para otro lote.'
            or 'No se pudo reservar una plaza de entrada.'
        return notify(src, message, 'error')
    end

    activeContracts[src] = {
        id = supplyConfig().type,
        lotId = lotId,
        citizenid = citizenid,
        stage = 'pickup',
        expiresAt = expiresAt,
    }
    sendClientActive(src, activeContracts[src])
    notify(src, 'Plaza reservada. Recoge el lote en el proveedor.', 'success')
end)

RegisterNetEvent('nexus_contracts:server:pickup', function(actionToken)
    local src = source
    if not schemaReady or not rateLimit(src) then return end

    local active = activeContracts[src] or syncActiveContract(src)
    if not active or active.stage ~= 'pickup' then return end
    local lot = NexusContractsGetLot(active.lotId)
    local citizenid = getCitizenId(src)
    if not lot or not citizenid or lot.citizenid ~= citizenid then return end
    if lot.state == 'ambiguous' then return notifyPendingIncident(src) end
    if lot.state ~= 'reserved' then return end

    local actionOk, actionReason = consumePhysicalAction(src, 'pickup', lot.lot_id, actionToken)
    if not actionOk then
        print(('[nexus_contracts] blocked pickup source=%s lot=%s reason=%s'):format(
            src, lot.lot_id, tostring(actionReason)
        ))
        return notify(src, 'La recogida fisica no es valida.', 'error')
    end
    if os.time() > tonumber(lot.expires_at) then
        if NexusContractsExpireReserved(lot.lot_id, citizenid) then
            clearClientActive(src)
            return notify(src, 'La reserva ha caducado.', 'error')
        end
        return notifyPendingIncident(src)
    end
    if not isNear(src, contractConfig().pickup, 5.0) then return notify(src, 'No estas en el proveedor.', 'error') end
    local packageSlot
    local supplySlots = getSupplyPackageSlots(src)
    if #supplySlots > 0 then
        local exactSlot = getRecoverablePackageSlot(src, lot, supplySlots)
        if not exactSlot then
            return notify(src, 'Ya llevas otro lote.', 'error')
        end
        packageSlot = tonumber(exactSlot.slot)
    else
        if not exports.ox_inventory:CanCarryItem(src, packageItem(), 1) then
            return notify(src, 'No tienes espacio para el lote.', 'error')
        end

        local added, response = exports.ox_inventory:AddItem(src, packageItem(), 1, metadataForLot(lot))
        packageSlot = added and getAddedItemSlot(response) or nil
        if not added then
            return notify(src, 'No se pudo cargar el lote.', 'error')
        end
        if not packageSlot then
            if not NexusContractsMarkAmbiguous(lot.lot_id, citizenid, 'inventory_added_slot_unresolved') then
                print(('[nexus_contracts] CRITICAL: pickup slot incident lock failed lot=%s'):format(lot.lot_id))
            end
            return notifyPendingIncident(src)
        end
    end

    if not NexusContractsMarkPickedUp(lot.lot_id, citizenid, packageSlot) then
        if not NexusContractsMarkAmbiguous(lot.lot_id, citizenid, 'inventory_added_state_not_persisted') then
            print(('[nexus_contracts] CRITICAL: pickup incident lock failed lot=%s'):format(lot.lot_id))
        end
        return notifyPendingIncident(src)
    end

    active.stage = 'dropoff'
    sendClientActive(src, active)
    notify(src, 'Lote cargado. Llevalo al taller mecanico.', 'inform')
end)

RegisterNetEvent('nexus_contracts:server:deliver', function(actionToken)
    local src = source
    if not schemaReady or not rateLimit(src) then return end

    local citizenid = getCitizenId(src)
    if not citizenid then return end
    local active = activeContracts[src] or syncActiveContract(src)
    if not active or active.stage ~= 'dropoff' then
        local latest = NexusContractsGetActiveLot(citizenid) or NexusContractsGetLatestLot(citizenid)
        if latest and latest.state == 'ambiguous' then return notifyPendingIncident(src) end
        logRejectedDelivery(citizenid, latest, 'no_active_delivery')
        return
    end

    local lot = NexusContractsGetLot(active.lotId)
    if not lot or lot.citizenid ~= citizenid then return end
    if lot.state ~= 'picked_up' then
        blockInvalidDelivery(src, citizenid, lot, 'invalid_delivery_state')
        return
    end

    local actionOk, actionReason = consumePhysicalAction(src, 'dropoff', lot.lot_id, actionToken)
    if not actionOk then
        print(('[nexus_contracts] blocked delivery source=%s lot=%s reason=%s'):format(
            src, lot.lot_id, tostring(actionReason)
        ))
        return notify(src, 'La entrega fisica no es valida.', 'error')
    end
    if os.time() > tonumber(lot.expires_at) then
        if NexusContractsLosePickedUp(lot.lot_id, citizenid, 'expired') then
            clearClientActive(src)
            return notify(src, 'El lote ha caducado y queda marcado como perdido.', 'error')
        end
        return notifyPendingIncident(src)
    end
    if not isNear(src, contractConfig().dropoff, 5.0) then return notify(src, 'No estas en el taller.', 'error') end
    if not getExactPackageSlot(src, lot) then return notify(src, 'No llevas el lote exacto asignado.', 'error') end
    local contents = persistedContents(lot)
    if not contents then
        if not NexusContractsMarkAmbiguous(lot.lot_id, citizenid, 'invalid_persisted_contents') then
            print(('[nexus_contracts] CRITICAL: invalid contents lock failed lot=%s'):format(lot.lot_id))
        end
        return notifyPendingIncident(src)
    end

    if not NexusContractsBeginDelivery(lot.lot_id, citizenid) then
        local currentLot = NexusContractsGetLot(lot.lot_id) or lot
        if blockInvalidDelivery(src, citizenid, currentLot, 'delivery_transition_rejected') then return end
        return notify(src, 'Esta entrega ya fue procesada o esta bloqueada.', 'error')
    end

    lot.state = 'delivery_pending'
    if not removeExactPackage(src, lot) then
        if not NexusContractsMarkAmbiguous(lot.lot_id, citizenid, 'delivery_pending_inventory_remove_failed') then
            print(('[nexus_contracts] CRITICAL: inventory incident lock failed lot=%s'):format(lot.lot_id))
        end
        return notifyPendingIncident(src)
    end

    if not NexusContractsCompleteDelivery(
        lot.lot_id,
        citizenid,
        supplyConfig().stockKey,
        contents
    ) then
        if not NexusContractsMarkAmbiguous(lot.lot_id, citizenid, 'inventory_removed_stock_commit_failed') then
            print(('[nexus_contracts] CRITICAL: delivery incident lock failed lot=%s'):format(lot.lot_id))
        end
        return notifyPendingIncident(src)
    end

    clearClientActive(src)
    local stock = NexusContractsGetStock(supplyConfig().stockKey)
    notify(src, ('Lote entregado. Stock del taller: %s/%s.'):format(stock, supplyConfig().maxLots), 'success')
end)

RegisterNetEvent('nexus_contracts:server:cancelPreparedAction', function(actionToken)
    cancelPhysicalAction(source, actionToken)
end)

RegisterNetEvent('nexus_contracts:server:cancel', function()
    local src = source
    if not schemaReady or not rateLimit(src) then return end
    local active, lot = syncActiveContract(src)
    if lot and lot.state == 'ambiguous' then return notifyPendingIncident(src) end
    if not active or not lot then return end
    if lot.state ~= 'reserved' then
        return notify(src, 'Un lote recogido ya no puede cancelarse.', 'error')
    end

    if NexusContractsCancelReserved(lot.lot_id, lot.citizenid, 'player_cancelled') then
        clearClientActive(src)
        notify(src, 'Reserva cancelada. La plaza del taller queda libre.', 'inform')
    else
        notifyPendingIncident(src)
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    if not schemaReady then return end
    local active = activeContracts[src]
    local citizenid = active and active.citizenid or sourceCitizenIds[src] or getCitizenId(src)
    local lot = citizenid and NexusContractsGetActiveLot(citizenid) or nil
    if lot and lot.state == 'picked_up' then
        if not NexusContractsLosePickedUp(lot.lot_id, citizenid, 'player_disconnected') then
            print(('[nexus_contracts] pending disconnect incident lot=%s'):format(lot.lot_id))
        end
    end
    if craftingSchemaReady and citizenid then
        local craft = NexusContractsGetActiveMechanicCraft(citizenid)
        if craft and craft.state == 'reserved' then
            if not NexusContractsReleaseMechanicCraft(
                craft.reservation_id,
                citizenid,
                'reserved',
                'cancelled',
                'player_disconnected'
            ) then
                NexusContractsMarkMechanicCraftAmbiguous(
                    craft.reservation_id,
                    citizenid,
                    'disconnect_release_failed'
                )
            end
        elseif craft and craft.state == 'fulfilling' then
            NexusContractsMarkMechanicCraftAmbiguous(
                craft.reservation_id,
                citizenid,
                'player_disconnected_while_fulfilling'
            )
        end
    end
    cancelPhysicalAction(src)
    activeContracts[src] = nil
    sourceCitizenIds[src] = nil
end)

CreateThread(function()
    while true do
        Wait(math.max(10, tonumber(NexusContractsConfig.expirySweepSeconds) or 30) * 1000)
        if schemaReady then
            local expired = NexusContractsGetExpiredLots(os.time())
            for i = 1, #expired do
                local lot = expired[i]
                local finalized = false
                if lot.state == 'reserved' then
                    finalized = NexusContractsExpireReserved(lot.lot_id, lot.citizenid)
                elseif lot.state == 'picked_up' then
                    finalized = NexusContractsLosePickedUp(lot.lot_id, lot.citizenid, 'expired')
                end
                for src, active in pairs(activeContracts) do
                    if active.lotId == lot.lot_id then
                        if finalized then
                            clearClientActive(src)
                        else
                            notifyPendingIncident(src)
                        end
                    end
                end
            end
        end
        if craftingSchemaReady then
            local expiredCrafts = NexusContractsGetExpiredMechanicCrafts(os.time())
            for i = 1, #expiredCrafts do
                local craft = expiredCrafts[i]
                if craft.state == 'reserved' then
                    if not NexusContractsReleaseMechanicCraft(
                        craft.reservation_id,
                        craft.citizenid,
                        'reserved',
                        'expired',
                        'ttl_expired'
                    ) then
                        NexusContractsMarkMechanicCraftAmbiguous(
                            craft.reservation_id,
                            craft.citizenid,
                            'ttl_release_failed'
                        )
                    end
                elseif craft.state == 'fulfilling' then
                    NexusContractsMarkMechanicCraftAmbiguous(
                        craft.reservation_id,
                        craft.citizenid,
                        'ttl_expired_while_fulfilling'
                    )
                end
            end
        end
    end
end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    setCraftingSchemaState('pending', 'schema_validation_pending')
    math.randomseed(os.time() + GetGameTimer())
    local schemaReason
    schemaReady, schemaReason = NexusContractsSchemaReady()
    if not schemaReady then
        setCraftingSchemaState('failed', ('migration_002_incomplete:%s'):format(
            tostring(schemaReason or 'unknown_schema_error')
        ))
        print(('^1[nexus_contracts] migration 002 incomplete (%s); civil supply flow is disabled.^7'):format(
            tostring(schemaReason or 'unknown_schema_error')
        ))
        return
    end
    local recovered = NexusContractsRecoverPendingDeliveries()
    if recovered > 0 then
        print(('[nexus_contracts] blocked %s pending deliveries for reconciliation'):format(recovered))
    end
    local craftingSchemaReason
    craftingSchemaReady, craftingSchemaReason = NexusContractsCraftingSchemaReady()
    if not craftingSchemaReady then
        setCraftingSchemaState('failed', ('migration_003_incomplete:%s'):format(
            tostring(craftingSchemaReason or 'unknown_schema_error')
        ))
        print(('^1[nexus_contracts] migration 003 incomplete (%s); mechanic crafting is disabled.^7'):format(
            tostring(craftingSchemaReason or 'unknown_schema_error')
        ))
    else
        local fulfilling = NexusContractsGetFulfillingMechanicCrafts()
        local recoveryReady = true
        for i = 1, #fulfilling do
            if not NexusContractsMarkMechanicCraftAmbiguous(
                fulfilling[i].reservation_id,
                fulfilling[i].citizenid,
                'resource_restarted_while_fulfilling'
            ) then
                recoveryReady = false
                print(('^1[nexus_contracts] failed to block fulfilling reservation=%s during startup^7'):format(
                    tostring(fulfilling[i].reservation_id)
                ))
            end
        end
        if #fulfilling > 0 then
            print(('[nexus_contracts] blocked %s fulfilling crafts for reconciliation'):format(#fulfilling))
        end
        if recoveryReady then
            setCraftingSchemaState('ready')
            print('[nexus_contracts] mechanic crafting schema ready')
        else
            setCraftingSchemaState('failed', 'fulfilling_recovery_failed')
            print('^1[nexus_contracts] mechanic crafting disabled: fulfilling recovery failed^7')
        end
    end
    CreateThread(function()
        Wait(500)
        local players = GetPlayers()
        for i = 1, #players do
            local src = tonumber(players[i])
            local active = src and syncActiveContract(src) or nil
            if src and active then sendClientActive(src, active) end
        end
    end)
    print('[nexus_contracts] suministro mecanico staging cargado')
end)
