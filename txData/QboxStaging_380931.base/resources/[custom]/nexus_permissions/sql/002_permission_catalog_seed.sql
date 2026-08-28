-- Fase 0: siembra el rol 'admin' con cada permiso del catalogo inicial
-- (config.lua NexusPermissionsConfig.PermissionCatalog), preservando
-- paridad con el ACE 'admin' monolitico que hoy usan casi todos los
-- recursos -- quien ya es ACE-admin y ademas recibe el rol 'admin' por
-- nexus_permissions queda con exactamente el mismo alcance que tiene hoy.
-- Ningun otro rol (moderator/support/developer) recibe permisos todavia --
-- decision explicita para una fase posterior, no de este init.

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

INSERT INTO nexus_permission_role_grants (role_name, permission) VALUES
    ('admin', 'qbx_mdt.admin_access'),
    ('admin', 'handling_lab.use'),
    ('admin', 'nexus_dispatch.admin_access'),
    ('admin', 'nexus_tablet.admin_access'),
    ('admin', 'nexus_crafting.editor_manage'),
    ('admin', 'nexus_contracts.quarantine_admin'),
    ('admin', 'nexus_blackmarket.admin_access'),
    ('admin', 'nexus_ems.admin_access'),
    ('admin', 'nexus_labs.admin_access'),
    ('admin', 'nexus_territories.editor_manage'),
    ('admin', 'nexus_territories.graffiti_admin'),
    ('admin', 'nexus_territories.influence_grant'),
    ('admin', 'nexus_territories.airdrop_admin'),
    ('admin', 'nexus_gangs.admin_manage'),
    ('admin', 'nexus_menu.admin_access'),
    ('admin', 'nexus_menu.give_kit'),
    ('admin', 'nexus_menu.grant_progression')
ON DUPLICATE KEY UPDATE permission = VALUES(permission);
