NexusSceneUtils = {}

function NexusSceneUtils.clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

function NexusSceneUtils.copy(value)
    if type(value) ~= 'table' then return value end

    local result = {}
    for key, entry in pairs(value) do
        result[key] = NexusSceneUtils.copy(entry)
    end
    return result
end

function NexusSceneUtils.isValidId(value)
    return type(value) == 'string'
        and #value >= 3
        and #value <= 64
        and value:match('^[%w_%-]+$') ~= nil
end

function NexusSceneUtils.toCoords(value)
    if type(value) ~= 'table' and type(value) ~= 'vector3' then return nil end

    local x = tonumber(value.x)
    local y = tonumber(value.y)
    local z = tonumber(value.z)
    if not x or not y or not z then return nil end

    return vector3(x, y, z)
end
