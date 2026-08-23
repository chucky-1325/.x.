-- NEXUS Panel de Incidencias de Suministro v1 (staging only, casos seguros).
-- Apply manually to qbox_staging while nexus_contracts is stopped.
--
-- Automatiza unicamente los 3 incident_reason donde el estado fisico del
-- paquete es conocido con certeza (ver auditoria de diseno):
--   - created_event_not_persisted     -> revertir a 'reserved' (solo faltaba el log)
--   - pickup_event_not_persisted      -> revertir a 'picked_up' (solo faltaba el log)
--   - inventory_removed_stock_commit_failed -> completar entrega + acreditar stock
--     (el paquete ya se confirmo eliminado del inventario antes de este fallo)
--
-- Cualquier otro incident_reason es rechazado por el propio procedimiento,
-- sin tocar nada, independientemente de lo que pida el cliente/admin.

DROP PROCEDURE IF EXISTS sp_recover_civil_lot_incident;

DELIMITER $$

CREATE PROCEDURE sp_recover_civil_lot_incident(
    IN p_lot_id VARCHAR(64),
    IN p_stock_key VARCHAR(32),
    IN p_metalscrap TINYINT UNSIGNED,
    IN p_iron TINYINT UNSIGNED,
    IN p_plastic TINYINT UNSIGNED
)
BEGIN
    DECLARE v_citizenid VARCHAR(64) DEFAULT NULL;
    DECLARE v_incident_reason VARCHAR(128) DEFAULT NULL;
    DECLARE v_target_state VARCHAR(32) DEFAULT NULL;
    DECLARE v_event_type VARCHAR(40) DEFAULT NULL;
    DECLARE v_transition_key VARCHAR(160) DEFAULT NULL;
    DECLARE v_needs_stock TINYINT(1) DEFAULT 0;
    DECLARE v_lot_rc INT DEFAULT 0;
    DECLARE v_stock_rc INT DEFAULT 0;
    DECLARE v_event_rc INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SELECT citizenid, incident_reason INTO v_citizenid, v_incident_reason
    FROM nexus_mechanic_supply_lots
    WHERE lot_id = p_lot_id AND state = 'ambiguous'
    LIMIT 1;

    IF v_citizenid IS NULL THEN
        SELECT 'LOT_NOT_FOUND' AS result, 0 AS lot_rc, 0 AS stock_rc, 0 AS event_rc;
    ELSE
        IF v_incident_reason = 'created_event_not_persisted' THEN
            SET v_target_state = 'reserved';
            SET v_event_type = 'manual_recovery_audit_retry_reserved';
            SET v_transition_key = CONCAT('recovery:audit_retry:reserved:', p_lot_id);
        ELSEIF v_incident_reason = 'pickup_event_not_persisted' THEN
            SET v_target_state = 'picked_up';
            SET v_event_type = 'manual_recovery_audit_retry_picked_up';
            SET v_transition_key = CONCAT('recovery:audit_retry:picked_up:', p_lot_id);
        ELSEIF v_incident_reason = 'inventory_removed_stock_commit_failed' THEN
            SET v_target_state = 'delivered';
            SET v_event_type = 'manual_recovery_stock_reintegrated';
            SET v_transition_key = CONCAT('recovery:stock_reintegrated:', p_lot_id);
            SET v_needs_stock = 1;
        END IF;

        IF v_target_state IS NULL THEN
            SELECT 'UNSAFE_REASON' AS result, 0 AS lot_rc, 0 AS stock_rc, 0 AS event_rc;
        ELSEIF v_needs_stock = 1 THEN
            START TRANSACTION;

            UPDATE nexus_mechanic_supply_lots
            SET state = v_target_state, active_key = NULL, package_slot = NULL,
                incident_reason = NULL, delivered_at = CURRENT_TIMESTAMP
            WHERE lot_id = p_lot_id AND citizenid = v_citizenid
              AND state = 'ambiguous' AND incident_reason = 'inventory_removed_stock_commit_failed'
              AND NOT EXISTS (
                  SELECT 1 FROM nexus_mechanic_supply_events WHERE transition_key = v_transition_key
              );
            SET v_lot_rc = ROW_COUNT();

            IF v_lot_rc = 1 THEN
                INSERT INTO nexus_mechanic_supply_stock
                    (lot_id, stock_key, metalscrap, iron, plastic)
                VALUES (p_lot_id, p_stock_key, p_metalscrap, p_iron, p_plastic);
                SET v_stock_rc = ROW_COUNT();
            END IF;

            IF v_lot_rc = 1 AND v_stock_rc = 1 THEN
                INSERT INTO nexus_mechanic_supply_events
                    (lot_id, citizenid, event_type, transition_key, details)
                VALUES (p_lot_id, v_citizenid, v_event_type, v_transition_key, NULL);
                SET v_event_rc = ROW_COUNT();
            END IF;

            IF v_lot_rc = 1 AND v_stock_rc = 1 AND v_event_rc = 1 THEN
                COMMIT;
                SELECT 'COMMIT' AS result, v_lot_rc AS lot_rc, v_stock_rc AS stock_rc, v_event_rc AS event_rc;
            ELSE
                ROLLBACK;
                SELECT 'ROLLBACK' AS result, v_lot_rc AS lot_rc, v_stock_rc AS stock_rc, v_event_rc AS event_rc;
            END IF;
        ELSE
            START TRANSACTION;

            UPDATE nexus_mechanic_supply_lots
            SET state = v_target_state, incident_reason = NULL, finalized_at = NULL
            WHERE lot_id = p_lot_id AND citizenid = v_citizenid
              AND state = 'ambiguous' AND incident_reason = v_incident_reason
              AND NOT EXISTS (
                  SELECT 1 FROM nexus_mechanic_supply_events WHERE transition_key = v_transition_key
              );
            SET v_lot_rc = ROW_COUNT();

            IF v_lot_rc = 1 THEN
                INSERT INTO nexus_mechanic_supply_events
                    (lot_id, citizenid, event_type, transition_key, details)
                VALUES (p_lot_id, v_citizenid, v_event_type, v_transition_key, NULL);
                SET v_event_rc = ROW_COUNT();
            END IF;

            IF v_lot_rc = 1 AND v_event_rc = 1 THEN
                COMMIT;
                SELECT 'COMMIT' AS result, v_lot_rc AS lot_rc, 0 AS stock_rc, v_event_rc AS event_rc;
            ELSE
                ROLLBACK;
                SELECT 'ROLLBACK' AS result, v_lot_rc AS lot_rc, 0 AS stock_rc, v_event_rc AS event_rc;
            END IF;
        END IF;
    END IF;
END$$

DELIMITER ;
