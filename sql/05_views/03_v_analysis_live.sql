-- ============================================================
-- l1.v_analysis_live — analytické view pro live Power BI dashboard.
-- Stejná logika jako v_analysis, ale filtruje jen poslední 3 měsíce.
-- Originál: sql/_postgres_originals/view.sql (PostgreSQL).
-- ============================================================

CREATE OR ALTER VIEW l1.v_analysis_live AS
SELECT
    f.id,
    f.pu_id,
    f.product_id,
    p.product_group,
    f.[timestamp],
    t.[year],
    t.[month],
    t.month_name,
    f.cycle_time_ms,
    f.loop_counter,
    f.fresult,
    f.error_code,
    f.error_text,
    f.test_num,
    l.group_name,
    l.descr             AS test_description,
    f.measured_value,
    l.limit_min,
    l.limit_max,
    l.limit_value,
    -- Pass/fail logika (BIT, NULL pokud nelze rozhodnout)
    CASE
        WHEN l.limit_min IS NOT NULL AND l.limit_max IS NOT NULL
             THEN CASE WHEN f.measured_value BETWEEN l.limit_min AND l.limit_max THEN 1 ELSE 0 END
        WHEN l.limit_min IS NOT NULL AND l.limit_max IS NULL
             THEN CASE WHEN f.measured_value >= l.limit_min THEN 1 ELSE 0 END
        WHEN l.limit_max IS NOT NULL AND l.limit_min IS NULL
             THEN CASE WHEN f.measured_value <= l.limit_max THEN 1 ELSE 0 END
        WHEN l.limit_value IS NOT NULL
             THEN CASE WHEN f.measured_value = l.limit_value THEN 1 ELSE 0 END
    END                 AS test_pass,
    -- Marginy
    CASE WHEN l.limit_min IS NOT NULL
         THEN f.measured_value - l.limit_min
    END                 AS margin_from_min,
    CASE WHEN l.limit_max IS NOT NULL
         THEN l.limit_max - f.measured_value
    END                 AS margin_to_max,
    -- Relativní pozice v okně (jen pro oboustranný limit)
    CASE WHEN l.limit_min IS NOT NULL AND l.limit_max IS NOT NULL
              AND l.limit_max <> l.limit_min
         THEN (f.measured_value - l.limit_min)
              / (l.limit_max - l.limit_min)
    END                 AS margin_pct
FROM l1.f_traces f
LEFT JOIN l1.d_limit   l ON l.product_id = f.product_id AND l.test_num = f.test_num
LEFT JOIN l1.d_product p ON p.product_id = f.product_id
LEFT JOIN l1.d_time    t ON t.[date]      = CAST(f.[timestamp] AS DATE)
WHERE f.[timestamp] >= DATEADD(MONTH, -3, SYSDATETIME());
GO
