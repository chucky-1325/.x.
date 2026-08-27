SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE nexus_permission_roles (
    role_name VARCHAR(32) NOT NULL,
    label VARCHAR(64) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (role_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE nexus_permission_role_grants (
    role_name VARCHAR(32) NOT NULL,
    permission VARCHAR(96) NOT NULL,
    PRIMARY KEY (role_name, permission),
    FOREIGN KEY (role_name) REFERENCES nexus_permission_roles(role_name) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE nexus_character_roles (
    citizenid VARCHAR(64) NOT NULL,
    role_name VARCHAR(32) NOT NULL,
    granted_by VARCHAR(64) NOT NULL,
    reason VARCHAR(255) NULL,
    granted_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (citizenid, role_name),
    FOREIGN KEY (role_name) REFERENCES nexus_permission_roles(role_name) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE nexus_permission_audit_log (
    id INT NOT NULL AUTO_INCREMENT,
    actor_citizenid VARCHAR(64) NULL,
    actor_source VARCHAR(64) NOT NULL,
    actor_identifier VARCHAR(96) NOT NULL,
    target_citizenid VARCHAR(64) NULL,
    target_identifier VARCHAR(96) NULL,
    permission VARCHAR(96) NOT NULL,
    reason VARCHAR(255) NULL,
    executed_via VARCHAR(64) NOT NULL,
    result ENUM('success','denied','error') NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_actor (actor_citizenid),
    KEY idx_target (target_citizenid),
    KEY idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO nexus_permission_roles (role_name, label) VALUES
    ('admin', 'Administrador'),
    ('moderator', 'Moderador'),
    ('support', 'Soporte'),
    ('developer', 'Desarrollador');
