local function notify(description, notifyType)
    if GetResourceState('nexus_ui') == 'started' then
        exports.nexus_ui:notify({
            title = 'Territorios',
            description = description,
            type = notifyType or 'inform',
        })
        return
    end

    lib.notify({ title = 'Territorios', description = description, type = notifyType or 'inform' })
end

local graffitiCache = {}
local activeAirdrop = nil
local airdropObject = nil

local function rotationToDirection(rotation)
    local adjustedRotation = {
        x = (math.pi / 180) * rotation.x,
        y = (math.pi / 180) * rotation.y,
        z = (math.pi / 180) * rotation.z,
    }

    return vector3(
        -math.sin(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)),
        math.cos(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)),
        math.sin(adjustedRotation.x)
    )
end

local function readShapeTest(ray)
    for _ = 1, 12 do
        local status, hit, endCoords, surfaceNormal = GetShapeTestResult(ray)
        if status ~= 1 then
            if hit == 1 then return endCoords, surfaceNormal end
            return nil
        end

        Wait(0)
    end

    return nil
end

local function castRay(origin, destination, flags)
    local ray = StartShapeTestRay(origin.x, origin.y, origin.z, destination.x, destination.y, destination.z, flags, PlayerPedId(), 7)
    return readShapeTest(ray)
end

local function isPointVisible(point)
    local ped = PlayerPedId()
    local origin = GetGameplayCamCoord()
    local targetDistance = #(point - origin)
    local ray = StartExpensiveSynchronousShapeTestLosProbe(origin.x, origin.y, origin.z, point.x, point.y, point.z, -1, ped, 7)
    local _, hit, hitCoords = GetShapeTestResult(ray)

    if hit ~= 1 then return true end
    return #(hitCoords - origin) >= targetDistance - 0.18
end

local function hexToRgb(hex)
    local value = tostring(hex or '#22d3ee'):gsub('#', '')
    if #value ~= 6 then return 34, 211, 238 end

    local r = tonumber(value:sub(1, 2), 16) or 34
    local g = tonumber(value:sub(3, 4), 16) or 211
    local b = tonumber(value:sub(5, 6), 16) or 238
    return r, g, b
end

local function cross(a, b)
    return vector3(
        (a.y * b.z) - (a.z * b.y),
        (a.z * b.x) - (a.x * b.z),
        (a.x * b.y) - (a.y * b.x)
    )
end

local function normalize(value)
    local length = #value
    if length <= 0.001 then return vector3(0.0, 0.0, 0.0) end
    return value / length
end

local function drawPolyDoubleSided(a, b, c, r, g, blue, alpha)
    DrawPoly(a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z, r, g, blue, alpha)
    DrawPoly(c.x, c.y, c.z, b.x, b.y, b.z, a.x, a.y, a.z, r, g, blue, alpha)
end

local function drawWallQuad(center, right, up, width, height, r, g, b, alpha)
    local halfRight = right * (width / 2.0)
    local halfUp = up * (height / 2.0)
    local p1 = center - halfRight - halfUp
    local p2 = center + halfRight - halfUp
    local p3 = center + halfRight + halfUp
    local p4 = center - halfRight + halfUp

    drawPolyDoubleSided(p1, p2, p3, r, g, b, alpha)
    drawPolyDoubleSided(p1, p3, p4, r, g, b, alpha)
end

