NexusTerritoriesConfig = {
    debug = false,
    command = 'territorios',
    editorCommand = 'territoryeditor',
    rateLimitBucket = 'default',
    adminAce = 'admin',

    control = {
        minimumInfluence = 25,
        contestedGap = 10,
        maxInfluence = 100,
        independentKey = 'independent',
    },

    decay = {
        enabled = true,
        intervalMinutes = 15,
        amount = 2,
    },

    benefits = {
        marketDiscountPercent = 12,
        contractCooldownReductionPercent = 20,
        influenceBonusPercent = 25,
        rivalHeatBonusPercent = 25,
        rivalAlertBonusPercent = 10,
    },

    editor = {
        defaultRadius = 160.0,
        minimumRadius = 40.0,
        maximumRadius = 500.0,
    },

    graffiti = {
        enabled = true,
        sprayItem = 'nexus_spraycan',
        removerItem = 'nexus_graffiti_remover',
        sprayInfluence = 5,
        removeInfluence = -4,
        maxPerGangZone = 4,
        interactDistance = 2.5,
        maxSprayDistance = 6.0,
        wallNormalMaxZ = 0.8,
        drawDistance = 45.0,
        textDrawDistance = 18.0,
        textScale = 0.78,
        logoSize = 1.15,
        logoDepthOffset = 0.035,
        sprayDuration = 6000,
        removeDuration = 5000,
    },

    airdrop = {
        enabled = true,
        command = 'territoryairdrop',
        adminOnly = true,
        activeSeconds = 900,
        cooldownSeconds = 300,
        captureDistance = 3.0,
        drawDistance = 90.0,
        captureDuration = 12000,
        influenceReward = 12,
        model = 'prop_box_wood05a',
        rewards = {
            { item = 'nexus_spraycan', count = 2 },
            { item = 'nexus_graffiti_remover', count = 1 },
            { item = 'lockpick', count = 2 },
            { item = 'metalscrap', count = 8 },
            { item = 'plastic', count = 8 },
        },
    },

    zones = {
        rancho = {
            label = 'Rancho',
            coords = vector3(443.72, -1842.72, 27.82),
            radius = 260.0,
            heatMultiplier = 1.0,
        },
        sandy = {
            label = 'Sandy Shores',
            coords = vector3(1394.64, 3604.22, 34.98),
            radius = 220.0,
            heatMultiplier = 1.15,
        },
        davis = {
            label = 'Davis',
            coords = vector3(119.02, -1949.84, 20.72),
            radius = 170.0,
            heatMultiplier = 1.05,
        },
        vespucci = {
            label = 'Vespucci',
            coords = vector3(-1156.27, -1569.31, 4.43),
            radius = 180.0,
            heatMultiplier = 1.2,
        },
    },
}
