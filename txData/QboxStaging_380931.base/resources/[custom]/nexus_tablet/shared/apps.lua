NexusTabletApps = {
    home = {
        label = 'Inicio',
        variant = 'civil',
        access = false,
    },
    police = {
        label = 'MDT Policial',
        variant = 'police',
        access = 'police',
        external = { resource = 'qbx_mdt', export = 'openMdt' },
    },
    ems = {
        label = 'Clinica EMS',
        variant = 'ems',
        access = 'ems',
        status = 'planned',
    },
    illegal = {
        label = 'Red Clandestina',
        variant = 'illegal',
        access = 'illegal',
        status = 'planned',
    },
    business = {
        label = 'Empresas',
        variant = 'business',
        access = 'business',
        status = 'planned',
    },
}
