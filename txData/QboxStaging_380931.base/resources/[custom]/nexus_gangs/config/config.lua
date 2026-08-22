NexusGangsConfig = {
    debug = false,
    command = 'gangs',
    adminAce = 'admin',
    rateLimitBucket = 'default',

    defaultColor = '#22d3ee',
    defaultReputation = 0,
    syncQboxRuntime = true,

    assets = {
        command = 'gangassets',
        interactDistance = 2.0,
        drawDistance = 18.0,
        stash = {
            enabled = true,
            slots = 80,
            weight = 250000,
            minRank = 0,
        },
        garage = {
            enabled = true,
            minRank = 0,
            platePrefix = 'GANG',
            maxPerModel = 2,
            vehicles = {
                { label = 'Sultan clasico', model = 'sultan', minRank = 0 },
                { label = 'Blista compacto', model = 'blista', minRank = 0 },
                { label = 'Burrito de suministros', model = 'burrito3', minRank = 1 },
                { label = 'Caracara tactico', model = 'caracara2', minRank = 2 },
            },
        },
        locations = {
            {
                id = 'rancho_safehouse',
                label = 'Safehouse Rancho',
                gangs = { 'vagos' },
                stash = vec3(443.72, -1842.72, 27.82),
                garage = vec4(438.74, -1840.10, 27.66, 136.0),
            },
            {
                id = 'davis_safehouse',
                label = 'Safehouse Davis',
                gangs = { 'ballas', 'families' },
                stash = vec3(105.72, -1939.11, 20.80),
                garage = vec4(94.42, -1936.34, 20.76, 45.0),
            },
        },
    },

    ranks = {
        [0] = {
            label = 'Asociado',
            permissions = {},
        },
        [1] = {
            label = 'Soldado',
            permissions = {
                invite = true,
            },
        },
        [2] = {
            label = 'Teniente',
            permissions = {
                invite = true,
                kick = true,
                promote = true,
            },
        },
        [3] = {
            label = 'Lider',
            isBoss = true,
            permissions = {
                invite = true,
                kick = true,
                promote = true,
                manage = true,
            },
        },
    },
}