local segmentMap = {
    ['0'] = { 'a', 'b', 'c', 'd', 'e', 'f' },
    ['1'] = { 'b', 'c' },
    ['2'] = { 'a', 'b', 'g', 'e', 'd' },
    ['3'] = { 'a', 'b', 'g', 'c', 'd' },
    ['4'] = { 'f', 'g', 'b', 'c' },
    ['5'] = { 'a', 'f', 'g', 'c', 'd' },
    ['6'] = { 'a', 'f', 'g', 'e', 'c', 'd' },
    ['7'] = { 'a', 'b', 'c' },
    ['8'] = { 'a', 'b', 'c', 'd', 'e', 'f', 'g' },
    ['9'] = { 'a', 'b', 'c', 'd', 'f', 'g' },
    A = { 'a', 'b', 'c', 'e', 'f', 'g' },
    B = { 'f', 'e', 'g', 'c', 'd' },
    C = { 'a', 'f', 'e', 'd' },
    D = { 'b', 'c', 'd', 'e', 'g' },
    E = { 'a', 'f', 'g', 'e', 'd' },
    F = { 'a', 'f', 'g', 'e' },
    G = { 'a', 'f', 'e', 'd', 'c' },
    H = { 'f', 'e', 'g', 'b', 'c' },
    I = { 'a', 'd' },
    J = { 'b', 'c', 'd', 'e' },
    L = { 'f', 'e', 'd' },
    N = { 'e', 'g', 'b' },
    O = { 'a', 'b', 'c', 'd', 'e', 'f' },
    P = { 'a', 'b', 'f', 'e', 'g' },
    R = { 'a', 'b', 'f', 'e', 'g', 'c' },
    S = { 'a', 'f', 'g', 'c', 'd' },
    T = { 'a', 'g' },
    U = { 'f', 'e', 'd', 'c', 'b' },
    V = { 'f', 'e', 'd', 'c' },
    Y = { 'f', 'g', 'b', 'c', 'd' },
    Z = { 'a', 'b', 'g', 'e', 'd' },
}

local segmentLayout = {
    a = { x = 0.0, y = 0.42, w = 0.34, h = 0.07 },
    b = { x = 0.19, y = 0.22, w = 0.07, h = 0.34 },
    c = { x = 0.19, y = -0.22, w = 0.07, h = 0.34 },
    d = { x = 0.0, y = -0.42, w = 0.34, h = 0.07 },
    e = { x = -0.19, y = -0.22, w = 0.07, h = 0.34 },
    f = { x = -0.19, y = 0.22, w = 0.07, h = 0.34 },
    g = { x = 0.0, y = 0.0, w = 0.34, h = 0.07 },
}

local function drawSegmentCharacter(center, right, up, character, scale, r, g, b)
    local segments = segmentMap[character]
    if not segments then segments = segmentMap['0'] end

    for i = 1, #segments do
        local segment = segmentLayout[segments[i]]
        local segmentCenter = center + (right * (segment.x * scale)) + (up * (segment.y * scale))
        drawWallQuad(segmentCenter, right, up, segment.w * scale, segment.h * scale, 4, 5, 8, 215)
        drawWallQuad(segmentCenter, right, up, segment.w * scale * 0.76, segment.h * scale * 0.76, r, g, b, 235)
    end
end

local function drawGraffitiLogo(point, normal, color, text)
    local graffitiConfig = NexusTerritoriesConfig.graffiti or {}
    local wallNormal = normalize(normal)
    if #wallNormal <= 0.001 then wallNormal = vector3(0.0, -1.0, 0.0) end

    local right = normalize(cross(vector3(0.0, 0.0, 1.0), wallNormal))
    if #right <= 0.001 then right = vector3(1.0, 0.0, 0.0) end

    local up = normalize(cross(wallNormal, right))
    local center = point + (wallNormal * (graffitiConfig.logoDepthOffset or 0.035))
    local size = graffitiConfig.logoSize or 0.92
    local r, g, b = hexToRgb(color)
    local tag = tostring(text or 'TAG'):upper():gsub('[^A-Z0-9]', ''):sub(1, 5)
    if tag == '' then tag = 'TAG' end

    local count = #tag
    local charScale = size / math.max(2.8, count * 1.05)
    local spacing = charScale * 0.52
    local totalWidth = ((count - 1) * spacing)
    local start = center - (right * (totalWidth / 2.0))

    for i = 1, count do
        local char = tag:sub(i, i)
        local charCenter = start + (right * ((i - 1) * spacing))
        drawSegmentCharacter(charCenter, right, up, char, charScale, r, g, b)
    end

    drawWallQuad(center - (up * (size * 0.34)), right, up, size * 0.72, size * 0.045, r, g, b, 180)
    drawWallQuad(center - (up * (size * 0.40)) + (right * (size * 0.06)), right, up, size * 0.46, size * 0.035, 255, 255, 255, 130)
end

