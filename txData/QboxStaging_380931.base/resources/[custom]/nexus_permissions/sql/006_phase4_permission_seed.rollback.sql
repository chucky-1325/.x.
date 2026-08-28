DELETE FROM nexus_permission_role_grants
WHERE role_name = 'admin'
  AND permission IN (
    'nexus_blackmarket.access_bypass',
    'nexus_blackmarket.distance_bypass',
    'nexus_ems.medic_access_bypass',
    'nexus_ems.grade_override',
    'nexus_labs.progression_bypass',
    'nexus_labs.territory_bypass',
    'nexus_labs.sabotage_bypass'
  );

INSERT INTO nexus_permission_role_grants (role_name, permission) VALUES
    ('admin', 'nexus_blackmarket.admin_access'),
    ('admin', 'nexus_ems.admin_access'),
    ('admin', 'nexus_labs.admin_access')
ON DUPLICATE KEY UPDATE permission = VALUES(permission);
