-- NEXUS Trabajos persistentes por mesa (staging only).
-- Subsistema separado del flujo mecanico de reservas (nexus_contracts) y del
-- flujo sincrono anterior (craftSessions/fulfillingSessions/finishCraft).

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE nexus_crafting_jobs (
    id INT NOT NULL AUTO_INCREMENT,
    job_key VARCHAR(64) NOT NULL,
    station_id VARCHAR(64) NOT NULL,
    recipe_id VARCHAR(64) NOT NULL,
    initiator_citizenid VARCHAR(64) NOT NULL,
    initiator_gang VARCHAR(64) NULL,
    station_type VARCHAR(24) NOT NULL,
    owner_gang VARCHAR(64) NULL,
    ingredients_snapshot LONGTEXT NULL,
    output_snapshot LONGTEXT NOT NULL,
    state VARCHAR(24) NOT NULL DEFAULT 'preparing',
    ready_at BIGINT NOT NULL,
    active_station_key VARCHAR(64) NULL,
    claim_action VARCHAR(16) NULL,
    claim_actor_citizenid VARCHAR(64) NULL,
    claim_key VARCHAR(64) NULL,
    claim_started_at BIGINT NULL,
    started_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    collected_at TIMESTAMP NULL,
    collected_by_citizenid VARCHAR(64) NULL,
    is_theft TINYINT(1) NOT NULL DEFAULT 0,
    cancel_reason VARCHAR(160) NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_crafting_jobs_key (job_key),
    UNIQUE KEY uq_crafting_jobs_active_station (active_station_key),
    KEY idx_crafting_jobs_initiator (initiator_citizenid, state),
    KEY idx_crafting_jobs_state_ready (state, ready_at),
    KEY idx_crafting_jobs_station (station_id, state),
    KEY idx_crafting_jobs_claim_lease (state, claim_started_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE nexus_crafting_job_events (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    job_id INT NOT NULL,
    event_type VARCHAR(32) NOT NULL,
    actor_citizenid VARCHAR(64) NULL,
    transition_key VARCHAR(160) NOT NULL,
    details LONGTEXT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_crafting_job_event_transition (transition_key),
    KEY idx_crafting_job_events_job (job_id, created_at),
    CONSTRAINT fk_crafting_job_events_job FOREIGN KEY (job_id) REFERENCES nexus_crafting_jobs(id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE nexus_crafting_workbenches
    ADD COLUMN IF NOT EXISTS owner_gang VARCHAR(64) NULL AFTER jobs;
