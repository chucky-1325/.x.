NexusEMSConfig = {
    command = 'ems',
    adminAce = 'admin',
    maxPatientDistance = 3.0,
    actionExpiryGraceMs = 65000,
    hospital = vector3(307.17, -590.81, 43.28),

    scenes = {
        enabled = true,
    },

    progression = {
        domain = 'ems',
    },

    actions = {
        assess = {
            label = 'Evaluacion primaria',
            description = 'Consciencia, respiracion, pulso, sangrado y dolor.',
            duration = 5000,
            scene = 'ems_assessment',
            xp = 12,
            reputation = 1,
        },
        bandage = {
            label = 'Controlar hemorragia',
            description = 'Aplica vendaje y reduce el sangrado.',
            duration = 6500,
            scene = 'ems_bandage',
            items = { 'bandage' },
            xp = 24,
            reputation = 1,
        },
        pain_relief = {
            label = 'Administrar analgesia',
            description = 'Reduce dolor con medicacion controlada.',
            duration = 4500,
            scene = 'ems_medication',
            items = { 'painkillers' },
            xp = 18,
            reputation = 1,
        },
        stabilize = {
            label = 'Estabilizar paciente',
            description = 'Primeros auxilios para un paciente inestable.',
            duration = 9000,
            scene = 'ems_stabilize',
            items = { 'firstaid', 'ifaks' },
            xp = 40,
            reputation = 2,
        },
        resuscitate = {
            label = 'Reanimacion avanzada',
            description = 'Reanima un paciente sin constantes vitales.',
            duration = 12000,
            scene = 'ems_resuscitate',
            items = { 'firstaid', 'ifaks' },
            minGrade = 1,
            xp = 70,
            reputation = 3,
        },
        prepare_transport = {
            label = 'Preparar traslado',
            description = 'Estabiliza la posicion y marca destino hospitalario.',
            duration = 5500,
            scene = 'ems_transport',
            xp = 16,
            reputation = 1,
        },
    },

    effects = {
        bandage = { bleeding = -2, health = 12 },
        pain_relief = { pain = -2, health = 3 },
        stabilize = { bleeding = -1, pain = -1, minimumHealth = 130, stabilized = true },
        resuscitate = { health = 125, bleeding = 1, pain = 3, stabilized = true, revive = true },
        prepare_transport = { transportReady = true },
    },
}

