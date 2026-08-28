-- Fase 3b: nexus_contracts tenia un unico permiso generico
-- (nexus_contracts.quarantine_admin) cubriendo dos listados de solo lectura
-- y dos acciones de recuperacion real. Se separa en tres permisos:
-- un permiso de vista compartido para ambos listados, y DOS permisos de
-- mutacion independientes -- uno por tipo de recuperacion -- para poder
-- delegar cada uno por separado en el futuro.

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

DELETE FROM nexus_permission_role_grants
WHERE role_name = 'admin' AND permission = 'nexus_contracts.quarantine_admin';

INSERT INTO nexus_permission_role_grants (role_name, permission) VALUES
    ('admin', 'nexus_contracts.quarantine_view'),
    ('admin', 'nexus_contracts.craft_quarantine_recover'),
    ('admin', 'nexus_contracts.lot_incident_recover')
ON DUPLICATE KEY UPDATE permission = VALUES(permission);
