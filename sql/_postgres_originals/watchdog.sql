-- 1. Tabulka pro zachytávání alertů
CREATE TABLE IF NOT EXISTS watchdog_alerts (
    alert_id     SERIAL PRIMARY KEY,
    product_id   TEXT,
    test_num     TEXT,
    triggered_at TIMESTAMPTZ DEFAULT NOW(),
    fail_count   INT,
    last_value   FLOAT,
    limit_min    FLOAT,
    limit_max    FLOAT,
    message      TEXT
);

-- 2. Trigger funkce
CREATE OR REPLACE FUNCTION fn_watchdog_consecutive_fails()
RETURNS TRIGGER AS $$
DECLARE
    v_consecutive INT;
    v_limit       d_limit%ROWTYPE;
BEGIN
    -- Načíst limit pro tento produkt + test
    SELECT * INTO v_limit
    FROM d_limit
    WHERE product_id = NEW.product_id
      AND test_num   = NEW.test_num;

    -- Spočítat kolik posledních kusů po sobě failuje
    SELECT COUNT(*) INTO v_consecutive
    FROM (
        SELECT
            CASE
                WHEN v_limit.limit_min IS NOT NULL AND v_limit.limit_max IS NOT NULL
                     THEN measured_value BETWEEN v_limit.limit_min AND v_limit.limit_max
                WHEN v_limit.limit_min IS NOT NULL
                     THEN measured_value >= v_limit.limit_min
                WHEN v_limit.limit_max IS NOT NULL
                     THEN measured_value <= v_limit.limit_max
                WHEN v_limit.limit_value IS NOT NULL
                     THEN measured_value = v_limit.limit_value
            END AS pass
        FROM f_traces
        WHERE product_id = NEW.product_id
          AND test_num   = NEW.test_num
        ORDER BY timestamp DESC
        LIMIT 2  -- posledních N kusů
    ) sub
    WHERE pass = FALSE;

    -- Pokud 2 (nebo více) po sobě failují → zapsat alert
    IF v_consecutive >= 2 THEN
        INSERT INTO watchdog_alerts (
            product_id, test_num, fail_count,
            last_value, limit_min, limit_max, message
        ) VALUES (
            NEW.product_id,
            NEW.test_num,
            v_consecutive,
            NEW.measured_value,
            v_limit.limit_min,
            v_limit.limit_max,
            FORMAT('ALERT: %s consecutive fails for product %s test %s (last value: %s)',
                   v_consecutive, NEW.product_id, NEW.test_num, NEW.measured_value)
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3. Navázat trigger na f_traces
CREATE TRIGGER trg_watchdog_consecutive_fails
AFTER INSERT ON f_traces
FOR EACH ROW
EXECUTE FUNCTION fn_watchdog_consecutive_fails();