local function raycastWall(maxDistance)
    local distance = maxDistance or 6.0
    local direction = rotationToDirection(GetGameplayCamRot(2))
    local camCoords = GetGameplayCamCoord()
    local camDestination = camCoords + (direction * distance)
    local flags = { -1, 511, 17, 1 }

    for i = 1, #flags do
        local hitCoords, normal = castRay(camCoords, camDestination, flags[i])
        if hitCoords then return hitCoords, normal end
    end

    local ped = PlayerPedId()
    local pedCoords = GetEntityCoords(ped)
    local headCoords = vector3(pedCoords.x, pedCoords.y, pedCoords.z + 1.15)
    local pedDestination = headCoords + (direction * distance)

    for i = 1, #flags do
        local hitCoords, normal = castRay(headCoords, pedDestination, flags[i])
        if hitCoords then return hitCoords, normal end
    end

    return nil
end

local function drawText3D(coords, text)
    local onScreen, x, y = World3dToScreen2d(coords.x, coords.y, coords.z)
    if not onScreen then return end

    SetTextScale(0.32, 0.32)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(34, 211, 238, 220)
    SetTextCentre(true)
    SetTextEntry('STRING')
    AddTextComponentString(text)
    DrawText(x, y)
end

local function drawGraffitiTag(coords, text, gangName, color, distance)
    local onScreen, x, y = World3dToScreen2d(coords.x, coords.y, coords.z)
    if not onScreen then return end

    local graffitiConfig = NexusTerritoriesConfig.graffiti or {}
    local maxDistance = graffitiConfig.textDrawDistance or 18.0
    local distanceScale = math.max(0.45, 1.0 - ((distance or 0.0) / maxDistance))
    local scale = (graffitiConfig.textScale or 0.78) * distanceScale
    local tag = tostring(text or gangName or 'TAG'):upper():sub(1, 16)
    local subtitle = tostring(gangName or ''):upper():sub(1, 16)
    local r, g, b = hexToRgb(color)

    SetTextFont(1)
    SetTextScale(scale, scale)
    SetTextCentre(true)
    SetTextColour(0, 0, 0, 220)
    SetTextOutline()
    SetTextEntry('STRING')
    AddTextComponentString(tag)
    DrawText(x + 0.002, y + 0.002)

    SetTextFont(1)
    SetTextScale(scale, scale)
    SetTextCentre(true)
    SetTextColour(r, g, b, 245)
    SetTextOutline()
    SetTextDropShadow(2, 0, 0, 0, 180)
    SetTextEntry('STRING')
    AddTextComponentString(tag)
    DrawText(x, y)

    if subtitle ~= '' then
        SetTextFont(4)
        SetTextScale(scale * 0.28, scale * 0.28)
        SetTextCentre(true)
        SetTextColour(255, 255, 255, 185)
        SetTextOutline()
        SetTextEntry('STRING')
        AddTextComponentString(subtitle)
        DrawText(x, y + (0.038 * distanceScale))
    end
end

local function refreshGraffiti()
    local ok, payload = lib.callback.await('nexus_territories:server:getGraffiti', false)
    if not ok then return end
    graffitiCache = payload or {}
end

local function deleteAirdropObject()
    if airdropObject and DoesEntityExist(airdropObject) then
        DeleteEntity(airdropObject)
    end

    airdropObject = nil
end

local function ensureAirdropObject()
    if not activeAirdrop then
        deleteAirdropObject()
        return
    end

    if airdropObject and DoesEntityExist(airdropObject) then return end

    local config = NexusTerritoriesConfig.airdrop or {}
    local model = joaat(config.model or 'prop_box_wood05a')
    RequestModel(model)
    local timeout = GetGameTimer() + 3000
    while not HasModelLoaded(model) and GetGameTimer() < timeout do
        Wait(0)
    end

    if not HasModelLoaded(model) then return end

    local coords = activeAirdrop.coords
    airdropObject = CreateObject(model, coords.x, coords.y, coords.z, false, false, false)
    SetEntityHeading(airdropObject, 0.0)
    FreezeEntityPosition(airdropObject, true)
    SetEntityInvincible(airdropObject, true)
    SetModelAsNoLongerNeeded(model)
end

