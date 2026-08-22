CREATE TABLE IF NOT EXISTS nexus_laundering_logs (
    id INT NOT NULL AUTO_INCREMENT,
    citizenid VARCHAR(64) NOT NULL,
    player_name VARCHAR(96) NULL,
    gang_name VARCHAR(64) NULL,
    location_id VARCHAR(64) NOT NULL,
    zone_id VARCHAR(64) NULL,
    dirty_amount INT NOT NULL DEFAULT 0,
    clean_amount INT NOT NULL DEFAULT 0,
    commission INT NOT NULL DEFAULT 0,
    risk INT NOT NULL DEFAULT 0,
    police_alert TINYINT(1) NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_launder_citizenid (citizenid),
    KEY idx_launder_gang (gang_name),
    KEY idx_launder_location (location_id),
    KEY idx_launder_created (created_at)
);

CREATE TABLE IF NOT EXISTS nexus_laundering_cooldowns (
    citizenid VARCHAR(64) NOT NULL,
    location_id VARCHAR(64) NOT NULL,
    available_at BIGINT NOT NULL DEFAULT 0,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (citizenid, location_id),
    KEY idx_launder_cd_available (available_at)
);
