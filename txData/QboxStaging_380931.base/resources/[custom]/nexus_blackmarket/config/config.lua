NexusBlackmarketConfig = {
    debug = false,
    command = 'blackmarket',
    nearestCommand = 'blackmarketnear',
    adminAce = 'admin',
    adminIdentifiers = {
        ['fivem:11477662'] = true,
    },
    rateLimitBucket = 'default',
    heat = {
        enabled = true,
        decayIntervalMinutes = 10,
        decayAmount = 3,
        maxHeat = 100,
        pricePerHeatPercent = 0.75,
        maxPriceMultiplier = 1.75,
        policeAlertBaseChance = 5,
        policeAlertPerHeat = 0.35,
        policeJobs = { police = true, bcso = true, sasp = true },
    },
    reputationDiscount = {
        enabled = true,
        minReputation = 5,
        percentPerReputation = 0.6,
        maxDiscountPercent = 18,
    },

    access = {
        requireGangOrCriminalRep = true,
        minimumCriminalReputation = 2,
    },

    worldUi = {
        enabled = true,
        drawDistance = 12.0,
        interactDistance = 2.5,
        markerScale = vector3(0.55, 0.55, 0.55),
        color = { r = 160, g = 20, b = 255, a = 150 },
    },

    locations = {
        rancho_contact = {
            label = 'Contacto clandestino',
            coords = vector3(484.14, -1312.48, 29.22),
            heading = 115.0,
            scenario = 'WORLD_HUMAN_SMOKING',
            model = 'g_m_y_mexgoon_03',
            minCriminalReputation = 2,
        },
        sandy_contact = {
            label = 'Proveedor del desierto',
            coords = vector3(1394.64, 3604.22, 34.98),
            heading = 205.0,
            scenario = 'WORLD_HUMAN_LEANING',
            model = 'g_m_m_chigoon_02',
            minCriminalReputation = 6,
        },
    },

    catalog = {
        blueprint_lockpick = {
            label = 'Plano: ganzua basica',
            item = 'blueprint_lockpick',
            price = 1500,
            moneyType = 'cash',
            stock = 8,
            required = { criminalReputation = 0 },
            heat = 5,
        },
        blueprint_advanced_repairkit = {
            label = 'Plano: kit avanzado',
            item = 'blueprint_advanced_repairkit',
            price = 3500,
            moneyType = 'cash',
            stock = 4,
            required = { craftingLevel = 4, craftingReputation = 3 },
            heat = 0,
        },
        blueprint_drill = {
            label = 'Plano: taladro preparado',
            item = 'blueprint_drill',
            price = 8500,
            moneyType = 'cash',
            stock = 2,
            required = { criminalReputation = 8, craftingLevel = 5 },
            heat = 20,
        },
        blueprint_thermite = {
            label = 'Plano: thermite',
            item = 'blueprint_thermite',
            price = 12500,
            moneyType = 'cash',
            stock = 1,
            required = { criminalReputation = 10, craftingLevel = 6 },
            heat = 35,
        },
    },
}
