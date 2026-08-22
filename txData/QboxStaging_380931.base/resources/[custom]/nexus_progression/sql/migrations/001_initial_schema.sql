CREATE TABLE IF NOT EXISTS nexus_progression (
    citizenid VARCHAR(64) NOT NULL,
    domain VARCHAR(32) NOT NULL,
    xp INT NOT NULL DEFAULT 0,
    reputation INT NOT NULL DEFAULT 0,
    level INT NOT NULL DEFAULT 1,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (citizenid, domain),
    INDEX idx_nexus_progression_domain (domain)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
