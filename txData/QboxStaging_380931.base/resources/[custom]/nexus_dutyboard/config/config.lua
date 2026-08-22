NexusDutyboardConfig = {
    debug = false,

    job = 'mechanic',

    point = vector3(-207.9, -1319.7, 30.89),
    radius = 1.5,

    targetLabel = 'Fichar',
    targetIcon = 'fa-solid fa-clipboard-check',

    -- server-side authoritative check against GetEntityCoords(GetPlayerPed(src)); has nothing to do with the ox_target radius above
    maxServerDistance = 2.5,

    rateLimitBucket = 'dutyboard',
    localCooldownMs = 3000,
}
