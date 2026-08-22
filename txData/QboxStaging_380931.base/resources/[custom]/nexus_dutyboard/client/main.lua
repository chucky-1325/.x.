local zoneId = nil
local panelOpen = false

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

local function closePanel()
    if not panelOpen then return end
    panelOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function openPanel()
    if panelOpen then return end
    local status = lib.callback.await('nexus_dutyboard:server:getStatus', false)
    if not status then return end

    panelOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', status = status })
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

RegisterNUICallback('close', function(_, cb)
    closePanel()
    cb(1)
end)

RegisterNUICallback('toggle', function(_, cb)
    local ok, onDuty = lib.callback.await('nexus_dutyboard:server:toggleDuty', false)
    cb({ ok = ok or false, onDuty = onDuty or false })
end)

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
    closePanel()
end)
