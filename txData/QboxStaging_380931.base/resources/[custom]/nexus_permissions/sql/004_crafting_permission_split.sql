-- Fase 3: nexus_crafting tenia un unico permiso generico (nexus_crafting.editor_manage)
-- cubriendo ver/listar el editor y mutar mesas (crear/guardar/mover/activar/
-- eliminar). Se separa en dos permisos reales -- solo lectura vs mutacion --
-- y se retira el generico.

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

DELETE FROM nexus_permission_role_grants
WHERE role_name = 'admin' AND permission = 'nexus_crafting.editor_manage';

INSERT INTO nexus_permission_role_grants (role_name, permission) VALUES
    ('admin', 'nexus_crafting.editor_view'),
    ('admin', 'nexus_crafting.editor_mutate')
ON DUPLICATE KEY UPDATE permission = VALUES(permission);
