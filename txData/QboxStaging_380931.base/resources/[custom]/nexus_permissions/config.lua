NexusPermissionsConfig = {
    -- Vacia hasta que se migre realmente un recurso existente.
    SensitiveResourceWhitelist = {},

    -- Catalogo de permisos granulares por recurso/accion (Fase 0). Cada
    -- clave es el string exacto que los recursos consumidores pasaran a
    -- hasPermission/hasAnyPermission. Solo los permisos listados aqui pueden
    -- devolver true -- cualquier otro string falla cerrado, aunque algun rol
    -- lo tenga otorgado en nexus_permission_role_grants. qbx_mdt.admin_access,
    -- handling_lab.use, nexus_dispatch.admin_access y los dos nexus_tablet.*
    -- de abajo ya tienen gate real consumiendolos (Fase 2); el resto queda
    -- definido para las fases siguientes del roadmap, sin gate ACE migrado.
    --
    -- nexus_tablet: dos bypasses administrativos distintos en el codigo
    -- (acceso ilegal vs restriccion general de apps) -- permisos separados
    -- a proposito, uno por bypass real, no un unico "admin_access" generico.
    --
    -- nexus_crafting: mismo criterio -- editor_view (solo lectura: listar,
    -- abrir una mesa desactivada para inspeccionarla) separado de
    -- editor_mutate (crea/guarda/mueve/activa/borra). El bypass de mesa
    -- desactivada en getStation nunca permite craftear -- cada punto real
    -- de crafteo/reserva sigue rechazando station.enabled==false sin
    -- excepcion, por eso ese bypass cae del lado de "view", no "mutate".
    --
    -- nexus_contracts: un permiso de vista (quarantine_view, cubre ambos
    -- listados) mas DOS permisos de mutacion independientes -- uno por tipo
    -- de recuperacion (craft_quarantine_recover / lot_incident_recover) --
    -- para poder delegar cada uno por separado en el futuro sin acoplarlos.
    --
    -- Fase 4: nexus_blackmarket, nexus_ems, nexus_labs -- cada bypass real
    -- separado (no un unico admin_access por recurso). nexus_labs.canUseLab
    -- bypasseaba 4 requisitos distintos con un solo booleano -- se separaron
    -- en progression_bypass (rango + reputacion) y territory_bypass (zona
    -- rival + influencia), ademas de sabotage_bypass, ya de por si distinto.
    -- nexus_ems.grade_override queda deliberadamente separado de
    -- medic_access_bypass -- nunca se combinan en un solo permiso de acceso.
    -- El backdoor NexusBlackmarketConfig.adminIdentifiers se retiro en esta
    -- migracion: quien necesite ese acceso ahora recibe un rol explicito de
    -- nexus_permissions, sin ningun identifier hardcodeado sustituto.
    --
    -- Fase 5: nexus_territories.editor_manage (generico) se separa en
    -- editor_view (solo ver/abrir el editor -- getEditorZones + el comando
    -- /territoryeditor, ninguno muta nada) y dos permisos de mutacion
    -- independientes: zone_save y zone_delete -- separados a proposito
    -- porque eliminar una zona dinamica es mas destructivo (cascada sobre
    -- influencia) que guardarla/crearla. graffiti_admin, influence_grant y
    -- airdrop_admin ya mapeaban 1:1 a una accion real desde la semilla de
    -- Fase 0 -- mantienen su nombre, solo dejan de ser placeholders.
    --
    -- Fase 6a: nexus_menu.admin_access/give_kit/grant_progression ya
    -- existian con su nombre final desde la semilla de Fase 0 -- ningun
    -- nodo nuevo, solo dejan de ser placeholders. Se retira el backdoor
    -- de identifier hardcodeado (mismo fivem:11477662 que blackmarket, sin
    -- sustituto). admin_access cubre tanto el flag admin de getAccess como
    -- sus 3 bypasses internos (police/ems/illegal) y el panel de
    -- diagnostico getIllegalValidationStatus -- ninguno muta datos.
    --
    -- Fase 6b: nexus_gangs.admin_manage (generico) se separa en 4 nodos.
    -- IMPORTANTE: nexus_gangs tiene su propio sistema interno de permisos
    -- por rango de banda (rank.isBoss / rank.permissions), que NO se toca
    -- -- estos 4 permisos solo cubren el bypass GLOBAL de administrador
    -- sobre ese sistema, no lo reemplazan. member_manage_override cubre
    -- tanto el bypass del permiso interno como el del tope de rango dentro
    -- de canManageTarget (setRank/kick via menu, misma banda) -- son el
    -- mismo bypass real aplicado a dos checks del mismo flujo. Separado de
    -- gang_member_admin (gangadd/gangremove: comandos de consola sin
    -- restriccion de banda propia, mismo tipo de accion pero otro camino
    -- de invocacion, elegido explicitamente separado). gang_create es
    -- crear una entidad nueva, distinto de gestionar membresia existente.
    PermissionCatalog = {
        ['qbx_mdt.admin_access'] = { resource = 'qbx_mdt', label = 'Acceso administrativo a MDT sin ser policia' },
        ['handling_lab.use'] = { resource = 'handling_lab', label = 'Usar los comandos del laboratorio de handling' },
        ['nexus_dispatch.admin_access'] = { resource = 'nexus_dispatch', label = 'Acceso administrativo a dispatch sin ser policia' },
        ['nexus_tablet.bypass_illegal_access'] = { resource = 'nexus_tablet', label = 'Bypass de requisitos de banda/reputacion para acceso ilegal en el tablet' },
        ['nexus_tablet.bypass_app_restriction'] = { resource = 'nexus_tablet', label = 'Bypass de restriccion de acceso a cualquier app del tablet' },
        ['nexus_crafting.editor_view'] = { resource = 'nexus_crafting', label = 'Listar mesas en el editor y abrir mesas desactivadas para inspeccionarlas (no craftear)' },
        ['nexus_crafting.editor_mutate'] = { resource = 'nexus_crafting', label = 'Crear, guardar, mover, activar/desactivar y eliminar mesas de crafting' },
        ['nexus_contracts.quarantine_view'] = { resource = 'nexus_contracts', label = 'Listar cuarentenas de craft y lot-incidents (solo lectura)' },
        ['nexus_contracts.craft_quarantine_recover'] = { resource = 'nexus_contracts', label = 'Ejecutar la recuperacion de una cuarentena de craft' },
        ['nexus_contracts.lot_incident_recover'] = { resource = 'nexus_contracts', label = 'Ejecutar la recuperacion de un lot-incident' },
        ['nexus_blackmarket.access_bypass'] = { resource = 'nexus_blackmarket', label = 'Acceso al mercado y a una ubicacion sin banda/reputacion' },
        ['nexus_blackmarket.distance_bypass'] = { resource = 'nexus_blackmarket', label = 'Bypass de requisito de distancia a una ubicacion' },
        ['nexus_ems.medic_access_bypass'] = { resource = 'nexus_ems', label = 'Tratar a un admin como medico valido sin serlo' },
        ['nexus_ems.grade_override'] = { resource = 'nexus_ems', label = 'Override de grado a 99 para el minGrade de una accion medica' },
        ['nexus_labs.progression_bypass'] = { resource = 'nexus_labs', label = 'Bypass de rango de banda y reputacion criminal para usar un lab' },
        ['nexus_labs.territory_bypass'] = { resource = 'nexus_labs', label = 'Bypass de bloqueo por zona rival y minimo de influencia para usar un lab' },
        ['nexus_labs.sabotage_bypass'] = { resource = 'nexus_labs', label = 'Bypass de reputacion criminal para sabotear (el rango de banda nunca tiene bypass)' },
        ['nexus_territories.editor_view'] = { resource = 'nexus_territories', label = 'Ver y abrir el editor de zonas de territorio (solo lectura)' },
        ['nexus_territories.zone_save'] = { resource = 'nexus_territories', label = 'Crear/guardar una zona dinamica de territorio' },
        ['nexus_territories.zone_delete'] = { resource = 'nexus_territories', label = 'Eliminar una zona dinamica de territorio' },
        ['nexus_territories.graffiti_admin'] = { resource = 'nexus_territories', label = 'Limpiar graffiti como admin' },
        ['nexus_territories.influence_grant'] = { resource = 'nexus_territories', label = 'Otorgar influencia de banda manualmente' },
        ['nexus_territories.airdrop_admin'] = { resource = 'nexus_territories', label = 'Lanzar airdrops fuera de las condiciones normales' },
        ['nexus_gangs.gang_create'] = { resource = 'nexus_gangs', label = 'Crear una banda nueva' },
        ['nexus_gangs.member_manage_override'] = { resource = 'nexus_gangs', label = 'Bypass del permiso interno de banda y del tope de rango para ascender/expulsar miembros' },
        ['nexus_gangs.gang_member_admin'] = { resource = 'nexus_gangs', label = 'Asignar o quitar a cualquier jugador de cualquier banda via comandos de consola' },
        ['nexus_gangs.reputation_grant'] = { resource = 'nexus_gangs', label = 'Modificar reputacion de banda manualmente' },
        ['nexus_menu.admin_access'] = { resource = 'nexus_menu', label = 'Acceso al panel admin del menu' },
        ['nexus_menu.give_kit'] = { resource = 'nexus_menu', label = 'Entregar kits administrativos de items' },
        ['nexus_menu.grant_progression'] = { resource = 'nexus_menu', label = 'Otorgar XP/reputacion de progresion manualmente' },
    },
}
