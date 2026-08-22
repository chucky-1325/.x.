NexusEMSDatabase = {}

function NexusEMSDatabase.Initialize()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `nexus_medical_events` (
            `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            `patient_citizenid` VARCHAR(64) NOT NULL,
            `medic_citizenid` VARCHAR(64) NOT NULL,
            `action` VARCHAR(40) NOT NULL,
            `before_state` LONGTEXT NOT NULL,
            `after_state` LONGTEXT NOT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `idx_medical_patient_time` (`patient_citizenid`, `created_at`),
            KEY `idx_medical_medic_time` (`medic_citizenid`, `created_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])
end

function NexusEMSDatabase.LogEvent(patientCitizenId, medicCitizenId, actionId, beforeState, afterState)
    return MySQL.insert.await(
        'INSERT INTO nexus_medical_events (patient_citizenid, medic_citizenid, action, before_state, after_state) VALUES (?, ?, ?, ?, ?)',
        { patientCitizenId, medicCitizenId, actionId, json.encode(beforeState), json.encode(afterState) }
    )
end

function NexusEMSDatabase.GetRecent(patientCitizenId, limit)
    limit = math.max(1, math.min(50, tonumber(limit) or 10))
    return MySQL.query.await(
        ('SELECT id, medic_citizenid, action, before_state, after_state, created_at FROM nexus_medical_events WHERE patient_citizenid = ? ORDER BY id DESC LIMIT %d'):format(limit),
        { patientCitizenId }
    ) or {}
end

