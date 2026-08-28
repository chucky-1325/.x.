-- Fase 4: siembra los 7 permisos granulares de nexus_blackmarket, nexus_ems
-- y nexus_labs en el rol 'admin'. Cada uno se aplicara en su propio commit
-- (blackmarket, labs, ems por separado), pero el catalogo/seed se hace de
-- una sola vez para los tres, como acordado.

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Estos 3 generic quedaron sembrados desde la Fase 0 (002_permission_catalog_seed.sql)
-- como placeholders, antes de que este catalogo existiera de verdad. Ya no
-- tienen entrada en PermissionCatalog -> hasPermission los rechazaria de
-- todos modos, pero se retiran explicitamente por higiene, igual que en
-- los splits de nexus_tablet/nexus_crafting/nexus_contracts.
DELETE FROM nexus_permission_role_grants
WHERE role_name = 'admin'
  AND permission IN ('nexus_blackmarket.admin_access', 'nexus_ems.admin_access', 'nexus_labs.admin_access');

INSERT INTO nexus_permission_role_grants (role_name, permission) VALUES
    ('admin', 'nexus_blackmarket.access_bypass'),
    ('admin', 'nexus_blackmarket.distance_bypass'),
    ('admin', 'nexus_ems.medic_access_bypass'),
    ('admin', 'nexus_ems.grade_override'),
    ('admin', 'nexus_labs.progression_bypass'),
    ('admin', 'nexus_labs.territory_bypass'),
    ('admin', 'nexus_labs.sabotage_bypass')
ON DUPLICATE KEY UPDATE permission = VALUES(permission);
