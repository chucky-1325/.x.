local zoneId = nil

local function notify(description, notifyType)
    if GetResourceState('nexus_ui') == 'started' then
        exports.nexus_ui:notify({
            title = 'Fichaje',
            description = description,
            type = notifyType or 'inform',
        })
        return
    end

    lib.notify({ title = 'Fichaje', description = description, type = notifyType or 'inform' })
end

local function taskLabel(task, kind)
    if kind == 'lot' then return ('Transporte activo (%s)'):format(task.state) end
    return ('Fabricacion activa (%s)'):format(task.state)
end

local function doToggle()
    lib.callback.await('nexus_dutyboard:server:toggleDuty', false)
end

local function openPanel()
    local status = lib.callback.await('nexus_dutyboard:server:getStatus', false)
    if not status then return end

    local options = {}

    if not status.eligible then
        options[#options + 1] = {
            title = 'Sin acceso',
            description = 'Este punto de fichaje es exclusivo del taller mecanico.',
            disabled = true,
            icon = 'fa-solid fa-ban',
        }
    else
        local hasIncident = status.craft and status.craft.incidentReason
        local hasTasks = status.lot ~= nil or status.craft ~= nil

        local stateLabel = 'Fuera de servicio'
        local stateIcon = 'fa-solid fa-circle-xmark'
        if status.onDuty then
            if hasIncident then
                stateLabel = 'En servicio - incidencia'
                stateIcon = 'fa-solid fa-triangle-exclamation'
            elseif hasTasks then
                stateLabel = 'En servicio - con tareas'
                stateIcon = 'fa-solid fa-list-check'
            else
                stateLabel = 'En servicio'
                stateIcon = 'fa-solid fa-circle-check'
            end
        end

        options[#options + 1] = {
            title = stateLabel,
            disabled = true,
            icon = stateIcon,
        }

        if status.grade then
            options[#options + 1] = {
                title = ('Rango: %s (nivel %s)'):format(status.grade.name, status.grade.level),
                disabled = true,
                icon = 'fa-solid fa-id-badge',
            }
        end

        if hasIncident then
            options[#options + 1] = {
                title = 'Incidencia pendiente',
                description = ('Reserva de fabricacion retenida para revision administrativa. Motivo: %s'):format(status.craft.incidentReason),
                disabled = true,
                icon = 'fa-solid fa-triangle-exclamation',
            }
        end

        if status.lot then
            options[#options + 1] = {
                title = taskLabel(status.lot, 'lot'),
                disabled = true,
                icon = 'fa-solid fa-truck',
            }
        end

        if status.craft then
            options[#options + 1] = {
                title = taskLabel(status.craft, 'craft'),
                disabled = true,
                icon = 'fa-solid fa-hammer',
            }
        end

        options[#options + 1] = {
            title = status.onDuty and 'Fichar salida' or 'Fichar entrada',
            icon = status.onDuty and 'fa-solid fa-right-from-bracket' or 'fa-solid fa-right-to-bracket',
            onSelect = function()
                if status.onDuty and hasTasks then
                    local confirmed = lib.alertDialog({
                        header = 'Confirmar salida',
                        content = 'Tienes tareas activas. Fichar salida de todos modos? Las tareas seguiran abiertas.',
                        centered = true,
                        cancel = true,
                    })
                    if confirmed ~= 'confirm' then return end
                end
                doToggle()
            end,
        }
    end

    lib.registerContext({
        id = 'nexus_dutyboard_panel',
        title = 'Tablon de Turnos',
        options = options,
    })
    lib.showContext('nexus_dutyboard_panel')
end

local function createZone()
    if GetResourceState('ox_target') ~= 'started' then return end
    if zoneId then return end

    zoneId = exports.ox_target:addSphereZone({
        coords = NexusDutyboardConfig.point,
        radius = NexusDutyboardConfig.radius,
        debug = NexusDutyboardConfig.debug,
        options = {
            {
                name = 'nexus_dutyboard_toggle',
                icon = NexusDutyboardConfig.targetIcon,
                label = NexusDutyboardConfig.targetLabel,
                onSelect = function()
                    openPanel()
                end,
            },
        },
    })
end

local function removeZone()
    if not zoneId then return end
    if GetResourceState('ox_target') == 'started' then
        exports.ox_target:removeZone(zoneId)
    end
    zoneId = nil
end

RegisterNetEvent('nexus_dutyboard:client:notify', function(data)
    if type(data) ~= 'table' then return end
    notify(data.description, data.type)
end)

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    createZone()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    removeZone()
end)
