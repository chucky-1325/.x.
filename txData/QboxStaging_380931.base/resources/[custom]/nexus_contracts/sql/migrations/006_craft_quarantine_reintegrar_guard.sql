-- NEXUS Panel de Cuarentenas de Crafting - guard de incident_reason (staging only).
-- Apply manually to qbox_staging while nexus_contracts is stopped.
--
-- sp_recover_craft_quarantine (migracion 004) nunca revisaba incident_reason:
-- la ruta 'reintegrar' devolvia los materiales reservados a 'available' sin
-- comprobar si el item fabricado ya habia sido entregado al inventario del
-- jugador, lo que permite duplicar valor.
--
-- Esta migracion invierte el modelo a lista de permitidos: 'reintegrar' solo
-- se ejecuta para los motivos donde el codigo de nexus_crafting/nexus_contracts
-- demuestra que el item de salida nunca se entrego, o fue reclamado con exito
-- antes de la incidencia. Cualquier motivo no incluido en la lista -conocido,
-- futuro, o NULL/vacio- queda bloqueado por defecto. La comprobacion de NULL
-- es explicita: en SQL, "NULL NOT IN (...)" evalua a NULL (no a TRUE), y un
-- ELSEIF con condicion NULL no se toma como verdadera, así que sin este
-- chequeo un incident_reason ausente caeria al ELSE y se trataria como
-- seguro. 'cerrar' no se ve afectado: descarta materiales sin devolverlos
-- al pool, sin riesgo de duplicacion en ningun motivo.
--
-- IMPORTANTE: fijar la sesion a utf8mb4/utf8mb4_unicode_ci antes de crear el
-- procedimiento. MySQL/MariaDB graban character_set_client/collation_connection
-- de la sesion que ejecuta el CREATE PROCEDURE como parte permanente de la
-- rutina, sin importar el charset de quien la llame despues. La columna
-- incident_reason usa utf8mb4_unicode_ci; si la rutina se crea con un charset
-- distinto (p.ej. cp850, el valor por defecto del cliente mysql.exe en
-- Windows), la comparacion "v_incident_reason NOT IN (...)" falla en
-- cualquier invocacion con error 1267 "Illegal mix of collations".

SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

DROP PROCEDURE IF EXISTS sp_recover_craft_quarantine;

DELIMITER $$

CREATE PROCEDURE sp_recover_craft_quarantine(
    IN p_reservation_id VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
    IN p_route VARCHAR(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
)
BEGIN
    DECLARE v_lot_id VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
    DECLARE v_citizenid VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
    DECLARE v_incident_reason VARCHAR(160) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
    DECLARE v_stock_state VARCHAR(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
    DECLARE v_event_type VARCHAR(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
    DECLARE v_transition_key VARCHAR(160) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
    DECLARE v_stock_rc INT DEFAULT 0;
    DECLARE v_lot_rc INT DEFAULT 0;
    DECLARE v_event_rc INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_route = 'reintegrar' THEN
        SET v_stock_state = 'available';
        SET v_event_type = 'manual_recovery_reintegrated';
        SET v_transition_key = CONCAT('recovery:reintegrated:', p_reservation_id);
    ELSEIF p_route = 'cerrar' THEN
        SET v_stock_state = 'discarded';
        SET v_event_type = 'manual_recovery_closed';
        SET v_transition_key = CONCAT('recovery:closed:', p_reservation_id);
    END IF;

    IF v_stock_state IS NULL THEN
        SELECT 'INVALID_ROUTE' AS result, 0 AS stock_rc, 0 AS lot_rc, 0 AS event_rc;
    ELSE
        SELECT lot_id, citizenid, incident_reason INTO v_lot_id, v_citizenid, v_incident_reason
        FROM nexus_mechanic_craft_reservations
        WHERE reservation_id = p_reservation_id AND state = 'ambiguous'
        LIMIT 1;

        IF v_lot_id IS NULL THEN
            SELECT 'RESERVATION_NOT_FOUND' AS result, 0 AS stock_rc, 0 AS lot_rc, 0 AS event_rc;
        ELSEIF p_route = 'reintegrar' AND (
            v_incident_reason IS NULL
            OR v_incident_reason NOT IN (
                'begin_lot_mismatch',
                'player_cancelled_release_failed',
                'ttl_expired_release_failed',
                'inventory_full_release_failed',
                'begin_failed_release_failed',
                'inventory_add_failed_release_failed',
                'stock_commit_failed_release_failed',
                'crafting_resource_stopped_release_failed',
                'disconnect_release_failed',
                'ttl_release_failed'
            )
        ) THEN
            SELECT 'UNSAFE_ROUTE_FOR_REASON' AS result, 0 AS stock_rc, 0 AS lot_rc, 0 AS event_rc;
        ELSE
            START TRANSACTION;

            UPDATE nexus_mechanic_supply_stock
            SET stock_state = v_stock_state, reservation_id = NULL
            WHERE lot_id = v_lot_id
              AND reservation_id = p_reservation_id
              AND stock_state = 'reserved'
              AND EXISTS (
                  SELECT 1 FROM nexus_mechanic_craft_reservations
                  WHERE reservation_id = p_reservation_id
                    AND citizenid = v_citizenid
                    AND state = 'ambiguous'
              )
              AND EXISTS (
                  SELECT 1 FROM nexus_mechanic_supply_lots
                  WHERE lot_id = v_lot_id AND state = 'delivered' AND capacity_slot IS NOT NULL
              )
              AND NOT EXISTS (
                  SELECT 1 FROM nexus_mechanic_supply_events WHERE transition_key = v_transition_key
              );
            SET v_stock_rc = ROW_COUNT();

            IF v_stock_rc = 1 THEN
                UPDATE nexus_mechanic_supply_lots
                SET state = 'recovered', capacity_slot = NULL
                WHERE lot_id = v_lot_id AND state = 'delivered' AND capacity_slot IS NOT NULL;
                SET v_lot_rc = ROW_COUNT();
            END IF;

            IF v_stock_rc = 1 AND v_lot_rc = 1 THEN
                INSERT INTO nexus_mechanic_supply_events
                    (lot_id, citizenid, event_type, transition_key, details)
                VALUES (v_lot_id, v_citizenid, v_event_type, v_transition_key, NULL);
                SET v_event_rc = ROW_COUNT();
            END IF;

            IF v_stock_rc = 1 AND v_lot_rc = 1 AND v_event_rc = 1 THEN
                COMMIT;
                SELECT 'COMMIT' AS result, v_stock_rc AS stock_rc, v_lot_rc AS lot_rc, v_event_rc AS event_rc;
            ELSE
                ROLLBACK;
                SELECT 'ROLLBACK' AS result, v_stock_rc AS stock_rc, v_lot_rc AS lot_rc, v_event_rc AS event_rc;
            END IF;
        END IF;
    END IF;
END$$

DELIMITER ;
