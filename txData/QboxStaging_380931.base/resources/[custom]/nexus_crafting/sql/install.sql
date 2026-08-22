CREATE TABLE IF NOT EXISTS nexus_crafting_logs (
    id INT NOT NULL AUTO_INCREMENT,
    citizenid VARCHAR(64) NOT NULL,
    station_id VARCHAR(64) NOT NULL,
    recipe_id VARCHAR(64) NOT NULL,
    output_item VARCHAR(64) NOT NULL,
    output_count INT NOT NULL DEFAULT 1,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    INDEX idx_nexus_crafting_citizenid (citizenid),
    INDEX idx_nexus_crafting_recipe (recipe_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS nexus_crafting_workbenches (
    id VARCHAR(64) NOT NULL,
    label VARCHAR(96) NOT NULL,
    type VARCHAR(24) NOT NULL DEFAULT 'public',
    category VARCHAR(32) NOT NULL DEFAULT 'civil',
    enabled TINYINT(1) NOT NULL DEFAULT 1,
    job VARCHAR(64) NULL,
    jobs LONGTEXT NULL,
    model VARCHAR(96) NOT NULL DEFAULT 'gr_prop_gr_bench_04b',
    recipes LONGTEXT NOT NULL,
    x DOUBLE NOT NULL,
    y DOUBLE NOT NULL,
    z DOUBLE NOT NULL,
    heading DOUBLE NOT NULL DEFAULT 0,
    sx DOUBLE NOT NULL DEFAULT 1.6,
    sy DOUBLE NOT NULL DEFAULT 1.2,
    sz DOUBLE NOT NULL DEFAULT 1.2,
    created_by VARCHAR(64) NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    INDEX idx_nexus_crafting_workbenches_type (type),
    INDEX idx_nexus_crafting_workbenches_category (category)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS nexus_crafting_sensitive_logs (
    id INT NOT NULL AUTO_INCREMENT,
    citizenid VARCHAR(64) NULL,
    source_id INT NULL,
    station_id VARCHAR(64) NOT NULL,
    recipe_id VARCHAR(64) NOT NULL,
    output_item VARCHAR(64) NOT NULL,
    output_count INT NOT NULL DEFAULT 1,
    blueprint_item VARCHAR(64) NULL,
    police_alert TINYINT(1) NOT NULL DEFAULT 0,
    risk_chance INT NOT NULL DEFAULT 0,
    x DOUBLE NULL,
    y DOUBLE NULL,
    z DOUBLE NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    INDEX idx_nexus_crafting_sensitive_citizenid (citizenid),
    INDEX idx_nexus_crafting_sensitive_recipe (recipe_id),
    INDEX idx_nexus_crafting_sensitive_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
