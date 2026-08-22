NexusSceneDefinitions = {
    craft_civil = {
        label = 'Montando componentes',
        animation = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 1 },
        props = {
            {
                model = 'prop_tool_hammer',
                bone = 57005,
                position = { x = 0.12, y = 0.02, z = -0.02 },
                rotation = { x = -90.0, y = 0.0, z = 15.0 },
            },
        },
    },
    craft_mechanic = {
        label = 'Ajustando piezas mecanicas',
        animation = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 1 },
        props = {
            {
                model = 'prop_tool_wrench',
                bone = 57005,
                position = { x = 0.12, y = 0.02, z = -0.01 },
                rotation = { x = -80.0, y = 0.0, z = 10.0 },
            },
        },
    },
    craft_illegal = {
        label = 'Preparando componentes clasificados',
        animation = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 1 },
        props = {
            {
                model = 'prop_cs_screwdriver',
                bone = 57005,
                position = { x = 0.11, y = 0.02, z = -0.01 },
                rotation = { x = -95.0, y = 0.0, z = 5.0 },
            },
        },
    },
    craft_medical = {
        label = 'Preparando material clinico',
        animation = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 1 },
        props = {
            {
                model = 'prop_ld_health_pack',
                bone = 57005,
                position = { x = 0.16, y = 0.02, z = -0.04 },
                rotation = { x = -90.0, y = 10.0, z = 0.0 },
            },
        },
    },
    craft_police = {
        label = 'Preparando equipo de servicio',
        animation = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 1 },
        props = {
            {
                model = 'prop_notepad_01',
                bone = 57005,
                position = { x = 0.13, y = 0.03, z = -0.02 },
                rotation = { x = -95.0, y = 0.0, z = 0.0 },
            },
        },
    },
    lab_chemistry = {
        label = 'Procesando mezcla de laboratorio',
        animation = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 1 },
        props = {
            {
                model = 'prop_cs_script_bottle_01',
                bone = 57005,
                position = { x = 0.11, y = 0.02, z = -0.03 },
                rotation = { x = -90.0, y = 0.0, z = 10.0 },
            },
        },
    },
    lab_packaging = {
        label = 'Empaquetando lote',
        animation = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 1 },
        props = {
            {
                model = 'prop_cs_cardbox_01',
                bone = 57005,
                position = { x = 0.18, y = 0.02, z = -0.05 },
                rotation = { x = -80.0, y = 0.0, z = 0.0 },
            },
        },
    },
    lab_processing = {
        label = 'Procesando materia prima',
        animation = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 1 },
        props = {
            {
                model = 'prop_cs_bowl_01',
                bone = 57005,
                position = { x = 0.15, y = 0.03, z = -0.04 },
                rotation = { x = -90.0, y = 0.0, z = 0.0 },
            },
        },
    },
    lab_maintenance = {
        label = 'Realizando mantenimiento',
        animation = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 1 },
        props = {
            {
                model = 'prop_tool_wrench',
                bone = 57005,
                position = { x = 0.12, y = 0.02, z = -0.01 },
                rotation = { x = -80.0, y = 0.0, z = 10.0 },
            },
        },
    },
    lab_sabotage = {
        label = 'Manipulando instalaciones rivales',
        animation = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 1 },
        props = {
            {
                model = 'prop_cs_screwdriver',
                bone = 57005,
                position = { x = 0.11, y = 0.02, z = -0.01 },
                rotation = { x = -95.0, y = 0.0, z = 5.0 },
            },
        },
    },
    package_pickup = {
        label = 'Recogiendo paquete',
        animation = { dict = 'mp_common', clip = 'givetake1_a', flag = 1 },
        props = {
            {
                model = 'prop_cs_package_01',
                bone = 57005,
                position = { x = 0.16, y = 0.03, z = -0.04 },
                rotation = { x = -90.0, y = 0.0, z = 10.0 },
            },
        },
    },
    package_delivery = {
        label = 'Entregando paquete',
        animation = { dict = 'mp_common', clip = 'givetake1_a', flag = 1 },
        props = {
            {
                model = 'prop_cs_package_01',
                bone = 57005,
                position = { x = 0.16, y = 0.03, z = -0.04 },
                rotation = { x = -90.0, y = 0.0, z = 10.0 },
            },
        },
    },
    extortion_collection = {
        label = 'Cobrando proteccion',
        animation = { dict = 'mp_common', clip = 'givetake1_a', flag = 1 },
        props = {
            {
                model = 'prop_cash_pile_01',
                bone = 57005,
                position = { x = 0.12, y = 0.03, z = -0.02 },
                rotation = { x = -90.0, y = 0.0, z = 0.0 },
            },
        },
    },
    evidence_biological = {
        label = 'Tomando muestra biologica',
        animation = { dict = 'amb@medic@standing@kneel@base', clip = 'base', flag = 1 },
        props = {
            {
                model = 'prop_ld_health_pack',
                bone = 57005,
                position = { x = 0.13, y = 0.02, z = -0.03 },
                rotation = { x = -90.0, y = 0.0, z = 10.0 },
            },
        },
    },
    evidence_trace = {
        label = 'Levantando indicios',
        animation = { dict = 'amb@medic@standing@kneel@base', clip = 'base', flag = 1 },
        props = {
            {
                model = 'prop_notepad_01',
                bone = 57005,
                position = { x = 0.11, y = 0.03, z = -0.02 },
                rotation = { x = -85.0, y = 0.0, z = 5.0 },
            },
        },
    },
    evidence_ballistic = {
        label = 'Embalando indicio balistico',
        animation = { dict = 'amb@medic@standing@kneel@base', clip = 'base', flag = 1 },
        props = {
            {
                model = 'prop_cs_package_01',
                bone = 57005,
                position = { x = 0.15, y = 0.03, z = -0.04 },
                rotation = { x = -90.0, y = 0.0, z = 10.0 },
            },
        },
    },
    evidence_photo = {
        label = 'Documentando la escena',
        animation = { dict = 'amb@world_human_paparazzi@male@base', clip = 'base', flag = 49 },
        props = {
            {
                model = 'prop_pap_camera_01',
                bone = 57005,
                position = { x = 0.12, y = 0.02, z = -0.02 },
                rotation = { x = -90.0, y = 0.0, z = 0.0 },
            },
        },
    },
    evidence_seal = {
        label = 'Sellando bolsa de evidencia',
        animation = { dict = 'mp_common', clip = 'givetake1_a', flag = 1 },
        props = {
            {
                model = 'prop_cs_package_01',
                bone = 57005,
                position = { x = 0.15, y = 0.03, z = -0.04 },
                rotation = { x = -90.0, y = 0.0, z = 10.0 },
            },
        },
    },
    ems_assessment = {
        label = 'Evaluando paciente',
        animation = { dict = 'amb@medic@standing@kneel@base', clip = 'base', flag = 1 },
        props = {
            {
                model = 'prop_notepad_01',
                bone = 57005,
                position = { x = 0.11, y = 0.03, z = -0.02 },
                rotation = { x = -85.0, y = 0.0, z = 5.0 },
            },
        },
    },
    ems_bandage = {
        label = 'Controlando hemorragia',
        animation = { dict = 'amb@medic@standing@kneel@base', clip = 'base', flag = 1 },
        props = {
            {
                model = 'prop_ld_health_pack',
                bone = 57005,
                position = { x = 0.13, y = 0.02, z = -0.03 },
                rotation = { x = -90.0, y = 0.0, z = 10.0 },
            },
        },
    },
    ems_medication = {
        label = 'Administrando medicacion',
        animation = { dict = 'amb@medic@standing@kneel@base', clip = 'base', flag = 1 },
        props = {
            {
                model = 'prop_cs_script_bottle_01',
                bone = 57005,
                position = { x = 0.11, y = 0.02, z = -0.02 },
                rotation = { x = -90.0, y = 0.0, z = 0.0 },
            },
        },
    },
    ems_stabilize = {
        label = 'Estabilizando paciente',
        animation = { dict = 'mini@cpr@char_a@cpr_str', clip = 'cpr_pumpchest', flag = 1 },
        props = {
            {
                model = 'prop_ld_health_pack',
                bone = 57005,
                position = { x = 0.13, y = 0.02, z = -0.03 },
                rotation = { x = -90.0, y = 0.0, z = 10.0 },
            },
        },
    },
    ems_resuscitate = {
        label = 'Realizando reanimacion',
        animation = { dict = 'mini@cpr@char_a@cpr_str', clip = 'cpr_pumpchest', flag = 1 },
        props = {},
    },
    ems_transport = {
        label = 'Preparando traslado',
        animation = { dict = 'amb@medic@standing@kneel@base', clip = 'base', flag = 1 },
        props = {
            {
                model = 'prop_ld_health_pack',
                bone = 57005,
                position = { x = 0.13, y = 0.02, z = -0.03 },
                rotation = { x = -90.0, y = 0.0, z = 10.0 },
            },
        },
    },
}
