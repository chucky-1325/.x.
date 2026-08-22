local function notify(description, notifyType)
    if GetResourceState('nexus_ui') == 'started' then
        exports.nexus_ui:notify({
            title = 'NEXUS',
            description = description,
            type = notifyType or 'inform',
        })
        return
    end

    lib.notify({ title = 'NEXUS', description = description, type = notifyType or 'inform' })
end

local function safeCall(resource, exportName, ...)
    if GetResourceState(resource) ~= 'started' then
        notify(('Recurso no iniciado: %s'):format(resource), 'error')
        return false
    end

    local args = { ... }
    local ok, err = pcall(function()
        exports[resource][exportName](table.unpack(args))
    end)

    if not ok then
        notify(('No se pudo abrir %s'):format(resource), 'error')
        print(('[nexus_menu] export failed %s:%s -> %s'):format(resource, exportName, err))
    end

    return ok
end

local function openItemDemo(kind)
    safeCall('qbx_item_ui', 'openItemSheet', DemoItems and DemoItems[kind] or { kind = kind })
end

local function openItemMenu()
    local options = {}
    for i = 1, #NexusMenuConfig.itemDemos do
        local demo = NexusMenuConfig.itemDemos[i]
        options[#options + 1] = {
            title = demo.label,
            description = ('Abrir ficha contextual: %s'):format(demo.kind),
            icon = 'box',
            onSelect = function()
                ExecuteCommand(('ficha %s'):format(demo.kind))
            end,
        }
    end

    lib.registerContext({
        id = 'nexus_item_menu',
        title = 'Fichas de item',
        menu = 'nexus_main_menu',
        options = options,
    })

    lib.showContext('nexus_item_menu')
end

local function openProgression()
    if GetResourceState('nexus_progression') ~= 'started' then
        notify('Progresion no iniciada.', 'error')
        return
    end

    exports.nexus_progression:openProgression()
end

local function isAdmin()
    local ok, result = pcall(function()
        return lib.callback.await('nexus_menu:server:isAdmin', false)
    end)

    return ok and result == true
end

local function getAccess()
    local ok, result = pcall(function()
        return lib.callback.await('nexus_menu:server:getAccess', false)
    end)

    if ok and result then return result end

    return {
        admin = false,
        police = false,
        ems = false,
        illegal = false,
        job = { name = 'unknown', type = 'none' },
        gang = { name = 'none' },
    }
end

local function giveAdminKit(kitId)
    TriggerServerEvent('nexus_menu:server:giveAdminKit', kitId)
end

local function addCraftingProgress(xp, reputation)
    TriggerServerEvent('nexus_menu:server:addCraftingProgress', xp, reputation)
end

local function addDomainProgress(domain, xp, reputation)
    TriggerServerEvent('nexus_menu:server:addDomainProgress', domain, xp, reputation)
end

local function addNearbyInfluence(amount)
    if GetResourceState('nexus_territories') ~= 'started' then
        notify('Territorios no iniciado.', 'error')
        return
    end

    TriggerServerEvent('nexus_territories:server:adminAddNearbyInfluence', amount)
end

local function addGangReputation(amount)
    if GetResourceState('nexus_gangs') ~= 'started' then
        notify('Bandas no iniciado.', 'error')
        return
    end

    TriggerServerEvent('nexus_gangs:server:adminAddGangReputation', amount)
end

local function openInfluenceZoneMenu(amount)
    if GetResourceState('nexus_territories') ~= 'started' then
        notify('Territorios no iniciado.', 'error')
        return
    end

    local ok, zones = lib.callback.await('nexus_territories:server:getZones', false)
    if not ok then
        notify('No se pudieron cargar territorios.', 'error')
        return
    end

    local options = {}
    for i = 1, #(zones or {}) do
        local zone = zones[i]
        options[#options + 1] = {
            title = zone.label or zone.id,
            description = ('Owner %s | Estado %s | Top %s | %+d influencia'):format(
                zone.owner or 'none',
                zone.status or 'neutral',
                zone.topInfluence or 0,
                amount
            ),
            icon = 'map-pin',
            onSelect = function()
                TriggerServerEvent('nexus_territories:server:adminAddZoneInfluence', zone.id, amount)
            end,
        }
    end

    lib.registerContext({
        id = 'nexus_admin_influence_zone_menu',
        title = ('Dar influencia %+d'):format(amount),
        menu = 'nexus_admin_test_menu',
        options = options,
    })
    lib.showContext('nexus_admin_influence_zone_menu')
end

