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
        ['nexus_blackmarket.admin_access'] = { resource = 'nexus_blackmarket', label = 'Acceso administrativo al mercado negro' },
        ['nexus_ems.admin_access'] = { resource = 'nexus_ems', label = 'Acceso administrativo EMS (grado elevado)' },
        ['nexus_labs.admin_access'] = { resource = 'nexus_labs', label = 'Bypass de rango/reputacion para labs y sabotaje' },
        ['nexus_territories.editor_manage'] = { resource = 'nexus_territories', label = 'Ver, guardar y eliminar zonas de territorio' },
        ['nexus_territories.graffiti_admin'] = { resource = 'nexus_territories', label = 'Limpiar graffiti como admin' },
        ['nexus_territories.influence_grant'] = { resource = 'nexus_territories', label = 'Otorgar influencia de banda manualmente' },
        ['nexus_territories.airdrop_admin'] = { resource = 'nexus_territories', label = 'Lanzar airdrops fuera de las condiciones normales' },
        ['nexus_gangs.admin_manage'] = { resource = 'nexus_gangs', label = 'Crear/asignar/quitar miembros de banda via comandos' },
        ['nexus_menu.admin_access'] = { resource = 'nexus_menu', label = 'Acceso al panel admin del menu' },
        ['nexus_menu.give_kit'] = { resource = 'nexus_menu', label = 'Entregar kits administrativos de items' },
        ['nexus_menu.grant_progression'] = { resource = 'nexus_menu', label = 'Otorgar XP/reputacion de progresion manualmente' },
    },
}