local function setAirdrop(payload)
    activeAirdrop = payload
    if not activeAirdrop then
        deleteAirdropObject()
        return
    end

    ensureAirdropObject()
    SetNewWaypoint(activeAirdrop.coords.x + 0.0, activeAirdrop.coords.y + 0.0)
    notify(('Airdrop territorial: %s'):format(activeAirdrop.zoneLabel or activeAirdrop.zoneId), 'warning')
end

local function refreshAirdrop()
    local ok, payload = lib.callback.await('nexus_territories:server:getAirdrop', false)
    if ok then setAirdrop(payload) end
end

local function claimAirdrop()
    if not activeAirdrop then return end

    local config = NexusTerritoriesConfig.airdrop or {}
    local done = lib.progressBar({
        duration = config.captureDuration or 12000,
        label = 'Capturando airdrop territorial',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'amb@prop_human_bum_bin@base', clip = 'base' },
    })

    if not done then return end
    TriggerServerEvent('nexus_territories:server:claimAirdrop', activeAirdrop.id)
end

local function nearestGraffiti()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local closest, closestDistance

    for i = 1, #graffitiCache do
        local graffiti = graffitiCache[i]
        local point = vector3(graffiti.coords.x, graffiti.coords.y, graffiti.coords.z)
        local distance = #(coords - point)
        if not closestDistance or distance < closestDistance then
            closest = graffiti
            closestDistance = distance
        end
    end

    return closest, closestDistance
end

local function sprayGraffiti()
    local graffitiConfig = NexusTerritoriesConfig.graffiti or {}
    if not graffitiConfig.enabled then return end

    local input = lib.inputDialog('Graffiti', {
        { type = 'input', label = 'Texto/logo', description = 'Vacio = tag/logo de tu gang', required = false },
    })

    if not input then return end

    local maxDistance = graffitiConfig.maxSprayDistance or 4.0
    local hitCoords, normal = raycastWall(maxDistance)
    if not hitCoords then
        notify('Apunta a una pared cercana.', 'error')
        return
    end

    if math.abs(normal.z) > (graffitiConfig.wallNormalMaxZ or 0.65) then
        notify('El graffiti debe ir en una pared, no en suelo/techo.', 'error')
        return
    end

    local heading = GetEntityHeading(PlayerPedId())

    local done = lib.progressBar({
        duration = graffitiConfig.sprayDuration or 6000,
        label = 'Pintando graffiti',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'switch@franklin@lamar_tagging_wall', clip = 'lamar_tagging_wall_loop_lamar' },
    })

    if not done then return end

    TriggerServerEvent('nexus_territories:server:sprayGraffiti', {
        text = input[1],
        coords = { x = hitCoords.x, y = hitCoords.y, z = hitCoords.z },
        normal = { x = normal.x, y = normal.y, z = normal.z },
        heading = heading,
    })
end

local function removeGraffiti()
    local graffitiConfig = NexusTerritoriesConfig.graffiti or {}
    if not graffitiConfig.enabled then return end

    local graffiti, distance = nearestGraffiti()
    if not graffiti or distance > (graffitiConfig.interactDistance or 2.5) then
        notify('No hay graffiti cerca.', 'error')
        return
    end

    local done = lib.progressBar({
        duration = graffitiConfig.removeDuration or 5000,
        label = 'Eliminando graffiti',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'amb@world_human_maid_clean@', clip = 'base' },
    })

    if not done then return end

    TriggerServerEvent('nexus_territories:server:removeGraffiti', graffiti.id)
end

local function adminRemoveNearestGraffiti()
    local graffiti, distance = nearestGraffiti()
    if not graffiti or distance > 8.0 then
        notify('No hay graffiti cercano para limpiar.', 'error')
        return
    end

    TriggerServerEvent('nexus_territories:server:adminRemoveGraffiti', graffiti.id)
end

