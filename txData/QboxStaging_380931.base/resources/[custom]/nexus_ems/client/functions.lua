NexusEMSClient = NexusEMSClient or {
    busy = false,
    tabletOpen = false,
    currentPatient = nil,
    activeToken = nil,
}

function NexusEMSClient.Notify(description, notifyType)
    lib.notify({
        title = 'NEXUS Clinica',
        description = description,
        type = notifyType or 'inform',
    })
end

function NexusEMSClient.GetClosestPatient(maxDistance)
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local closestId, closestDistance

    for _, player in ipairs(GetActivePlayers()) do
        if player ~= PlayerId() then
            local targetPed = GetPlayerPed(player)
            local distance = #(playerCoords - GetEntityCoords(targetPed))
            if distance <= (maxDistance or NexusEMSConfig.maxPatientDistance) and (not closestDistance or distance < closestDistance) then
                closestId = GetPlayerServerId(player)
                closestDistance = distance
            end
        end
    end

    return closestId, closestDistance
end

function NexusEMSClient.CloseTablet()
    NexusEMSClient.tabletOpen = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'close' })
end

function NexusEMSClient.OpenTablet(payload)
    if type(payload) ~= 'table' or type(payload.patient) ~= 'table' then return end
    NexusEMSClient.currentPatient = payload.patient.serverId
    NexusEMSClient.tabletOpen = true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'open', payload = payload })
end

local function reasonMessage(reason)
    if type(reason) == 'string' and reason:sub(1, 13) == 'missing_item:' then
        return ('Falta material sanitario: %s'):format(reason:sub(14))
    end

    local messages = {
        forbidden = NexusEMSLocale.noAccess,
        invalid_patient = NexusEMSLocale.noPatient,
        physical_busy = NexusEMSLocale.busy,
        patient_busy = NexusEMSLocale.patientBusy,
        too_far = 'Te alejaste demasiado del paciente.',
        not_indicated = 'Este tratamiento no esta indicado ahora.',
        grade = 'Tu certificacion no permite esta intervencion.',
        cooldown = 'Espera antes de repetir esta intervencion.',
        too_early = 'La intervencion no se completo correctamente.',
        expired = 'La sesion clinica ha expirado.',
    }
    return messages[reason] or 'No se pudo realizar la intervencion.'
end

function NexusEMSClient.RunAction(target, actionId)
    if NexusEMSClient.busy then
        NexusEMSClient.Notify(NexusEMSLocale.busy, 'error')
        return false
    end

    NexusEMSClient.busy = true
    local ok, prepared = lib.callback.await('nexus_ems:server:prepareAction', false, target, actionId)
    if not ok or type(prepared) ~= 'table' then
        NexusEMSClient.busy = false
        NexusEMSClient.Notify(reasonMessage(prepared), 'error')
        return false
    end

    NexusEMSClient.activeToken = prepared.token
    local completed
    if GetResourceState('nexus_scene_core') == 'started' and NexusEMSConfig.scenes.enabled ~= false then
        completed = exports.nexus_scene_core:play(prepared.sceneId, {
            duration = prepared.duration,
            label = prepared.label,
            targetCoords = prepared.coords,
            canCancel = true,
        })
    else
        completed = lib.progressBar({
            duration = prepared.duration,
            label = prepared.label,
            useWhileDead = false,
            canCancel = true,
            disable = { move = true, car = true, combat = true },
            anim = { dict = 'amb@medic@standing@kneel@base', clip = 'base' },
        })
    end

    if not completed then
        TriggerServerEvent('nexus_ems:server:cancelAction', prepared.token)
        NexusEMSClient.activeToken = nil
        NexusEMSClient.busy = false
        NexusEMSClient.Notify(NexusEMSLocale.cancelled, 'inform')
        return false
    end

    local finished, payload = lib.callback.await('nexus_ems:server:finishAction', false, prepared.token)
    NexusEMSClient.activeToken = nil
    NexusEMSClient.busy = false
    if not finished or type(payload) ~= 'table' then
        NexusEMSClient.Notify(reasonMessage(payload), 'error')
        return false
    end

    if actionId == 'prepare_transport' and payload.hospital then
        SetNewWaypoint(payload.hospital.x, payload.hospital.y)
        NexusEMSClient.Notify('Destino hospitalario marcado en GPS.', 'inform')
    end

    NexusEMSClient.OpenTablet(payload)
    return true
end

function NexusEMSClient.AssessPatient(target)
    target = tonumber(target)
    if not target then return NexusEMSClient.Notify(NexusEMSLocale.noPatient, 'error') end
    NexusEMSClient.CloseTablet()
    NexusEMSClient.RunAction(target, 'assess')
end

