CreateThread(function()
    exports.ox_target:addGlobalPlayer({
        {
            name = 'nexus_ems_assess',
            icon = 'fa-solid fa-stethoscope',
            label = 'Evaluar paciente',
            distance = NexusEMSConfig.maxPatientDistance,
            canInteract = function(entity)
                if entity == PlayerPedId() then return false end
                local data = exports.qbx_core:GetPlayerData() or {}
                local job = data.job or {}
                return NexusEMSJobs.jobTypes[job.type] == true or NexusEMSJobs.jobs[job.name] ~= nil
            end,
            onSelect = function(data)
                local player = NetworkGetPlayerIndexFromPed(data.entity)
                if player == -1 then return NexusEMSClient.Notify(NexusEMSLocale.noPatient, 'error') end
                NexusEMSClient.AssessPatient(GetPlayerServerId(player))
            end,
        },
    })
end)

