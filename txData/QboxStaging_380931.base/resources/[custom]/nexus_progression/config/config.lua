NexusProgressionConfig = {
    debug = false,

    domains = {
        civil = { label = 'Ciudadano', icon = 'user', color = '#38bdf8' },
        police = { label = 'Policia', icon = 'shield', color = '#60a5fa' },
        ems = { label = 'EMS', icon = 'heart-pulse', color = '#2dd4bf' },
        criminal = { label = 'Criminal', icon = 'skull', color = '#ef4444' },
        business = { label = 'Empresas', icon = 'briefcase', color = '#22c55e' },
        crafting = { label = 'Crafting', icon = 'wrench', color = '#f59e0b' },
    },

    maxLevel = 100,
    xpBase = 1000,
    xpGrowth = 1.18,

    testCommandEnabled = false,

    activity = {
        enabled = false,
    },

    serverApi = {
        writers = {
            nexus_crafting = {
                crafting = { maxXp = 250, maxReputation = 5 },
            },
            nexus_ems = {
                ems = { maxXp = 100, maxReputation = 5 },
            },
        },
    },
}
