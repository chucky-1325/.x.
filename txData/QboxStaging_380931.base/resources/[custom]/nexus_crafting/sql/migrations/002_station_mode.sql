-- NEXUS gating por estacion (staging only).
-- 'mode' reemplaza el uso del booleano global verticalSlice.enabled para
-- decidir que estaciones son alcanzables. Sin valor por defecto a proposito:
-- una fila sin 'mode' explicito queda inalcanzable (getStation la trata como
-- no reconocida), tanto para las 3 mesas dinamicas ya existentes como para
-- cualquiera nueva creada por el editor hasta que este se actualice para
-- pedir el modo explicitamente.

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

ALTER TABLE nexus_crafting_workbenches
    ADD COLUMN IF NOT EXISTS mode VARCHAR(16) NULL AFTER type;
