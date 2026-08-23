NexusContractsConfig = {
    debug = false,
    command = 'contracts',
    quarantineAdminCommand = 'craftquarantine',
    quarantineAdminAce = 'nexus.crafting.admin',
    rateLimitBucket = 'default',
    interactDistance = 3.0,
    packageItem = 'nexus_contract_package',
    expirySweepSeconds = 30,
    actionDurations = {
        pickup = 4500,
        deliver = 5500,
    },
    sceneCore = {
        enabled = true,
        pickup = 'package_pickup',
        deliver = 'package_delivery',
    },

    supply = {
        type = 'civil_mechanic_supply',
        stockKey = 'mechanic',
        destination = 'mechanic_bennys',
        maxLots = 5,
        contents = {
            metalscrap = 3,
            iron = 2,
            plastic = 2,
        },
    },

    mechanicCrafting = {
        stationId = 'mechanic_bench',
        recipeId = 'repairkit_basic',
        outputItem = 'repairkit',
        outputCount = 1,
        stockKey = 'mechanic',
        job = 'mechanic',
        minimumGrade = 0,
        reservationSeconds = 90,
        coords = vector3(-211.61, -1324.64, 30.89),
        maxDistance = 4.0,
        contents = {
            metalscrap = 3,
            iron = 2,
            plastic = 2,
        },
    },

    contacts = {
        civil_supplier = {
            label = 'Proveedor de suministros',
            coords = vector3(489.62, -1314.13, 29.26),
            heading = 88.0,
            model = 's_m_m_dockwork_01',
            scenario = 'WORLD_HUMAN_CLIPBOARD',
        },
    },

    contracts = {
        civil_mechanic_supply = {
            type = 'civil_mechanic_supply',
            label = 'Suministros para taller',
            description = 'Transporta un lote sellado desde el proveedor hasta el taller mecanico.',
            pickup = vector3(472.31, -1310.72, 29.22),
            dropoff = vector3(-211.61, -1324.64, 30.89),
            destination = 'mechanic_bennys',
            durationSeconds = 1200,
        },
    },
}
