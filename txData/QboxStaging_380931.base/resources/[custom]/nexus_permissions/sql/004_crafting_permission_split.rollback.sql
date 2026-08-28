DELETE FROM nexus_permission_role_grants
WHERE role_name = 'admin'
  AND permission IN ('nexus_crafting.editor_view', 'nexus_crafting.editor_mutate');

INSERT INTO nexus_permission_role_grants (role_name, permission) VALUES
    ('admin', 'nexus_crafting.editor_manage')
ON DUPLICATE KEY UPDATE permission = VALUES(permission);