local function openGraffitiList()
    refreshGraffiti()

    local options = {}
    if #graffitiCache == 0 then
        options[#options + 1] = {
            title = 'Sin graffiti activo',
            description = 'No hay marcas territoriales registradas.',
            icon = 'spray-can',
            disabled = true,
        }
    end

    for i = 1, #graffitiCache do
        local graffiti = graffitiCache[i]
        options[#options + 1] = {
            title = ('%s | %s'):format(graffiti.text or 'TAG', graffiti.gangName or 'sin gang'),
            description = ('Zona %s | ID %s'):format(graffiti.zoneId or '-', graffiti.id or '-'),
            icon = 'spray-can',
            onSelect = function()
                SetNewWaypoint(graffiti.coords.x + 0.0, graffiti.coords.y + 0.0)
                notify('GPS marcado al graffiti.', 'success')
            end,
        }
    end

    lib.registerContext({
        id = 'nexus_territories_graffiti_list',
        title = 'Graffiti activo',
        menu = 'nexus_territories_menu',
        options = options,
    })

    lib.showContext('nexus_territories_graffiti_list')
end

local function formatOwner(zone)
    if zone.status == 'controlled' then
        return ('Control: %s | Influencia %s'):format(zone.owner, zone.topInfluence or 0)
    end

    if zone.status == 'contested' then
        return ('Disputado: %s | Influencia %s'):format(zone.owner or 'sin lider', zone.topInfluence or 0)
    end

    return 'Neutral'
end

local function openRankings()
    local ok, payload = lib.callback.await('nexus_territories:server:getRankings', false)
    if not ok then
        notify(payload == 'rate_limited' and 'Espera un momento.' or 'No se pudo cargar ranking.', 'error')
        return
    end

    local options = {}

    options[#options + 1] = {
        title = 'Bandas',
        description = 'Influencia total acumulada por territorio.',
        icon = 'ranking-star',
        disabled = true,
    }

    for i = 1, #(payload.gangs or {}) do
        local entry = payload.gangs[i]
        options[#options + 1] = {
            title = ('#%s %s'):format(i, entry.gang_name),
            description = ('Influencia total %s'):format(entry.influence or 0),
            icon = i == 1 and 'crown' or 'users',
            disabled = true,
        }
    end

    options[#options + 1] = {
        title = 'Jugadores',
        description = 'Contribucion individual registrada por logs.',
        icon = 'user-shield',
        disabled = true,
    }

    for i = 1, #(payload.players or {}) do
        local entry = payload.players[i]
        options[#options + 1] = {
            title = ('#%s %s'):format(i, entry.citizenid or 'desconocido'),
            description = ('Influencia aportada %s'):format(entry.influence or 0),
            icon = 'user',
            disabled = true,
        }
    end

    lib.registerContext({
        id = 'nexus_territories_rankings',
        title = 'Clasificacion',
        menu = 'nexus_territories_menu',
        options = options,
    })

    lib.showContext('nexus_territories_rankings')
end

