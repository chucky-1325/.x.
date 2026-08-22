CREATE TABLE IF NOT EXISTS nexus_blackmarket_logs (
    id INT NOT NULL AUTO_INCREMENT,
    citizenid VARCHAR(64) NOT NULL,
    player_name VARCHAR(96) NULL,
    location_id VARCHAR(64) NOT NULL,
    catalog_id VARCHAR(64) NOT NULL,
    item VARCHAR(64) NOT NULL,
    price INT NOT NULL DEFAULT 0,
    money_type VARCHAR(24) NOT NULL DEFAULT 'cash',
    heat INT NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_citizenid (citizenid),
    KEY idx_catalog_id (catalog_id),
    KEY idx_created_at (created_at)
);
