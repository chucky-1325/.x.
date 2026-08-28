NexusMenuConfig = {
    command = 'nexus',
    key = 'F5',

    admin = {
        -- ace ya no se usa -- el acceso admin ahora lo decide nexus_permissions
        -- (nexus_menu.admin_access / give_kit / grant_progression). El backdoor
        -- de identifiers hardcodeados que existia aqui fue retirado, sin
        -- sustituto.
        ace = 'admin',
        kits = {
            crafting_materials = {
                label = 'Materiales crafting',
                items = {
                    { item = 'plastic', count = 25 },
                    { item = 'rubber', count = 15 },
                    { item = 'metalscrap', count = 25 },
                    { item = 'steel', count = 15 },
                    { item = 'iron', count = 15 },
                    { item = 'aluminum', count = 15 },
                    { item = 'glass', count = 10 },
                    { item = 'electronickit', count = 5 },
                },
            },
            blueprints = {
                label = 'Blueprints crafting',
                items = {
                    { item = 'blueprint_lockpick', count = 1 },
                    { item = 'blueprint_drill', count = 1 },
                    { item = 'blueprint_thermite', count = 1 },
                    { item = 'blueprint_advanced_repairkit', count = 1 },
                },
            },
            illegal_test = {
                label = 'Kit ilegal test',
                items = {
                    { item = 'blueprint_lockpick', count = 1 },
                    { item = 'blueprint_drill', count = 1 },
                    { item = 'blueprint_thermite', count = 1 },
                    { item = 'metalscrap', count = 40 },
                    { item = 'steel', count = 25 },
                    { item = 'aluminum', count = 20 },
                    { item = 'plastic', count = 20 },
                    { item = 'electronickit', count = 5 },
                    { item = 'nexus_spraycan', count = 5 },
                    { item = 'nexus_graffiti_remover', count = 3 },
                    { item = 'black_money', count = 10000 },
                },
            },
            illegal_loop_v1 = {
                label = 'Kit validacion ilegal v1',
                items = {
                    { item = 'blueprint_lockpick', count = 1 },
                    { item = 'blueprint_drill', count = 1 },
                    { item = 'blueprint_thermite', count = 1 },
                    { item = 'blueprint_advanced_repairkit', count = 1 },
                    { item = 'metalscrap', count = 60 },
                    { item = 'steel', count = 35 },
                    { item = 'aluminum', count = 25 },
                    { item = 'plastic', count = 45 },
                    { item = 'rubber', count = 20 },
                    { item = 'glass', count = 20 },
                    { item = 'iron', count = 20 },
                    { item = 'electronickit', count = 8 },
                    { item = 'nexus_spraycan', count = 5 },
                    { item = 'nexus_graffiti_remover', count = 3 },
                    { item = 'weed_skunk', count = 12 },
                    { item = 'empty_weed_bag', count = 8 },
                    { item = 'coke_small_brick', count = 2 },
                    { item = 'black_money', count = 15000 },
                },
            },
            ems_test = {
                label = 'Kit sanitario test',
                items = {
                    { item = 'bandage', count = 10 },
                    { item = 'painkillers', count = 6 },
                    { item = 'firstaid', count = 4 },
                    { item = 'ifaks', count = 2 },
                },
            },
        },
    },

    access = {
        policeJobs = {
            police = true,
            sheriff = true,
            state = true,
            ranger = true,
            detective = true,
            forensic = true,
            internal_affairs = true,
        },
        emsJobs = {
            ambulance = true,
            ems = true,
            doctor = true,
        },
    },

    itemDemos = {
        { label = 'Arma', kind = 'weapon' },
        { label = 'Comida', kind = 'food' },
        { label = 'Medicamento', kind = 'medication' },
        { label = 'Documento', kind = 'document' },
        { label = 'Llave', kind = 'key' },
        { label = 'Evidencia', kind = 'evidence' },
        { label = 'Ilegal', kind = 'illegal' },
    },
}
