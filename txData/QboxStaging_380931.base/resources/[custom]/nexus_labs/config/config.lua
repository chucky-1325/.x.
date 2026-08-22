NexusLabsConfig = {
    command = 'labs',
    rateLimitBucket = 'labs',
    interactDistance = 3.0,
    adminAce = 'admin',

    policeJobs = { police = true, bcso = true, sasp = true },

    sceneCore = {
        enabled = true,
        actions = {
            production = {
                default = 'lab_processing',
                meth = 'lab_chemistry',
                packaging = 'lab_packaging',
                weed = 'lab_processing',
            },
            upgrade = 'lab_maintenance',
            repair = 'lab_maintenance',
            sabotage = 'lab_sabotage',
        },
    },

    production = {
        durationMs = 12000,
        cooldownSeconds = 900,
        minimumInfluence = 15,
        allowOwnerOnly = true,
        depositToGangStash = true,
    },

    upgrades = {
        enabled = true,
        durationMs = 10000,
        maxLevel = 3,
        durationReductionPerLevel = 0.10,
        riskReductionPerLevel = 4,
        outputBonusPerLevel = 0.20,
        conditionDecayPerRun = 8,
        levels = {
            [2] = {
                cash = 4500,
                materials = {
                    { item = 'metalscrap', count = 18 },
                    { item = 'electronickit', count = 2 },
                    { item = 'glass', count = 6 },
                },
            },
            [3] = {
                cash = 9500,
                materials = {
                    { item = 'steel', count = 20 },
                    { item = 'electronickit', count = 4 },
                    { item = 'plastic', count = 14 },
                },
            },
        },
    },

    maintenance = {
        enabled = true,
        durationMs = 7000,
        repairAmount = 35,
        cash = 1200,
        materials = {
            { item = 'metalscrap', count = 8 },
            { item = 'plastic', count = 6 },
            { item = 'electronickit', count = 1 },
        },
    },

    sabotage = {
        enabled = true,
        requiredRank = 1,
        minCriminalReputation = 3,
        damage = 35,
        durationMs = 9000,
        policeAlertChance = 35,
        influenceReward = 8,
        materials = {
            { item = 'lockpick', count = 1 },
            { item = 'plastic', count = 3 },
        },
    },

    labs = {
        rancho_meth = {
            label = 'Laboratorio Rancho',
            type = 'meth',
            zoneId = 'rancho',
            coords = vector4(443.72, -1842.72, 27.82, 48.0),
            model = 'prop_tool_bench02',
            requiredRank = 1,
            minCriminalReputation = 4,
            baseRisk = 22,
            influenceReward = 5,
            recipe = {
                label = 'Cristal sintetico',
                inputs = {
                    { item = 'plastic', count = 4 },
                    { item = 'glass', count = 2 },
                    { item = 'metalscrap', count = 2 },
                },
                outputs = {
                    { item = 'meth', count = 6 },
                },
                xp = 160,
                reputation = 3,
            },
        },
        davis_packaging = {
            label = 'Mesa de empaquetado Davis',
            type = 'packaging',
            zoneId = 'davis',
            coords = vector4(105.72, -1939.11, 20.80, 318.0),
            model = 'prop_table_03',
            requiredRank = 1,
            minCriminalReputation = 3,
            baseRisk = 18,
            influenceReward = 4,
            recipe = {
                label = 'Paquetes discretos',
                inputs = {
                    { item = 'coke_small_brick', count = 1 },
                    { item = 'plastic', count = 2 },
                },
                outputs = {
                    { item = 'cokebaggy', count = 8 },
                },
                xp = 120,
                reputation = 2,
            },
        },
        sandy_grow = {
            label = 'Secadero Sandy',
            type = 'weed',
            zoneId = 'sandy',
            coords = vector4(1391.84, 3606.28, 34.98, 199.0),
            model = 'bkr_prop_weed_table_01a',
            requiredRank = 0,
            minCriminalReputation = 1,
            baseRisk = 12,
            influenceReward = 3,
            recipe = {
                label = 'Ladrillo vegetal',
                inputs = {
                    { item = 'weed_skunk', count = 8 },
                    { item = 'empty_weed_bag', count = 4 },
                },
                outputs = {
                    { item = 'weed_brick', count = 1 },
                },
                xp = 90,
                reputation = 1,
            },
        },
    },
}
