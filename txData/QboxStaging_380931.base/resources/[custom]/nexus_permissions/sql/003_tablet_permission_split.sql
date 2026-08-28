-- Fase 2: nexus_tablet tenia un unico permiso generico (nexus_tablet.admin_access)
-- cubriendo dos bypasses administrativos distintos en el codigo. Se separa en
-- dos permisos reales -- uno por accion -- y se retira el generico.

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

DELETE FROM nexus_permission_role_grants
WHERE role_name = 'admin' AND permission = 'nexus_tablet.admin_access';

INSERT INTO nexus_permission_role_grants (role_name, permission) VALUES
    ('admin', 'nexus_tablet.bypass_illegal_access'),
    ('admin', 'nexus_tablet.bypass_app_restriction')
ON DUPLICATE KEY UPDATE permission = VALUES(permission);
