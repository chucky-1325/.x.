lib.callback.register('nexus_ems:server:canUse', function(source)
    return NexusEMS.IsMedic(source)
end)

lib.callback.register('nexus_ems:server:prepareAction', function(source, target, actionId)
    if not NexusEMS.RateLimit(source) then return false, 'rate_limited' end
    return NexusEMS.PrepareAction(source, target, actionId)
end)

lib.callback.register('nexus_ems:server:finishAction', function(source, actionToken)
    if not NexusEMS.RateLimit(source) then return false, 'rate_limited' end
    return NexusEMS.FinishAction(source, actionToken)
end)

lib.callback.register('nexus_ems:server:getPatient', function(source, target)
    if not NexusEMS.IsMedic(source) then return false, 'forbidden' end
    if not NexusEMS.IsNear(source, tonumber(target)) then return false, 'too_far' end
    return true, NexusEMS.BuildPatientPayload(source, tonumber(target))
end)

