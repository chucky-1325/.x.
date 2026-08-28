NexusPermissionsConfig = {
    -- Vacia hasta que se migre realmente un recurso existente.
    SensitiveResourceWhitelist = {},

    -- Catalogo de permisos granulares por recurso/accion (Fase 0). Cada
    -- clave es el string exacto que los recursos consumidores pasaran a
    -- hasPermission/hasAnyPermission. Solo los permisos listados aqui pueden
    -- devolver true -- cualquier otro string falla cerrado, aunque algun rol
    -- lo tenga otorgado en nexus_permission_role_grants. Solo qbx_mdt.admin_access
    -- y handling_lab.use tienen ya un gate real consumiendolos (piloto); el
    -- resto queda definido para las fases siguientes del roadmap, sin ningun
    -- gate ACE migrado todavia.
    PermissionCatalog = {
        ['qbx_mdt.admin_access'] = { resource = 'qbx_mdt', label = 'Acceso administrativo a MDT sin ser policia' },
        ['handling_lab.use'] = { resource = 'handling_lab', label = 'Usar los comandos del laboratorio de handling' },
        ['nexus_dispatch.admin_access'] = { resource = 'nexus_dispatch', label = 'Acceso administrativo a dispatch sin ser policia' },
        ['nexus_tablet.admin_access'] = { resource = 'nexus_tablet', label = 'Bypass de acceso ilegal y restriccion de apps en el tablet' },
        ['nexus_crafting.editor_manage'] = { resource = 'nexus_crafting', label = 'Crear, editar y eliminar mesas de crafting' },
        ['nexus_contracts.quarantine_admin'] = { resource = 'nexus_contracts', label = 'Listar y recuperar cuarentenas de craft y lot-incidents' },
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
