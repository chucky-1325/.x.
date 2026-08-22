NexusDispatchConfig = NexusDispatchConfig or {}

NexusDispatchConfig.command = 'dispatch'
NexusDispatchConfig.maxRecent = 30
NexusDispatchConfig.blipSeconds = 90
NexusDispatchConfig.adminAce = 'admin'

NexusDispatchConfig.statuses = {
    open = { label = 'Abierta' },
    assigned = { label = 'Asignada' },
    enroute = { label = 'En ruta' },
    closed = { label = 'Cerrada' },
}

NexusDispatchConfig.ais = {
    enabled = true,
    resource = 'ais_core',
    typeMap = {
        lab = 'narcotics',
        sabotage = 'organized_crime',
        laundering = 'fraud',
        operations = 'organized_crime',
        crafting = 'organized_crime',
        blackmarket = 'organized_crime',
        bolo = 'organized_crime',
        generic = 'organized_crime',
    },
}

NexusDispatchConfig.policeJobs = {
    police = true,
    bcso = true,
    sasp = true,
    sheriff = true,
}

NexusDispatchConfig.types = {
    generic = { label = 'Incidente', priority = 1, sprite = 161, color = 3 },
    lab = { label = 'Laboratorio ilegal', priority = 3, sprite = 499, color = 1 },
    sabotage = { label = 'Sabotaje de laboratorio', priority = 3, sprite = 161, color = 1 },
    laundering = { label = 'Lavado de dinero', priority = 2, sprite = 500, color = 5 },
    operations = { label = 'Operacion de banda', priority = 2, sprite = 478, color = 47 },
    crafting = { label = 'Crafting sensible', priority = 2, sprite = 566, color = 17 },
    blackmarket = { label = 'Mercado negro', priority = 2, sprite = 514, color = 40 },
    bolo = { label = 'BOLO activo', priority = 3, sprite = 480, color = 29 },
}
