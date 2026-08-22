CREATE TABLE IF NOT EXISTS nexus_contract_logs (
    id INT NOT NULL AUTO_INCREMENT,
    citizenid VARCHAR(64) NOT NULL,
    player_name VARCHAR(96) NULL,
    contract_id VARCHAR(64) NOT NULL,
    status VARCHAR(24) NOT NULL,
    reward_cash INT NOT NULL DEFAULT 0,
    reward_xp INT NOT NULL DEFAULT 0,
    reward_reputation INT NOT NULL DEFAULT 0,
    police_alert TINYINT(1) NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_contract_citizenid (citizenid),
    KEY idx_contract_id (contract_id),
    KEY idx_contract_created (created_at)
);
