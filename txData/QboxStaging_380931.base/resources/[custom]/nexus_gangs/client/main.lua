local function notify(description, notifyType)
    if GetResourceState('nexus_ui') == 'started' then
        exports.nexus_ui:notify({
            title = 'Bandas',
            description = description,
            type = notifyType or 'inform',
        })
        return
    end

    lib.notify({ title = 'Bandas', description = description, type = notifyType or 'inform' })
end

local cachedAssets = {
    loadedAt = 0,
    locations = {},
    vehicles = {},
    persistedVehicles = {},
}

local function toVec3(value)
    if not value then return nil end
    return vector3(value.x or value[1] or 0.0, value.y or value[2] or 0.0, value.z or value[3] or 0.0)
end

local function toVec4(value)
    if not value then return nil end
    return vector4(value.x or value[1] or 0.0, value.y or value[2] or 0.0, value.z or value[3] or 0.0, value.w or value[4] or 0.0)
end

local function reasonText(reason)
    local reasons = {
        rate_limited = 'Espera un momento.',
        inventory_offline = 'ox_inventory no esta iniciado.',
        no_gang = 'No perteneces a una banda.',
        no_rank = 'Tu rango no permite usar esto.',
        invalid_location = 'Esta safehouse no pertenece a tu banda.',
        invalid_point = 'Punto mal configurado.',
        too_far = 'Estas lejos del punto real de la safehouse.',
        stash_failed = 'No se pudo registrar el inventario.',
        invalid_vehicle = 'Vehiculo no configurado.',
        vehicle_rank = 'Tu rango no permite sacar ese vehiculo.',
        invalid_plate = 'Placa invalida.',
        not_gang_vehicle = 'Este vehiculo no pertenece al garaje de tu banda.',
        fleet_limit = 'La flota de este modelo esta completa. Guarda uno antes de sacar otro.',
        vehicle_state_changed = 'El estado del vehiculo cambio. Reabre el garaje.',
    }

    return reasons[reason] or tostring(reason or 'error')
end

local function distanceToLocationPoint(location, pointType)
    local point = pointType == 'garage' and toVec4(location.garage) or toVec3(location.stash)
    if not point then return nil end

    local coords = GetEntityCoords(PlayerPedId())
    local target = pointType == 'garage' and vector3(point.x, point.y, point.z) or point
    return #(coords - target)
end

local function isNearLocationPoint(location, pointType)
    local distance = distanceToLocationPoint(location, pointType)
    if not distance then return false, 9999.0 end
    return distance <= ((NexusGangsConfig.assets and NexusGangsConfig.assets.interactDistance or 2.0) + 1.5), distance
end

local function drawText3D(coords, text)
    SetDrawOrigin(coords.x, coords.y, coords.z, 0)
    SetTextScale(0.32, 0.32)
    SetTextFont(4)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

local function loadAssets(force)
    if not force and GetGameTimer() - cachedAssets.loadedAt < 5000 then return true end

    local ok, payload = lib.callback.await('nexus_gangs:server:getAssets', false)
    if not ok then
        notify(payload == 'rate_limited' and 'Espera un momento.' or 'No se pudieron cargar assets de banda.', 'error')
        return false
    end

    cachedAssets.loadedAt = GetGameTimer()
    cachedAssets.locations = payload.locations or {}
    cachedAssets.vehicles = payload.garageVehicles or {}
    cachedAssets.persistedVehicles = payload.persistedVehicles or {}
    return true
end

local function openGangStash(locationId)
    local ok, result = lib.callback.await('nexus_gangs:server:openStash', false, locationId)
    if not ok then
        notify(('No se pudo abrir inventario: %s'):format(reasonText(result)), 'error')
        return
    end

    exports.ox_inventory:openInventory('stash', result)
end

local function spawnGangVehicle(locationId, model)
    local ok, payload = lib.callback.await('nexus_gangs:server:requestVehicle', false, locationId, model)
    if not ok then
        notify(('No se pudo sacar vehiculo: %s'):format(reasonText(payload)), 'error')
        return
    end

    local spawn = toVec4(payload.spawn)
    local hash = joaat(payload.model)
    RequestModel(hash)

    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(0) end
    if not HasModelLoaded(hash) then
        notify('Modelo de vehiculo no cargado.', 'error')
        return
    end

    local vehicle = CreateVehicle(hash, spawn.x, spawn.y, spawn.z, spawn.w, true, false)
    SetVehicleNumberPlateText(vehicle, payload.plate or 'GANG')
    SetVehicleEngineOn(vehicle, true, true, false)
    SetPedIntoVehicle(PlayerPedId(), vehicle, -1)
    SetModelAsNoLongerNeeded(hash)
    notify(('Vehiculo entregado: %s'):format(payload.label or payload.model), 'success')