local function openTerritories()
    local ok, zonesOrReason = lib.callback.await('nexus_territories:server:getZones', false)
    if not ok then
        notify(zonesOrReason == 'rate_limited' and 'Espera un momento.' or 'No se pudieron cargar territorios.', 'error')
        return
    end

    local options = {
        {
            title = 'Clasificacion',
            description = 'Ranking de bandas y jugadores por influencia.',
            icon = 'ranking-star',
            onSelect = openRankings,
        },
        {
            title = 'Graffiti activo',
            description = 'Marcas territoriales visibles y waypoint.',
            icon = 'spray-can',
            onSelect = openGraffitiList,
        },
    }

    for _, zone in ipairs(zonesOrReason or {}) do
        local influenceText = {}
        for i = 1, math.min(#(zone.influence or {}), 3) do
            local entry = zone.influence[i]
            influenceText[#influenceText + 1] = ('%s %s'):format(entry.gang, entry.influence)
        end

        options[#options + 1] = {
            title = zone.label,
            description = ('%s | Heat x%s | %s'):format(formatOwner(zone), zone.heatMultiplier or 1.0, table.concat(influenceText, ', ')),
            icon = zone.status == 'controlled' and 'crown' or (zone.status == 'contested' and 'fire' or 'circle'),
            disabled = true,
        }
    end

    lib.registerContext({
        id = 'nexus_territories_menu',
        title = 'Territorios',
        options = options,
    })

    lib.showContext('nexus_territories_menu')
end

local function currentCoordsPayload()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)

    return { x = coords.x, y = coords.y, z = coords.z }
end

local function openCreateZone()
    local input = lib.inputDialog('Crear territorio', {
        { type = 'input', label = 'ID', description = 'Ejemplo: rancho_norte', required = true },
        { type = 'input', label = 'Nombre', description = 'Nombre visible del territorio', required = true },
        { type = 'number', label = 'Radio', default = NexusTerritoriesConfig.editor.defaultRadius, min = NexusTerritoriesConfig.editor.minimumRadius, max = NexusTerritoriesConfig.editor.maximumRadius, required = true },
        { type = 'number', label = 'Heat multiplier', default = 1.0, min = 0.5, max = 3.0, required = true },
    })

    if not input then return end

    TriggerServerEvent('nexus_territories:server:saveZone', {
        id = input[1],
        label = input[2],
        radius = input[3],
        heatMultiplier = input[4],
        coords = currentCoordsPayload(),
        enabled = true,
    })
end

local function openEditZone(zone)
    local options = {
        {
            title = zone.label,
            description = ('%s | Radio %s | Heat x%s'):format(zone.dynamic and 'Dinamica' or 'Predefinida', zone.radius or 0, zone.heatMultiplier or 1.0),
            icon = zone.dynamic and 'pen-tool' or 'lock',
            disabled = true,
        },
        {
            title = 'Marcar GPS',
            description = 'Pone waypoint en el centro del territorio.',
            icon = 'map-pin',
            onSelect = function()
                SetNewWaypoint(zone.coords.x + 0.0, zone.coords.y + 0.0)
                notify(('GPS marcado: %s'):format(zone.label), 'success')
            end,
        },
    }

    if zone.dynamic then
        options[#options + 1] = {
            title = 'Mover aqui',
            description = 'Guarda el centro del territorio en tu posicion actual.',
            icon = 'arrows-up-down-left-right',
            onSelect = function()
                TriggerServerEvent('nexus_territories:server:saveZone', {
                    id = zone.id,
                    label = zone.label,
                    radius = zone.radius,
                    heatMultiplier = zone.heatMultiplier,
                    coords = currentCoordsPayload(),
                    enabled = true,
                })
            end,
        }

        options[#options + 1] = {
            title = 'Editar valores',
            description = 'Cambia nombre, radio y heat.',
            icon = 'sliders',
            onSelect = function()
                local input = lib.inputDialog(('Editar %s'):format(zone.label), {
                    { type = 'input', label = 'Nombre', default = zone.label, required = true },
                    { type = 'number', label = 'Radio', default = zone.radius, min = NexusTerritoriesConfig.editor.minimumRadius, max = NexusTerritoriesConfig.editor.maximumRadius, required = true },
                    { type = 'number', label = 'Heat multiplier', default = zone.heatMultiplier or 1.0, min = 0.5, max = 3.0, required = true },
                })

                if not input then return end
                TriggerServerEvent('nexus_territories:server:saveZone', {
                    id = zone.id,
                    label = input[1],
                    radius = input[2],
                    heatMultiplier = input[3],
                    coords = zone.coords,
                    enabled = true,
                })
            end,
        }

        options[#options + 1] = {
            title = 'Eliminar territorio',
            description = 'Elimina zona dinamica e influencia asociada.',
            icon = 'trash',
            onSelect = function()
                local alert = lib.alertDialog({
                    header = 'Eliminar territorio',
                    content = ('Eliminar %s y su influencia?'):format(zone.label),
                    centered = true,
                    cancel = true,
                })

                if alert == 'confirm' then
                    TriggerServerEvent('nexus_territories:server:deleteZone', zone.id)
                end
            end,
        }
    end

    lib.registerContext({
        id = 'nexus_territories_editor_zone',
        title = zone.label,
        menu = 'nexus_territories_editor',
        options = options,
    })

    lib.showContext('nexus_territories_editor_zone')
end

local function openEditor()
    local ok, zonesOrReason = lib.callback.await('nexus_territories:server:getEditorZones', false)
    if not ok then
        notify(zonesOrReason == 'no_access' and 'No tienes permiso.' or 'No se pudo cargar editor.', 'error')
        return
    end

    local options = {
        {
            title = 'Crear territorio aqui',
            description = 'Crea una zona circular usando tu posicion actual.',
            icon = 'plus',
            onSelect = openCreateZone,
        },
    }

    for _, zone in ipairs(zonesOrReason or {}) do
        options[#options + 1] = {
            title = zone.label,
            description = ('%s | Radio %s | Heat x%s'):format(zone.dynamic and 'Dinamica' or 'Predefinida', zone.radius or 0, zone.heatMultiplier or 1.0),
            icon = zone.dynamic and 'pen-tool' or 'lock',
            onSelect = function()
                openEditZone(zone)
            end,
        }
    end

    lib.registerContext({
        id = 'nexus_territories_editor',
        title = 'Editor territorios',
        options = options,
    })

    lib.showContext('nexus_territories_editor')
end

exports('openTerritories', openTerritories)
exports('openTerritoryEditor', openEditor)

RegisterNetEvent('nexus_territories:client:open', openTerritories)
RegisterNetEvent('nexus_territories:client:openEditor', openEditor)
RegisterNetEvent('nexus_territories:client:zonesUpdated', function()
    notify('Territorios actualizados.', 'inform')
end)
RegisterNetEvent('nexus_territories:client:graffitiUpdated', function()
    refreshGraffiti()
end)
RegisterNetEvent('nexus_territories:client:setAirdrop', setAirdrop)
RegisterNetEvent('nexus_territories:client:useSpray', sprayGraffiti)
RegisterNetEvent('nexus_territories:client:useGraffitiRemover', removeGraffiti)
RegisterCommand(NexusTerritoriesConfig.command, openTerritories, false)
RegisterCommand(NexusTerritoriesConfig.editorCommand, openEditor, false)
RegisterCommand('spray', sprayGraffiti, false)
RegisterCommand('cleangraffiti', removeGraffiti, false)
RegisterCommand('graffitirefresh', function()
    refreshGraffiti()
    notify('Graffiti recargado.', 'success')
end, false)
RegisterCommand('graffitiadminclean', adminRemoveNearestGraffiti, false)
RegisterCommand('airdroprefresh', refreshAirdrop, false)

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Wait(500)
    refreshGraffiti()
    refreshAirdrop()

    CreateThread(function()
        while true do
            local sleep = 1000
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local drawDistance = NexusTerritoriesConfig.graffiti.drawDistance or 45.0

            for i = 1, #graffitiCache do
                local graffiti = graffitiCache[i]
                local point = vector3(graffiti.coords.x, graffiti.coords.y, graffiti.coords.z)
                local normal = graffiti.normal and vector3(graffiti.normal.x, graffiti.normal.y, graffiti.normal.z) or vector3(0.0, 0.0, 1.0)
                local drawPoint = point + (normal * 0.04)
                local distance = #(coords - point)
                if distance <= drawDistance and isPointVisible(drawPoint) then
                    sleep = 0
                    drawGraffitiLogo(point, normal, graffiti.color, graffiti.text or graffiti.gangName)
                end
            end

            if activeAirdrop and activeAirdrop.coords then
                ensureAirdropObject()
                local dropPoint = vector3(activeAirdrop.coords.x, activeAirdrop.coords.y, activeAirdrop.coords.z)
                local distance = #(coords - dropPoint)
                local config = NexusTerritoriesConfig.airdrop or {}
                if distance <= (config.drawDistance or 90.0) then
                    sleep = 0
                    DrawMarker(1, dropPoint.x, dropPoint.y, dropPoint.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2.8, 2.8, 0.45, 34, 211, 238, 120, false, true, 2, nil, nil, false)
                    drawText3D(dropPoint + vector3(0.0, 0.0, 1.25), ('AIRDROP | %s'):format(activeAirdrop.zoneLabel or activeAirdrop.zoneId))

                    if distance <= (config.captureDistance or 3.0) then
                        lib.showTextUI('[E] Capturar airdrop', { icon = 'box-open' })
                        if IsControlJustReleased(0, 38) then
                            lib.hideTextUI()
                            claimAirdrop()
                        end
                    else
                        lib.hideTextUI()
                    end
                end
            end

            Wait(sleep)
        end
    end)

    print('[nexus_territories] territorios cliente cargado')
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    deleteAirdropObject()
end)
