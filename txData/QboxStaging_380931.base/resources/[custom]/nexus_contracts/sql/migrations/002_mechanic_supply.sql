-- NEXUS staging migration 002: civil mechanic supply lots.
-- Apply manually to qbox_staging while nexus_contracts is stopped.

CREATE TABLE IF NOT EXISTS `nexus_mechanic_supply_lots` (
    `lot_id` VARCHAR(64) NOT NULL,
    `contract_type` VARCHAR(64) NOT NULL,
    `citizenid` VARCHAR(64) NOT NULL,
    `owner_name` VARCHAR(96) NULL,
    `destination` VARCHAR(64) NOT NULL,
    `contents` LONGTEXT NOT NULL,
    `state` VARCHAR(32) NOT NULL,
    `expires_at` BIGINT NOT NULL,
    `capacity_slot` TINYINT UNSIGNED NULL,
    `active_key` VARCHAR(64) NULL,
    `package_slot` SMALLINT UNSIGNED NULL,
    `incident_reason` VARCHAR(128) NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `picked_up_at` TIMESTAMP NULL DEFAULT NULL,
    `delivered_at` TIMESTAMP NULL DEFAULT NULL,
    `finalized_at` TIMESTAMP NULL DEFAULT NULL,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`lot_id`),
    UNIQUE KEY `uq_mechanic_supply_capacity_slot` (`capacity_slot`),
    UNIQUE KEY `uq_mechanic_supply_active_key` (`active_key`),
    KEY `idx_mechanic_supply_owner_state` (`citizenid`, `state`),
    KEY `idx_mechanic_supply_expiry` (`state`, `expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `nexus_mechanic_supply_stock` (
    `lot_id` VARCHAR(64) NOT NULL,
    `stock_key` VARCHAR(32) NOT NULL,
    `metalscrap` TINYINT UNSIGNED NOT NULL DEFAULT 3,
    `iron` TINYINT UNSIGNED NOT NULL DEFAULT 2,
    `plastic` TINYINT UNSIGNED NOT NULL DEFAULT 2,
    `received_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`lot_id`),
    KEY `idx_mechanic_supply_stock_key` (`stock_key`, `received_at`),
    CONSTRAINT `fk_mechanic_supply_stock_lot`
        FOREIGN KEY (`lot_id`) REFERENCES `nexus_mechanic_supply_lots` (`lot_id`)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `nexus_mechanic_supply_events` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `lot_id` VARCHAR(64) NOT NULL,
    `citizenid` VARCHAR(64) NULL,
    `event_type` VARCHAR(40) NOT NULL,
    `transition_key` VARCHAR(160) NULL,
    `details` LONGTEXT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_mechanic_supply_event_transition` (`transition_key`),
    KEY `idx_mechanic_supply_event_lot` (`lot_id`, `created_at`),
    KEY `idx_mechanic_supply_event_type` (`event_type`, `created_at`),
    CONSTRAINT `fk_mechanic_supply_event_lot`
        FOREIGN KEY (`lot_id`) REFERENCES `nexus_mechanic_supply_lots` (`lot_id`)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE `nexus_mechanic_supply_events`
    ADD COLUMN IF NOT EXISTS `transition_key` VARCHAR(160) NULL AFTER `event_type`;

CREATE UNIQUE INDEX IF NOT EXISTS `uq_mechanic_supply_event_transition`
    ON `nexus_mechanic_supply_events` (`transition_key`);
