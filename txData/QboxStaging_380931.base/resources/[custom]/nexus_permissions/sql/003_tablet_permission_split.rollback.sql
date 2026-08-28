DELETE FROM nexus_permission_role_grants
WHERE role_name = 'admin'
  AND permission IN ('nexus_tablet.bypass_illegal_access', 'nexus_tablet.bypass_app_restriction');

INSERT INTO nexus_permission_role_grants (role_name, permission) VALUES
    ('admin', 'nexus_tablet.admin_access')
ON DUPLICATE KEY UPDATE permission = VALUES(permission);
