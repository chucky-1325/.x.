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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

