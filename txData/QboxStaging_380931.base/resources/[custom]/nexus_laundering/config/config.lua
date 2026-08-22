NexusLaunderingConfig = {
    command = 'launder',
    rateLimitBucket = 'laundering',
    interactDistance = 3.0,
    dirtyItem = 'black_money',

    limits = {
        minAmount = 250,
        maxAmount = 15000,
        cooldownSeconds = 900,
    },

    policeJobs = { police = true, bcso = true, sasp = true },

    locations = {
        rancho_carwash = {
            label = 'Lavado Rancho',
            zoneId = 'rancho',
            coords = vector4(479.24, -1888.88, 26.09, 299.0),
            commissionPercent = 22,
            baseRisk = 14,
            minCriminalReputation = 2,
            requiredGang = false,
            model = 's_m_m_highsec_01',
            scenario = 'WORLD_HUMAN_CLIPBOARD',
        },
        vespucci_front = {
            label = 'Fachada Vespucci',
            zoneId = 'vespucci',
            coords = vector4(-1161.39, -1566.74, 4.43, 125.0),
            commissionPercent = 18,
            baseRisk = 22,
            minCriminalReputation = 5,
            requiredGang = true,
            model = 'a_m_m_soucent_03',
            scenario = 'WORLD_HUMAN_SMOKING',
        },
    },
}
