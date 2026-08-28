DELETE FROM nexus_permission_role_grants
WHERE role_name = 'admin'
  AND permission IN (
    'nexus_gangs.gang_create',
    'nexus_gangs.member_manage_override',
    'nexus_gangs.gang_member_admin',
    'nexus_gangs.reputation_grant'
  );

INSERT INTO nexus_permission_role_grants (role_name, permission) VALUES
    ('admin', 'nexus_gangs.admin_manage')
ON DUPLICATE KEY UPDATE permission = VALUES(permission);
