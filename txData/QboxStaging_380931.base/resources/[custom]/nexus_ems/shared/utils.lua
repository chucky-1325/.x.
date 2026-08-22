NexusEMSUtils = {}

function NexusEMSUtils.clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    return math.max(minimum, math.min(maximum, value))
end

function NexusEMSUtils.gradeLevel(job)
    local grade = job and job.grade
    if type(grade) == 'table' then return tonumber(grade.level) or 0 end
    return tonumber(grade) or 0
end

function NexusEMSUtils.copy(source)
    local result = {}
    for key, value in pairs(source or {}) do result[key] = value end
    return result
end

function NexusEMSUtils.distance(coordsA, coordsB)
    if not coordsA or not coordsB then return math.huge end
    return #(coordsA - coordsB)
end

