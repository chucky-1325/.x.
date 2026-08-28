-- Fase 6b: nexus_gangs tenia un unico permiso generico (nexus_gangs.admin_manage)
-- cubriendo crear bandas, gestionar miembros (menu + comandos de consola) y
-- reputacion. Se separa en 4 permisos reales, opcion A (mas granular):
-- gang_create, member_manage_override (bypass de canManageTarget: permiso
-- interno de banda + tope de rango), gang_member_admin (gangadd/gangremove
-- de consola, sin restriccion de banda propia) y reputation_grant. El
-- sistema interno de permisos por rango de banda no se toca.

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

DELETE FROM nexus_permission_role_grants
WHERE role_name = 'admin' AND permission = 'nexus_gangs.admin_manage';

INSERT INTO nexus_permission_role_grants (role_name, permission) VALUES
    ('admin', 'nexus_gangs.gang_create'),
    ('admin', 'nexus_gangs.member_manage_override'),
    ('admin', 'nexus_gangs.gang_member_admin'),
    ('admin', 'nexus_gangs.reputation_grant')
ON DUPLICATE KEY UPDATE permission = VALUES(permission);
