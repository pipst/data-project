-- Nejdřív v Postgresu připravte view pro poslední N produktů
CREATE OR REPLACE VIEW v_watchdog_latest AS
WITH latest AS (
    -- Posledních 10 kusů pro každou kombinaci product_id + test_num
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY product_id, test_num
               ORDER BY timestamp DESC
           ) AS rn
    FROM f_traces
),
enriched AS (
    SELECT
        l.product_id,
        l.test_num,
        l.measured_value,
        l.timestamp,
        d.limit_min,
        d.limit_max,
        d.limit_value,
        -- Pass/fail
        CASE
            WHEN d.limit_min IS NOT NULL AND d.limit_max IS NOT NULL
                 THEN l.measured_value BETWEEN d.limit_min AND d.limit_max
            WHEN d.limit_min IS NOT NULL
                 THEN l.measured_value >= d.limit_min
            WHEN d.limit_max IS NOT NULL
                 THEN l.measured_value <= d.limit_max
            WHEN d.limit_value IS NOT NULL
                 THEN l.measured_value = d.limit_value
        END AS test_pass,
        -- Relativní pozice v okně
        CASE WHEN d.limit_max != d.limit_min AND d.limit_min IS NOT NULL AND d.limit_max IS NOT NULL
             THEN (l.measured_value - d.limit_min) / (d.limit_max - d.limit_min)
        END AS margin_pct
    FROM latest l
    LEFT JOIN d_limit d ON d.product_id = l.product_id AND d.test_num = l.test_num
    WHERE l.rn <= 10  -- posledních 10 kusů
)
SELECT
    product_id,
    test_num,
    MAX(timestamp)      AS last_measured,
    -- Semafor stav
    CASE
        WHEN bool_or(NOT test_pass)                        THEN 'RED'
        WHEN MIN(margin_pct) < 0.1 OR MAX(margin_pct) > 0.9 THEN 'ORANGE'
        ELSE                                                    'GREEN'
    END AS status,
    MIN(margin_pct)     AS worst_margin,
    COUNT(*) FILTER (WHERE NOT test_pass) AS fail_count
FROM enriched
GROUP BY product_id, test_num;