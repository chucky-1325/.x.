NexusBridgeUtils = NexusBridgeUtils or {}

function NexusBridgeUtils.copy(value)
    if type(value) ~= 'table' then return value end

    local result = {}
    for key, child in pairs(value) do
        result[key] = NexusBridgeUtils.copy(child)
    end

    return result
end

function NexusBridgeUtils.trim(value, maxLength)
    if type(value) ~= 'string' then return '' end

    value = value:gsub('[%z\1-\31]', ''):match('^%s*(.-)%s*$') or ''
    if maxLength and #value > maxLength then
        value = value:sub(1, maxLength)
    end

    return value
end

function NexusBridgeUtils.log(level, message)
    print(('[nexus_bridge] [%s] %s'):format(level or 'INFO', message or ''))
end
