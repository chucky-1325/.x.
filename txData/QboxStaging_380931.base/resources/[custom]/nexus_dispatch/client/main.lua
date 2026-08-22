local activeBlips = {}

local function notify(message, type)
    lib.notify({
        title = 'Dispatch',
        description = message,
        type = type or 'inform',
    })
end

local function coordsFromAlert(alert)
    local coords = alert and alert.coords
    if not coords then return nil end
    local x = tonumber(coords.x or coords[1])
    local y = tonumber(coords.y or coords[2])
    local z = tonumber(coords.z or coords[3])
    if not x or not y or not z then return nil end
    return vector3(x, y, z)
end

local function createAlertBlip(alert)
    local coords = coordsFromAlert(alert)
    if not coords then return end

    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, alert.sprite or 161)
    SetBlipColour(blip, alert.color or 3)
    SetBlipScale(blip, 0.85)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(alert.title or 'Dispatch')
    EndTextCommandSetBlipName(blip)

    activeBlips[#activeBlips + 1] = blip

    SetTimeout((NexusDispatchConfig.blipSeconds or 90) * 1000, function()
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end)
end

RegisterNetEvent('nexus_dispatch:client:alert', function(alert)
    alert = alert or {}
    notify(('%s | Riesgo %s%%'):format(alert.title or 'Incidente', alert.risk or 0), 'warning')
    createAlertBlip(alert)
end)

RegisterNetEvent('nexus_dispatch:client:updated', function(alert)
    if not alert or not alert.id then return end
    notify(('#%s actualizado: %s'):format(alert.id, alert.status or 'estado'), 'inform')
end)

local function setAlertStatus(alert, status)
    local ok, result = lib.callback.await('nexus_dispatch:server:updateAlert', false, alert.id, status)
    if not ok then
        return notify(('No se pudo actualizar alerta: %s'):format(result or 'error'), 'error')
    end

    notify(('Alerta #%s actualizada.'):format(result.id or alert.id), 'success')
    return result
end

local function createAisCase(alert)
    local ok, result = lib.callback.await('nexus_dispatch:server:createAisCase', false, alert.id)
    if not ok then
        return notify(('No se pudo crear caso AIS: %s'):format(result or 'error'), 'error')
    end

    notify(('Caso AIS creado: %s'):format(result.aisCaseNumber or result.aisCaseId or alert.id), 'success')
    return result
end

local function openAlertDetail(alert)
    local coords = coordsFromAlert(alert)
    local status = alert.status or 'open'
    local assigned = alert.assignedName and alert.assignedName ~= '' and alert.assignedName or 'sin unidad'

    local options = {
        {
            title = 'Marcar GPS',
            description = coords and 'Crear waypoint a la alerta.' or 'Esta alerta no tiene coordenadas.',
            icon = 'map-pin',
            disabled = not coords,
            onSelect = function()
                if not coords then return end
                SetNewWaypoint(coords.x, coords.y)
                notify('Ubicacion marcada en GPS.', 'success')
            end
        },
        {
            title = 'Asignarme',
            description = ('Estado actual: %s | Unidad: %s'):format(status, assigned),
            icon = 'user-check',
            disabled = status == 'closed',
            onSelect = function()
                setAlertStatus(alert, 'assigned')
            end
        },
        {
            title = 'Marcar en ruta',
            description = 'La unidad va hacia la ubicacion.',
            icon = 'route',
            disabled = status == 'closed',
            onSelect = function()
                setAlertStatus(alert, 'enroute')
            end
        },
        {
            title = 'Crear caso AIS',
            description = alert.aisCaseNumber and ('Ya vinculado: %s'):format(alert.aisCaseNumber) or 'Convierte esta alerta en caso investigativo.',
            icon = 'folder-plus',
            disabled = alert.aisCaseNumber ~= nil and alert.aisCaseNumber ~= '',
            onSelect = function()
                createAisCase(alert)
            end
        },
        {
            title = 'Cerrar incidente',
            description = 'Cierra el incidente y lo deja en historial.',
            icon = 'circle-check',
            disabled = status == 'closed',
            onSelect = function()
                setAlertStatus(alert, 'closed')
            end
        },
    }

    lib.registerContext({
        id = ('nexus_dispatch_alert_%s'):format(alert.id or 'unknown'),
        title = ('Dispatch #%s'):format(alert.id or '?'),
        menu = 'nexus_dispatch_menu',
        options = options,
    })
    lib.showContext(('nexus_dispatch_alert_%s'):format(alert.id or 'unknown'))
end

local function openDispatch()
    local ok, result = lib.callback.await('nexus_dispatch:server:getRecent', false)
    if not ok then
        return notify(result == 'no_access' and 'No tienes acceso al dispatch.' or 'Dispatch no disponible.', 'error')
    end

    local options = {}
    for i = 1, #(result or {}) do
        local alert = result[i]
        local status = alert.status or 'open'
        local assigned = alert.assignedName and alert.assignedName ~= '' and alert.assignedName or 'sin unidad'
        local caseTag = alert.aisCaseNumber and alert.aisCaseNumber ~= '' and (' | AIS %s'):format(alert.aisCaseNumber) or ''
        local description = ('%s | %s | Riesgo %s%% | %s%s'):format(alert.message or 'Sin descripcion', status, alert.risk or 0, assigned, caseTag)
        options[#options + 1] = {
            title = ('#%s %s'):format(alert.id or '?', alert.title or 'Incidente'),
            description = description,
            icon = status == 'closed' and 'circle-check' or (alert.priority and alert.priority >= 3 and 'triangle-alert' or 'radio'),
            onSelect = function()
                openAlertDetail(alert)
            end
        }
    end

    if #options == 0 then
        options[1] = {
            title = 'Sin alertas',
            description = 'No hay alertas recientes registradas.',
            disabled = true,
        }
    end

    lib.registerContext({
        id = 'nexus_dispatch_menu',
        title = 'NEXUS Dispatch',
        options = options,
    })
    lib.showContext('nexus_dispatch_menu')
end

RegisterCommand(NexusDispatchConfig.command or 'dispatch', openDispatch, false)
exports('openDispatch', openDispatch)

print('[nexus_dispatch] dispatch cliente cargado')