local function openIllegalValidationMenu()
    if not isAdmin() then
        notify('No tienes permiso admin.', 'error')
        return
    end

    local ok, payload = lib.callback.await('nexus_menu:server:getIllegalValidationStatus', false)
    local resourceLines = {}

    if ok and payload and payload.resources then
        for i = 1, #payload.resources do
            local entry = payload.resources[i]
            local state = entry.state == 'started' and 'OK' or (entry.state or 'missing')
            resourceLines[#resourceLines + 1] = ('%s: %s'):format(entry.name, state)
        end
    else
        resourceLines[#resourceLines + 1] = 'No se pudo leer estado de recursos.'
    end

    lib.registerContext({
        id = 'nexus_illegal_validation_menu',
        title = 'Validacion ilegal v1',
        menu = 'nexus_admin_test_menu',
        options = {
            {
                title = 'Estado de recursos',
                description = table.concat(resourceLines, ' | '),
                icon = 'server',
                disabled = true,
            },
            {
                title = 'Dar kit loop ilegal v1',
                description = 'Materiales, blueprints, spray/remover y dinero sucio.',
                icon = 'box-open',
                onSelect = function()
                    giveAdminKit('illegal_loop_v1')
                end,
            },
            {
                title = 'Boost criminal +2500',
                description = 'Desbloquea contactos, labs y lavado para pruebas.',
                icon = 'user-secret',
                onSelect = function()
                    addDomainProgress('criminal', 2500, 25)
                    Wait(250)
                    openProgression()
                end,
            },
            {
                title = 'Boost crafting +2500',
                description = 'Desbloquea recetas avanzadas y clasificadas.',
                icon = 'hammer',
                onSelect = function()
                    addDomainProgress('crafting', 2500, 15)
                    Wait(250)
                    openProgression()
                end,
            },
            {
                title = 'Influencia Rancho +100',
                description = 'Suma influencia exacta en Rancho para labs/beneficios.',
                icon = 'map-pin',
                onSelect = function()
                    TriggerServerEvent('nexus_territories:server:adminAddZoneInfluence', 'rancho', 100)
                end,
            },
            {
                title = 'Reputacion banda +100',
                description = 'Sube reputacion global de tu banda actual.',
                icon = 'ranking-star',
                onSelect = function()
                    addGangReputation(100)
                end,
            },
            {
                title = '1. Tablet ilegal',
                description = 'Verifica dashboard, riesgo, operaciones, labs y lavado.',
                icon = 'tablet-screen-button',
                onSelect = function()
                    safeCall('nexus_tablet', 'openTablet', 'illegal')
                end,
            },
            {
                title = '2. Contratos',
                description = 'Genera reputacion criminal y paquete fisico.',
                icon = 'route',
                onSelect = function()
                    safeCall('nexus_contracts', 'openContracts')
                end,
            },
            {
                title = '3. Mercado negro',
                description = 'Compra blueprint y valida heat/stock.',
                icon = 'mask',
                onSelect = function()
                    ExecuteCommand('blackmarket rancho_contact')
                end,
            },
            {
                title = '4. Crafting ilegal',
                description = 'Valida blueprint, nivel, materiales y riesgo.',
                icon = 'screwdriver-wrench',
                onSelect = function()
                    safeCall('nexus_crafting', 'openCrafting', 'illegal_bench')
                end,
            },
            {
                title = '5. Operaciones',
                description = 'Suministros/extorsion con ruta, NPC y stash.',
                icon = 'people-carry-box',
                onSelect = function()
                    safeCall('nexus_operations', 'openOperations')
                end,
            },
            {
                title = '6. Laboratorios',
                description = 'Produccion territorial y riesgo policial.',
                icon = 'flask-vial',
                onSelect = function()
                    safeCall('nexus_labs', 'openLabs')
                end,
            },
            {
                title = '7. Lavado',
                description = 'Convierte black_money en cash con comision/cooldown.',
                icon = 'money-bill-transfer',
                onSelect = function()
                    safeCall('nexus_laundering', 'openLaundering')
                end,
            },
            {
                title = '8. Territorios',
                description = 'Control, influencia, graffiti, ranking y airdrops.',
                icon = 'map',
                onSelect = function()
                    safeCall('nexus_territories', 'openTerritories')
                end,
            },
            {
                title = 'Rescatar foco/pantalla',
                description = 'Usar si una NUI queda abierta o se bloquea foco.',
                icon = 'eye',
                onSelect = function()
                    ExecuteCommand('fixscreen')
                end,
            },
        },
    })

    lib.showContext('nexus_illegal_validation_menu')
end

local function openAdminTestMenu()
    if not isAdmin() then
        notify('No tienes permiso admin.', 'error')
        return
    end

    lib.registerContext({
        id = 'nexus_admin_test_menu',
        title = 'NEXUS Admin pruebas',
        menu = 'nexus_main_menu',
        options = {
            {
                title = 'Dar materiales',
                description = 'Materiales comunes para pruebas de recetas.',
                icon = 'boxes-stacked',
                onSelect = function()
                    giveAdminKit('crafting_materials')
                end,
            },
            {
                title = 'Dar kit sanitario',
                description = 'Vendajes, analgesia y primeros auxilios para probar EMS.',
                icon = 'kit-medical',
                onSelect = function()
                    giveAdminKit('ems_test')
                end,
            },
            {
                title = 'Evaluar paciente cercano',
                description = 'Inicia el flujo fisico y abre la tablet clinica.',
                icon = 'stethoscope',
                onSelect = function()
                    ExecuteCommand('ems')
                end,
            },
            {
                title = 'Validacion ilegal v1',
                description = 'Checklist rapido: banda, territorio, contratos, mercado, crafting, labs y lavado.',
                icon = 'clipboard-check',
                onSelect = openIllegalValidationMenu,
            },
            {
                title = 'Dar blueprints',
                description = 'Planos fisicos para recetas avanzadas.',
                icon = 'scroll',
                onSelect = function()
                    giveAdminKit('blueprints')
                end,
            },
            {
                title = 'Subir crafting +2500',
                description = 'Salto rapido para probar recetas clasificadas.',
                icon = 'angles-up',
                onSelect = function()
                    addCraftingProgress(2500, 15)
                    Wait(250)
                    openProgression()
                end,
            },
            {
                title = 'Abrir mesa publica',
                description = 'Prueba rapida de crafting civil.',
                icon = 'hammer',
                onSelect = function()
                    safeCall('nexus_crafting', 'openCrafting', 'public_workbench')
                end,
            },
            {
                title = 'Abrir mesa ilegal',
                description = 'Prueba de blueprints, riesgo y recetas clasificadas.',
                icon = 'user-secret',
                onSelect = function()
                    safeCall('nexus_crafting', 'openCrafting', 'illegal_bench')
                end,
            },
            {
                title = 'Tablet ilegal',
                description = 'Dashboard clandestino de banda y operaciones.',
                icon = 'tablet-screen-button',
                onSelect = function()
                    safeCall('nexus_tablet', 'openTablet', 'illegal')
                end,
            },
            {
                title = 'Abrir mercado negro',
                description = 'Compra blueprints raros con stock y reputacion.',
                icon = 'mask',
                onSelect = function()
                    ExecuteCommand('blackmarket rancho_contact')
                end,
            },
            {
                title = 'Abrir contratos ilegales',
                description = 'Rutas con riesgo para subir reputacion criminal.',
                icon = 'route',
                onSelect = function()
                    ExecuteCommand('contracts')
                end,
            },
            {
                title = 'Abrir operaciones de banda',
                description = 'Suministros y extorsion territorial para gangs.',
                icon = 'people-carry-box',
                onSelect = function()
                    safeCall('nexus_operations', 'openOperations')
                end,
            },
            {
                title = 'Abrir lavado de dinero',
                description = 'Convierte dinero sucio en cash con comision y riesgo.',
                icon = 'money-bill-transfer',
                onSelect = function()
                    safeCall('nexus_laundering', 'openLaundering')
                end,
            },
            {
                title = 'Editor territorios',
                description = 'Crear zonas, moverlas y eliminar dinamicas.',
                icon = 'map-location-dot',
                onSelect = function()
                    ExecuteCommand('territoryeditor')
                end,
            },
            {
                title = 'Influencia cercana +25',
                description = 'Admin: suma influencia a tu banda en el territorio actual.',
                icon = 'plus',
                onSelect = function()
                    addNearbyInfluence(25)
                end,
            },
            {
                title = 'Influencia cercana +100',
                description = 'Admin: controla rapido el territorio actual para pruebas.',
                icon = 'angles-up',
                onSelect = function()
                    addNearbyInfluence(100)
                end,
            },
            {
                title = 'Influencia por zona +100',
                description = 'Admin: elige territorio exacto y suma influencia a tu banda.',
                icon = 'map-pin',
                onSelect = function()
                    openInfluenceZoneMenu(100)
                end,
            },
            {
                title = 'Influencia por zona +25',
                description = 'Admin: elige territorio exacto y suma influencia moderada.',
                icon = 'map-pin',
                onSelect = function()
                    openInfluenceZoneMenu(25)
                end,
            },
            {
                title = 'Influencia cercana -25',
                description = 'Admin: resta influencia a tu banda en el territorio actual.',
                icon = 'minus',
                onSelect = function()
                    addNearbyInfluence(-25)
                end,
            },
            {
                title = 'Assets de banda',
                description = 'Abre inventario y garaje de safehouse.',
                icon = 'warehouse',
                onSelect = function()
                    safeCall('nexus_gangs', 'openGangAssets')
                end,
            },
            {
                title = 'Reputacion banda +25',
                description = 'Admin: sube reputacion global de tu banda NEXUS.',
                icon = 'ranking-star',
                onSelect = function()
                    addGangReputation(25)
                end,
            },
            {
                title = 'Reputacion banda +100',
                description = 'Admin: desbloqueo rapido de reputacion de banda.',
                icon = 'ranking-star',
                onSelect = function()
                    addGangReputation(100)
                end,
            },
            {
                title = 'Reputacion banda -25',
                description = 'Admin: baja reputacion global de tu banda NEXUS.',
                icon = 'minus',
                onSelect = function()
                    addGangReputation(-25)
                end,
            },
            {
                title = 'Refrescar assets de banda',
                description = 'Recarga safehouses, stash y garajes.',
                icon = 'rotate',
                onSelect = function()
                    ExecuteCommand('gangassetsrefresh')
                end,
            },
            {
                title = 'Copiar posicion para safehouse',
                description = 'Usa esto para ajustar stash/garage de banda.',
                icon = 'location-crosshairs',
                onSelect = function()
                    ExecuteCommand('vec4')
                end,
            },
            {
                title = 'Refrescar graffiti',
                description = 'Recarga marcas territoriales del servidor.',
                icon = 'spray-can',
                onSelect = function()
                    ExecuteCommand('graffitirefresh')
                end,
            },
            {
                title = 'Limpiar graffiti cercano',
                description = 'Admin: elimina la marca territorial mas cercana.',
                icon = 'eraser',
                onSelect = function()
                    ExecuteCommand('graffitiadminclean')
                end,
            },
            {
                title = 'Lanzar airdrop territorial',
                description = 'Admin: crea una caja disputable en una zona.',
                icon = 'parachute-box',
                onSelect = function()
                    ExecuteCommand('territoryairdrop')
                end,
            },
            {
                title = 'Refrescar airdrop',
                description = 'Recarga el estado del airdrop activo.',
                icon = 'rotate',
                onSelect = function()
                    ExecuteCommand('airdroprefresh')
                end,
            },
            {
                title = 'Admin menu QBox',
                description = 'Abre el menu administrativo base.',
                icon = 'shield-halved',
                onSelect = function()
                    TriggerEvent('qbx_admin:client:openMenu')
                end,
            },
            {
                title = 'NoClip',
                description = 'Activa/desactiva vuelo admin.',
                icon = 'person-running',
                onSelect = function()
                    ExecuteCommand('noclip')
                end,
            },
            {
                title = 'Nombres jugadores',
                description = 'Activa/desactiva nombres sobre jugadores.',
                icon = 'users',
                onSelect = function()
                    ExecuteCommand('names')
                end,
            },
            {
                title = 'Blips jugadores',
                description = 'Activa/desactiva blips de jugadores.',
                icon = 'map-location-dot',
                onSelect = function()
                    ExecuteCommand('blips')
                end,
            },
            {
                title = 'Copiar coordenadas vec4',
                description = 'Copia posicion y heading para configs.',
                icon = 'location-crosshairs',
                onSelect = function()
                    ExecuteCommand('vec4')
                end,
            },
            {
                title = 'Crafting editor',
                description = 'Crear, mover, activar/desactivar y listar mesas.',
                icon = 'screwdriver-wrench',
                onSelect = function()
                    ExecuteCommand('crafteditor')
                end,
            },
            {
                title = 'Crafting debug',
                description = 'Estado de mesas cercanas y cache cliente.',
                icon = 'bug',
                onSelect = function()
                    ExecuteCommand('craftdebug')
                end,
            },
            {
                title = 'Recargar mesas',
                description = 'Reconstruye zonas, props y cache de crafting.',
                icon = 'rotate',
                onSelect = function()
                    ExecuteCommand('craftreload')
                end,
            },
            {
                title = 'Dar kit ilegal test',
                description = 'Blueprints y materiales para drill/thermite.',
                icon = 'flask',
                onSelect = function()
                    giveAdminKit('illegal_test')
                end,
            },
            {
                title = 'Subir crafting +500',
                description = 'XP y reputacion para desbloquear recetas.',
                icon = 'chart-line',
                onSelect = function()
                    addCraftingProgress(500, 5)
                    Wait(250)
                    openProgression()
                end,
            },
            {
                title = 'Fix screen / foco',
                description = 'Limpia NUI focus, fade y camaras.',
                icon = 'eye',
                onSelect = function()
                    ExecuteCommand('fixscreen')
                end,
            },
        },
    })

    lib.showContext('nexus_admin_test_menu')
end

local function registerMainMenu()
    local access = getAccess()
    local options = {
        {
            title = 'Telefono',
            description = 'Centro social y apps del jugador.',
            icon = 'mobile-screen',
            onSelect = function()
                safeCall('qbx_phone_aaa', 'openPhone')
            end,
        },
    }

    if access.police then
        options[#options + 1] = {
            title = 'Tablet policial',
            description = 'MDT, dispatch, unidades y casos policiales.',
            icon = 'laptop',
            onSelect = function()
                if GetResourceState('nexus_tablet') ~= 'started' then
                    notify('Tablet NEXUS no iniciada.', 'error')
                    return
                end
                exports.nexus_tablet:openTablet('police')
            end,
        }

        options[#options + 1] = {
            title = 'AIS',
            description = 'Casos, evidencia y herramientas de investigacion.',
            icon = 'magnifying-glass',
            onSelect = function()
                ExecuteCommand('aismdt')
            end,
        }
    end

    if access.ems then
        options[#options + 1] = {
            title = 'Tablet clinica',
            description = 'Evaluacion, tratamiento y preparacion de traslado.',
            icon = 'stethoscope',
            onSelect = function()
                ExecuteCommand('ems')
            end,
        }
    end

    if access.illegal then
        options[#options + 1] = {
            title = 'Tablet ilegal',
            description = 'Red clandestina: banda, contratos, mercado y territorios.',
            icon = 'tablet-screen-button',
            onSelect = function()
                if GetResourceState('nexus_tablet') ~= 'started' then
                    notify('Tablet NEXUS no iniciada.', 'error')
                    return
                end
                exports.nexus_tablet:openTablet('illegal')
            end,
        }

        options[#options + 1] = {
            title = 'Bandas',
            description = 'Miembros, rangos y organizacion criminal.',
            icon = 'users',
            onSelect = function()
                safeCall('nexus_gangs', 'openGangs')
            end,
        }

        options[#options + 1] = {
            title = 'Territorios',
            description = 'Control, influencia y zonas criminales.',
            icon = 'map',
            onSelect = function()
                safeCall('nexus_territories', 'openTerritories')
            end,
        }

        options[#options + 1] = {
            title = 'Operaciones',
            description = 'Suministros, extorsion y actividad de banda.',
            icon = 'people-carry-box',
            onSelect = function()
                safeCall('nexus_operations', 'openOperations')
            end,
        }
    end

    options[#options + 1] = {
        title = 'Fichas de item',
        description = 'Pruebas de UI contextual por tipo de item.',
        icon = 'id-card',
        onSelect = openItemMenu,
    }

    options[#options + 1] = {
        title = 'Crafting',
        description = 'Mesa modular conectada a XP crafting.',
        icon = 'hammer',
        onSelect = function()
            safeCall('nexus_crafting', 'openCrafting', 'public_workbench')
        end,
    }

    options[#options + 1] = {
        title = 'Progresion',
        description = 'Reputacion, niveles y dominios del personaje.',
        icon = 'chart-line',
        onSelect = openProgression,
    }

    options[#options + 1] = {
        title = 'Rescatar pantalla',
        description = 'Limpia foco NUI, camaras y fade.',
        icon = 'eye',
        onSelect = function()
            ExecuteCommand('fixscreen')
        end,
    }

    if access.admin then
        options[#options + 1] = {
            title = 'Admin pruebas',
            description = 'Herramientas rapidas para testear sistemas NEXUS.',
            icon = 'shield-halved',
            onSelect = openAdminTestMenu,
        }
    end

    lib.registerContext({
        id = 'nexus_main_menu',
        title = 'NEXUS',
        options = options,
    })
end

local function openMenu()
    registerMainMenu()
    lib.showContext('nexus_main_menu')
end

exports('openMenu', openMenu)

RegisterCommand(NexusMenuConfig.command, openMenu, false)
RegisterKeyMapping(NexusMenuConfig.command, 'Abrir menu NEXUS', 'keyboard', NexusMenuConfig.key)

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Wait(500)
    registerMainMenu()
    print('[nexus_menu] menu central cargado')
end)
