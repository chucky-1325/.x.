NexusOperationsConfig = {
    debug = false,
    command = 'operations',
    rateLimitBucket = 'default',
    interactDistance = 4.0,
    abandonCooldownSeconds = 300,

    -- Usado solo por server/security_fallback.lua cuando nexus_bridge no esta
    -- corriendo. Valores en paridad con nexus_bridge/config/config.lua para que
    -- el fallback y el modulo compartido se comporten igual.
    security = {
        rateLimits = {
            default = { window = 10000, limit = 8 },
        },
        timedActions = {
            minimumDuration = 500,
            maximumDuration = 120000,
            graceMs = 60000,
            earlyToleranceMs = 250,
        },
    },

    policeJobs = { police = true, bcso = true, sasp = true },

    actionDurations = {
        pickup = 6500,
        deliver = 8000,
        extort = 9000,
    },
    sceneCore = {
        enabled = true,
        pickup = 'package_pickup',
        dropoff = 'package_delivery',
        extort = 'extortion_collection',
    },

    supplyPackageItem = 'nexus_contract_package',

    npcDefaults = {
        supply = {
            model = 'g_m_y_mexgoon_02',
            scenario = 'WORLD_HUMAN_SMOKING',
        },
        extortion = {
            model = 'a_m_m_business_01',
            scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
        },
    },

    operations = {
        rancho_supply = {
            label = 'Suministros para Rancho',
            type = 'supply',
            description = 'Mueve componentes discretos hasta la safehouse. La recompensa cae en el stash de banda.',
            requiredRank = 0,
            minCriminalReputation = 0,
            zoneId = 'rancho',
            pickup = vector3(484.14, -1312.48, 29.22),
            dropoff = vector3(443.72, -1842.72, 27.82),
            routes = {
                {
                    label = 'La Mesa - Rancho',
                    pickup = vector4(484.14, -1312.48, 29.22, 292.0),
                    dropoff = vector4(443.72, -1842.72, 27.82, 48.0),
                    riskModifier = 0,
                    influenceModifier = 0,
                    npc = { model = 'g_m_y_mexgoon_02', scenario = 'WORLD_HUMAN_SMOKING' },
                },
                {
                    label = 'Cypress - Rancho',
                    pickup = vector4(866.43, -1638.55, 30.34, 91.0),
                    dropoff = vector4(443.72, -1842.72, 27.82, 48.0),
                    riskModifier = 6,
                    influenceModifier = 2,
                    npc = { model = 'g_m_y_mexgoon_03', scenario = 'WORLD_HUMAN_CLIPBOARD' },
                },
                {
                    label = 'Murrieta - Rancho',
                    pickup = vector4(1127.75, -1304.32, 34.73, 176.0),
                    dropoff = vector4(443.72, -1842.72, 27.82, 48.0),
                    riskModifier = 10,
                    influenceModifier = 3,
                    npc = { model = 'g_m_m_chicold_01', scenario = 'WORLD_HUMAN_SMOKING' },
                },
            },
            durationSeconds = 1200,
            cooldownSeconds = 1800,
            policeAlertChance = 12,
            influence = 6,
            rewards = {
                stash = {
                    { item = 'metalscrap', count = 12 },
                    { item = 'plastic', count = 10 },
                    { item = 'nexus_spraycan', count = 1 },
                },
                player = {
                    cash = 650,
                    xp = 130,
                    reputation = 2,
                },
            },
        },
        davis_extortion = {
            label = 'Cobro de proteccion Davis',
            type = 'extortion',
            description = 'Presiona un negocio local. Paga rapido, pero sube el riesgo de respuesta policial.',
            requiredRank = 1,
            minCriminalReputation = 3,
            zoneId = 'davis',
            point = vector3(105.72, -1939.11, 20.80),
            routes = {
                {
                    label = 'Davis local',
                    point = vector4(105.72, -1939.11, 20.80, 318.0),
                    riskModifier = 0,
                    influenceModifier = 0,
                    npc = { model = 'a_m_m_business_01', scenario = 'WORLD_HUMAN_STAND_IMPATIENT' },
                },
                {
                    label = 'Forum Drive tienda',
                    point = vector4(-48.24, -1757.74, 29.42, 48.0),
                    riskModifier = 8,
                    influenceModifier = 2,
                    npc = { model = 'a_m_m_eastsa_02', scenario = 'WORLD_HUMAN_STAND_MOBILE' },
                },
                {
                    label = 'Carson deposito',
                    point = vector4(361.04, -2042.77, 22.35, 141.0),
                    riskModifier = 12,
                    influenceModifier = 3,
                    npc = { model = 'a_m_y_business_02', scenario = 'WORLD_HUMAN_CLIPBOARD' },
                },
            },
            durationSeconds = 900,
            cooldownSeconds = 2400,
            policeAlertChance = 24,
            influence = 8,
            rewards = {
                player = {
                    cash = 1800,
                    xp = 190,
                    reputation = 3,
                },
            },
        },
    },
}
