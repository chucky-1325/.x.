DELETE FROM nexus_permission_role_grants
WHERE role_name = 'admin'
  AND permission IN ('nexus_territories.editor_view', 'nexus_territories.zone_save', 'nexus_territories.zone_delete');

INSERT INTO nexus_permission_role_grants (role_name, permission) VALUES
    ('admin', 'nexus_territories.editor_manage')
ON DUPLICATE KEY UPDATE permission = VALUES(permission);
