-- NEXUS Phase 1B (staging only)
-- Adds atomic workshop stock reservations for the single mechanic recipe.

ALTER TABLE `nexus_mechanic_supply_stock`
    ADD COLUMN IF NOT EXISTS `stock_state` VARCHAR(16) NOT NULL DEFAULT 'available' AFTER `plastic`,
    ADD COLUMN IF NOT EXISTS `reservation_id` VARCHAR(64) NULL AFTER `stock_state`,
    ADD COLUMN IF NOT EXISTS `reserved_at` TIMESTAMP NULL AFTER `reservation_id`,
    ADD COLUMN IF NOT EXISTS `reservation_expires_at` BIGINT NULL AFTER `reserved_at`,
    ADD COLUMN IF NOT EXISTS `consumed_at` TIMESTAMP NULL AFTER `reservation_expires_at`;

CREATE UNIQUE INDEX IF NOT EXISTS `uq_mechanic_supply_stock_reservation`
    ON `nexus_mechanic_supply_stock` (`reservation_id`);

CREATE INDEX IF NOT EXISTS `idx_mechanic_supply_stock_state`
    ON `nexus_mechanic_supply_stock` (`stock_key`, `stock_state`, `received_at`);

CREATE TABLE IF NOT EXISTS `nexus_mechanic_craft_reservations` (
    `reservation_id` VARCHAR(64) NOT NULL,
    `lot_id` VARCHAR(64) NOT NULL,
    `citizenid` VARCHAR(64) NOT NULL,
    `station_id` VARCHAR(64) NOT NULL,
    `recipe_id` VARCHAR(64) NOT NULL,
    `output_item` VARCHAR(64) NOT NULL,
    `output_count` TINYINT UNSIGNED NOT NULL DEFAULT 1,
    `state` VARCHAR(24) NOT NULL DEFAULT 'reserved',
    `active_key` VARCHAR(64) NULL,
    `expires_at` BIGINT NOT NULL,
    `incident_reason` VARCHAR(160) NULL,
    `reserved_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `fulfilling_at` TIMESTAMP NULL,
    `completed_at` TIMESTAMP NULL,
    `finalized_at` TIMESTAMP NULL,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`reservation_id`),
    UNIQUE KEY `uq_mechanic_craft_active` (`active_key`),
    KEY `idx_mechanic_craft_lot` (`lot_id`),
    KEY `idx_mechanic_craft_state_expiry` (`state`, `expires_at`),
    CONSTRAINT `fk_mechanic_craft_stock_lot`
        FOREIGN KEY (`lot_id`) REFERENCES `nexus_mechanic_supply_stock` (`lot_id`)
        ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `nexus_mechanic_craft_events` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `reservation_id` VARCHAR(64) NOT NULL,
    `lot_id` VARCHAR(64) NOT NULL,
    `citizenid` VARCHAR(64) NOT NULL,
    `event_type` VARCHAR(32) NOT NULL,
    `transition_key` VARCHAR(160) NOT NULL,
    `details` LONGTEXT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_mechanic_craft_event_transition` (`transition_key`),
    KEY `idx_mechanic_craft_event_reservation` (`reservation_id`),
    KEY `idx_mechanic_craft_event_lot` (`lot_id`),
    KEY `idx_mechanic_craft_event_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `nexus_mechanic_craft_guards` (
    `guard_key` VARCHAR(160) NOT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`guard_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
