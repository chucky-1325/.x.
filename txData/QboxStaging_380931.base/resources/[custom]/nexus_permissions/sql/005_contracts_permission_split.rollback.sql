DELETE FROM nexus_permission_role_grants
WHERE role_name = 'admin'
  AND permission IN (
    'nexus_contracts.quarantine_view',
    'nexus_contracts.craft_quarantine_recover',
    'nexus_contracts.lot_incident_recover'
  );

INSERT INTO nexus_permission_role_grants (role_name, permission) VALUES
    ('admin', 'nexus_contracts.quarantine_admin')
ON DUPLICATE KEY UPDATE permission = VALUES(permission);
