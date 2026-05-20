-- ============================================================
-- l1.v_watchdog_latest — semafor view pro Power BI watchdog dashboard.
-- Pro každou kombinaci (product_id, test_num) vrátí status RED/ORANGE/GREEN
-- z posledních 10 měření.
-- Originál: sql/_postgres_originals/v_watchdog_bi.sql (PostgreSQL).
-- KLÍČOVÉ KONVERZE:
--   - bool_or(NOT test_pass)    → MIN(test_pass_int) = 0
--   - COUNT(*) FILTER (WHERE …) → SUM(CASE WHEN … THEN 1 ELSE 0 END)
-- ============================================================

CREATE OR ALTER VIEW l1.v_watchdog_latest AS
WITH latest AS (
    SELECT
        f.product_id,
        f.test_num,
        f.measured_value,
        f.[timestamp],
        ROW_NUMBER() OVER (
            PARTITION BY f.product_id, f.test_num
            ORDER BY f.[timestamp] DESC
        ) AS rn
    FROM l1.f_traces f
),
enriched AS (
    SELECT
        l.product_id,
        l.test_num,
        l.measured_value,
        l.[timestamp],
        d.limit_min,
        d.limit_max,
        d.limit_value,
        -- Pass/fail jako INT (0/1, NULL pokud nelze rozhodnout)
        CASE
            WHEN d.limit_min IS NOT NULL AND d.limit_max IS NOT NULL
                 THEN CASE WHEN l.measured_value BETWEEN d.limit_min AND d.limit_max THEN 1 ELSE 0 END
            WHEN d.limit_min IS NOT NULL
                 THEN CASE WHEN l.measured_value >= d.limit_min THEN 1 ELSE 0 END
            WHEN d.limit_max IS NOT NULL
                 THEN CASE WHEN l.measured_value <= d.limit_max THEN 1 ELSE 0 END
            WHEN d.limit_value IS NOT NULL
                 THEN CASE WHEN l.measured_value = d.limit_value THEN 1 ELSE 0 END
        END AS test_pass_int,
        -- Relativní pozice v okně
        CASE WHEN d.limit_min IS NOT NULL
                  AND d.limit_max IS NOT NULL
                  AND d.limit_max <> d.limit_min
             THEN (l.measured_value - d.limit_min) / (d.limit_max - d.limit_min)
        END AS margin_pct
    FROM latest l
    LEFT JOIN l1.d_limit d
           ON d.product_id = l.product_id AND d.test_num = l.test_num
    WHERE l.rn <= 10
)
SELECT
    product_id,
    test_num,
    MAX([timestamp])    AS last_measured,
    CASE
        WHEN MIN(test_pass_int) = 0                              THEN 'RED'
        WHEN MIN(margin_pct) < 0.1 OR MAX(margin_pct) > 0.9      THEN 'ORANGE'
        ELSE                                                          'GREEN'
    END                 AS status,
    MIN(margin_pct)     AS worst_margin,
    SUM(CASE WHEN test_pass_int = 0 THEN 1 ELSE 0 END) AS fail_count
FROM enriched
GROUP BY product_id, test_num;
GO
