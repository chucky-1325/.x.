NexusBridgeConfig = {
    debug = false,

    rateLimits = {
        default = { window = 10000, limit = 8 },
        tablet = { window = 5000, limit = 6 },
        crafting = { window = 7000, limit = 2 },
        admin = { window = 3000, limit = 10 },
    },

    timedActions = {
        minimumDuration = 500,
        maximumDuration = 120000,
        graceMs = 60000,
        earlyToleranceMs = 250,
    },

    permissionGroups = {
        police = {
            jobTypes = { leo = true },
            jobs = {
                police = 0,
                bcso = 0,
                sasp = 0,
                sheriff = 0,
                state = 0,
                ranger = 0,
                detective = 0,
                forensic = 0,
                internal_affairs = 0,
            },
            gangs = {},
        },
        ems = { jobs = { ambulance = 0 }, gangs = {} },
        gov = { jobs = { judge = 0, lawyer = 0 }, gangs = {} },
        business = { jobs = {}, gangs = {} },
        illegal = { jobs = {}, gangs = { ballas = 0, vagos = 0, families = 0 } },
    },
}