end

local function storeCurrentGangVehicle(locationId)
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then
        vehicle = GetVehiclePedIsIn(ped, true)
    end
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        notify('No estas en un vehiculo de banda.', 'error')
        return
    end

    local plate = GetVehicleNumberPlateText(vehicle)
    local model = GetEntityModel(vehicle)
    local ok, reason = lib.callback.await('nexus_gangs:server:storeVehicle', false, locationId, plate, model)
    if not ok then
        notify(('No se pudo guardar vehiculo: %s'):format(reasonText(reason)), 'error')
        return
    end

    DeleteEntity(vehicle)
    cachedAssets.loadedAt = 0
    notify('Vehiculo guardado en garaje de banda.', 'success')
end

local function openGarageMenu(location)
    local nearGarage, distance = isNearLocationPoint(location, 'garage')
    local options = {}

    if not nearGarage then
        options[#options + 1] = {
            title = 'Acercate al garaje real',
            description = ('Distancia actual %.1fm. Usa el marker de vehiculo en la safehouse.'):format(distance or 0.0),
            icon = 'location-crosshairs',
            disabled = true,
        }
    end

    options[#options + 1] = {
        title = 'Guardar vehiculo actual',
        description = nearGarage and 'Guarda el vehiculo de banda por placa.' or ('Acercate al garaje: %.1fm'):format(distance or 0.0),
        icon = 'square-parking',
        disabled = not location.canGarage or not nearGarage,
        onSelect = function()
            storeCurrentGangVehicle(location.id)
        end,
    }

    for i = 1, #cachedAssets.vehicles do
        local vehicle = cachedAssets.vehicles[i]
        local out = 0
        local stored = 0
        local maxPerModel = NexusGangsConfig.assets and NexusGangsConfig.assets.garage and NexusGangsConfig.assets.garage.maxPerModel or 2
        for j = 1, #(cachedAssets.persistedVehicles or {}) do
            local record = cachedAssets.persistedVehicles[j]
            if record.model == vehicle.model then
                if record.state == 'out' then out = out + 1 else stored = stored + 1 end
            end
        end
        options[#options + 1] = {
            title = vehicle.label or vehicle.model,
            description = ('Rango minimo %s | Guardados %s | Fuera %s | Limite %s'):format(vehicle.minRank or 0, stored, out, maxPerModel),
            icon = 'car',
            disabled = not location.canGarage or not nearGarage,
            onSelect = function()
                spawnGangVehicle(location.id, vehicle.model)
            end,
        }
    end

    if #(cachedAssets.persistedVehicles or {}) > 0 then
        options[#options + 1] = {
            title = 'Registro de vehiculos',
            description = 'Ultimas placas registradas en la banda.',
            icon = 'clipboard-list',
            disabled = true,
        }

        for i = 1, math.min(#cachedAssets.persistedVehicles, 6) do
            local record = cachedAssets.persistedVehicles[i]
            options[#options + 1] = {
                title = ('%s | %s'):format(record.plate or '-', record.label or record.model or '-'),
                description = ('Estado %s | Ultimo conductor %s'):format(record.state or 'stored', record.last_driver or '-'),
                icon = record.state == 'out' and 'car-side' or 'warehouse',
                disabled = true,
            }
        end
    end

    lib.registerContext({
        id = 'nexus_gang_garage',
        title = ('Garaje - %s'):format(location.label or 'Safehouse'),
        menu = 'nexus_gang_assets',
        options = options,
    })
    lib.showContext('nexus_gang_garage')
end

local function openGangAssetsMenu()
    if not loadAssets(true) then return end

    local options = {}
    if #cachedAssets.locations == 0 then
        options[#options + 1] = {
            title = 'Sin safehouse',
            description = 'Tu banda no tiene puntos configurados.',
            icon = 'house-lock',
            disabled = true,
        }
    end

    for i = 1, #cachedAssets.locations do
        local location = cachedAssets.locations[i]
        local nearStash, stashDistance = isNearLocationPoint(location, 'stash')
        local nearGarage, garageDistance = isNearLocationPoint(location, 'garage')
        options[#options + 1] = {
            title = location.label or location.id,
            description = ('Stash %.1fm | Garaje %.1fm'):format(stashDistance or 0.0, garageDistance or 0.0),
            icon = 'warehouse',
            onSelect = function()
                lib.registerContext({
                    id = 'nexus_gang_asset_location',
                    title = location.label or 'Safehouse',
                    menu = 'nexus_gang_assets',
                    options = {
                        {
                            title = 'Inventario de banda',
                            description = nearStash and 'Abrir stash compartido.' or ('Acercate al stash: %.1fm'):format(stashDistance or 0.0),
                            icon = 'box-archive',
                            disabled = not location.canStash or not nearStash,
                            onSelect = function()
                                openGangStash(location.id)
                            end,
                        },
                        {
                            title = 'Garaje de banda',
                            description = nearGarage and 'Sacar vehiculo operativo.' or ('Acercate al garaje: %.1fm'):format(garageDistance or 0.0),
                            icon = 'car',
                            disabled = not location.canGarage or not nearGarage,
                            onSelect = function()
                                openGarageMenu(location)
                            end,
                        },
                    },
                })
                lib.showContext('nexus_gang_asset_location')
            end,
        }
    end

    lib.registerContext({
        id = 'nexus_gang_assets',
        title = 'Assets de banda',
        options = options,
    })
    lib.showContext('nexus_gang_assets')
end

local function inputPlayerId(title)
    local input = lib.inputDialog(title, {
        { type = 'number', label = 'ID jugador', required = true, min = 1 },
    })
    if not input then return nil end
    return tonumber(input[1])
end

local function openSetRankDialog()
    local input = lib.inputDialog('Cambiar rango', {
        { type = 'number', label = 'ID jugador', required = true, min = 1 },
        { type = 'number', label = 'Nuevo rango', required = true, min = 0, max = 3 },
    })
    if not input then return end

    TriggerServerEvent('nexus_gangs:server:setMemberRank', tonumber(input[1]), tonumber(input[2]))
end

local function openKickDialog()
    local target = inputPlayerId('Expulsar miembro')
    if not target then return end

    local confirm = lib.alertDialog({
        header = 'Confirmar expulsion',
        content = ('Vas a expulsar al jugador ID %s de tu banda.'):format(target),
        centered = true,
        cancel = true,
    })

    if confirm ~= 'confirm' then return end
    TriggerServerEvent('nexus_gangs:server:kickMember', target)
end

local function openInviteDialog()
    local target = inputPlayerId('Invitar jugador')
    if not target then return end
    TriggerServerEvent('nexus_gangs:server:invite', target)
end

local function openGangManagementMenu()
    local ok, payload = lib.callback.await('nexus_gangs:server:getGang', false)
    if not ok then
        notify(payload == 'rate_limited' and 'Espera un momento.' or 'No se pudo cargar banda.', 'error')
        return
    end

    local gang = payload.gang or {}
    if gang.name == 'none' then
        notify('No perteneces a una banda.', 'error')
        return
    end

    local options = {
        {
            title = gang.label or gang.name,
            description = ('Rango %s | Rep %s'):format(gang.rankLabel or '-', gang.reputation or 0),
            icon = 'users',
            disabled = true,
        },
    }

    if gang.permissions and gang.permissions.invite then
        options[#options + 1] = {
            title = 'Invitar jugador',
            description = 'Invita a un jugador conectado por ID.',
            icon = 'user-plus',
            onSelect = openInviteDialog,
        }
    end

    if gang.permissions and gang.permissions.promote then
        options[#options + 1] = {
            title = 'Cambiar rango',
            description = 'Solo puedes modificar miembros con rango inferior.',
            icon = 'ranking-star',
            onSelect = openSetRankDialog,
        }
    end

    if gang.permissions and gang.permissions.kick then
        options[#options + 1] = {
            title = 'Expulsar miembro',
            description = 'Solo puedes expulsar miembros con rango inferior.',
            icon = 'user-minus',
            onSelect = openKickDialog,
        }
    end

    for i = 1, #(payload.members or {}) do
        local member = payload.members[i]
        options[#options + 1] = {
            title = member.citizenid,
            description = ('Rango %s | %s'):format(member.rank_level, member.rank_label or 'Miembro'),
            icon = 'id-card',
            disabled = true,
        }
    end

    lib.registerContext({
        id = 'nexus_gang_management',
        title = 'Gestion de banda',
        menu = 'nexus_gangs_menu',
        options = options,
    })
    lib.showContext('nexus_gang_management')
end

local function openGangMenu()
    local ok, payload = lib.callback.await('nexus_gangs:server:getGang', false)
    if not ok then
        notify(payload == 'rate_limited' and 'Espera un momento.' or 'No se pudo cargar banda.', 'error')
        return
    end

    local gang = payload.gang or {}
    local options = {
        {
            title = gang.label or 'Sin banda',
            description = gang.name == 'none'
                and 'No perteneces a una banda.'
                or ('Tag %s | Rango %s | Rep %s'):format(gang.tag or '-', gang.rankLabel or '-', gang.reputation or 0),
            icon = gang.name == 'none' and 'user' or 'users',
            disabled = true,
        },
    }

    if gang.name ~= 'none' then
        options[#options + 1] = {
            title = 'Assets de banda',
            description = 'Inventario, garaje y safehouses configuradas.',
            icon = 'warehouse',
            onSelect = openGangAssetsMenu,
        }

        options[#options + 1] = {
            title = 'Gestion de miembros',
            description = 'Invitar, cambiar rangos y expulsar segun permisos.',
            icon = 'user-gear',
            onSelect = openGangManagementMenu,
        }

        for i = 1, #(payload.members or {}) do
            local member = payload.members[i]
            options[#options + 1] = {
                title = member.citizenid,
                description = ('Rango %s | %s'):format(member.rank_level, member.rank_label or 'Miembro'),
                icon = 'id-card',
                disabled = true,
            }
        end

        if gang.permissions and gang.permissions.invite then
            options[#options + 1] = {
                title = 'Invitar jugador cercano',
                description = 'Usa /ganginvite ID por ahora.',
                icon = 'user-plus',
                disabled = true,
            }
        end

        options[#options + 1] = {
            title = 'Salir de banda',
            description = 'Lideres deben transferir liderazgo antes.',
            icon = 'right-from-bracket',
            onSelect = function()
                TriggerServerEvent('nexus_gangs:server:leave')
            end,
        }
    else
        options[#options + 1] = {
            title = 'Aceptar invitacion',
            description = 'Acepta una invitacion pendiente.',
            icon = 'check',
            onSelect = function()
                TriggerServerEvent('nexus_gangs:server:acceptInvite')
            end,
        }
    end

    lib.registerContext({
        id = 'nexus_gangs_menu',
        title = 'Bandas',
        options = options,
    })

    lib.showContext('nexus_gangs_menu')
end

exports('openGangs', openGangMenu)
exports('openGangAssets', openGangAssetsMenu)
exports('openGangManagement', openGangManagementMenu)

RegisterNetEvent('nexus_gangs:client:open', openGangMenu)
RegisterCommand(NexusGangsConfig.command, openGangMenu, false)
RegisterCommand(NexusGangsConfig.assets.command, openGangAssetsMenu, false)

RegisterCommand('gangassetsrefresh', function()
    cachedAssets.loadedAt = 0
    if loadAssets(true) then notify('Assets de banda recargados.', 'success') end
end, false)

RegisterCommand('ganginvite', function(_, args)
    local target = tonumber(args[1])
    if not target then
        notify('Uso: /ganginvite id', 'error')
        return
    end

    TriggerServerEvent('nexus_gangs:server:invite', target)
end, false)

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Wait(500)
    loadAssets(true)
    print('[nexus_gangs] bandas cliente cargado')
end)

