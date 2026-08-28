-- Fase 5: nexus_territories tenia un unico permiso generico
-- (nexus_territories.editor_manage) cubriendo ver/abrir el editor y mutar
-- zonas (guardar/eliminar). Se separa en tres permisos reales -- solo
-- lectura, guardar zona y eliminar zona -- y se retira el generico.
-- graffiti_admin/influence_grant/airdrop_admin ya existian con su nombre
-- final desde la semilla de Fase 0 (002_permission_catalog_seed.sql), no
-- se tocan aqui.

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

DELETE FROM nexus_permission_role_grants
WHERE role_name = 'admin' AND permission = 'nexus_territories.editor_manage';

INSERT INTO nexus_permission_role_grants (role_name, permission) VALUES
    ('admin', 'nexus_territories.editor_view'),
    ('admin', 'nexus_territories.zone_save'),
    ('admin', 'nexus_territories.zone_delete')
ON DUPLICATE KEY UPDATE permission = VALUES(permission);
