-- NEXUS Panel de Cuarentenas v1 (staging only, crafting quarantines).
-- Apply manually to qbox_staging while nexus_contracts is stopped.
-- Reusable, parameterized version of the manual recovery pattern already
-- validated by hand for D20DB697 and the synthetic ZZZ-TEST-PROBE A/B rows.

DROP PROCEDURE IF EXISTS sp_recover_craft_quarantine;

DELIMITER $$

CREATE PROCEDURE sp_recover_craft_quarantine(
    IN p_reservation_id VARCHAR(64),
    IN p_route VARCHAR(16)
)
BEGIN
    DECLARE v_lot_id VARCHAR(64) DEFAULT NULL;
    DECLARE v_citizenid VARCHAR(64) DEFAULT NULL;
    DECLARE v_stock_state VARCHAR(16) DEFAULT NULL;
    DECLARE v_event_type VARCHAR(32) DEFAULT NULL;
    DECLARE v_transition_key VARCHAR(160) DEFAULT NULL;
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
        SELECT lot_id, citizenid INTO v_lot_id, v_citizenid
        FROM nexus_mechanic_craft_reservations
        WHERE reservation_id = p_reservation_id AND state = 'ambiguous'
        LIMIT 1;

        IF v_lot_id IS NULL THEN
            SELECT 'RESERVATION_NOT_FOUND' AS result, 0 AS stock_rc, 0 AS lot_rc, 0 AS event_rc;
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