CreateThread(function()
    while true do
        local sleep = 1000
        local assets = NexusGangsConfig.assets

        if assets and loadAssets(false) and #cachedAssets.locations > 0 then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local drawDistance = assets.drawDistance or 18.0
            local interactDistance = assets.interactDistance or 2.0

            for i = 1, #cachedAssets.locations do
                local location = cachedAssets.locations[i]
                local stash = toVec3(location.stash)
                local garage = toVec4(location.garage)

                if stash then
                    local distance = #(coords - stash)
                    if distance < drawDistance then
                        sleep = 0
                        DrawMarker(2, stash.x, stash.y, stash.z + 0.2, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.28, 0.28, 0.28, 34, 211, 238, 180, false, true, 2, false, nil, nil, false)
                        if distance < interactDistance then
                            drawText3D(stash + vector3(0.0, 0.0, 0.35), '[E] Inventario de banda')
                            if IsControlJustPressed(0, 38) then openGangStash(location.id) end
                        end
                    end
                end

                if garage then
                    local garageCoords = vector3(garage.x, garage.y, garage.z)
                    local distance = #(coords - garageCoords)
                    if distance < drawDistance then
                        sleep = 0
                        DrawMarker(36, garage.x, garage.y, garage.z + 0.25, 0.0, 0.0, 0.0, 0.0, 0.0, garage.w, 0.65, 0.65, 0.65, 34, 211, 238, 160, false, true, 2, false, nil, nil, false)
                        if distance < interactDistance then
                            drawText3D(garageCoords + vector3(0.0, 0.0, 0.75), '[E] Garaje de banda')
                            if IsControlJustPressed(0, 38) then openGarageMenu(location) end
                        end
                    end
                end
            end
        end

        Wait(sleep)
    end
end)
