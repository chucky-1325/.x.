CREATE TABLE IF NOT EXISTS nexus_lab_logs (
    id INT NOT NULL AUTO_INCREMENT,
    lab_id VARCHAR(64) NOT NULL,
    zone_id VARCHAR(64) NOT NULL,
    gang_name VARCHAR(64) NOT NULL,
    citizenid VARCHAR(64) NOT NULL,
    player_name VARCHAR(96) NULL,
    status VARCHAR(24) NOT NULL,
    risk INT NOT NULL DEFAULT 0,
    xp INT NOT NULL DEFAULT 0,
    reputation INT NOT NULL DEFAULT 0,
    influence INT NOT NULL DEFAULT 0,
    police_alert TINYINT(1) NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_lab_logs_lab (lab_id),
    KEY idx_lab_logs_gang (gang_name),
    KEY idx_lab_logs_zone (zone_id),
    KEY idx_lab_logs_created (created_at)
);

CREATE TABLE IF NOT EXISTS nexus_lab_cooldowns (
    gang_name VARCHAR(64) NOT NULL,
    lab_id VARCHAR(64) NOT NULL,
    available_at BIGINT NOT NULL DEFAULT 0,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (gang_name, lab_id),
    KEY idx_lab_cd_available (available_at)
);

CREATE TABLE IF NOT EXISTS nexus_lab_state (
    gang_name VARCHAR(64) NOT NULL,
    lab_id VARCHAR(64) NOT NULL,
    level INT NOT NULL DEFAULT 1,
    condition_value INT NOT NULL DEFAULT 100,
    queue_until BIGINT NOT NULL DEFAULT 0,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (gang_name, lab_id),
    KEY idx_lab_state_queue (queue_until)
);
