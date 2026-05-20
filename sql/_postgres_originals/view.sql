CREATE OR REPLACE VIEW v_analysis AS
SELECT
    f.id,
    f.pu_id,
    f.product_id,
    p.product_group,
    f.timestamp,
    t.year,
    t.month,
    t.month_name,
    f.cycle_time_ms,
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
    -- Pass/fail logika
    CASE
        WHEN l.limit_min IS NOT NULL AND l.limit_max IS NOT NULL
             THEN f.measured_value BETWEEN l.limit_min AND l.limit_max
        WHEN l.limit_min IS NOT NULL AND l.limit_max IS NULL
             THEN f.measured_value >= l.limit_min
        WHEN l.limit_max IS NOT NULL AND l.limit_min IS NULL
             THEN f.measured_value <= l.limit_max
        WHEN l.limit_value IS NOT NULL
             THEN f.measured_value = l.limit_value
    END                 AS test_pass,
    -- Marginy
    CASE WHEN l.limit_min IS NOT NULL
         THEN f.measured_value - l.limit_min END AS margin_from_min,
    CASE WHEN l.limit_max IS NOT NULL
         THEN l.limit_max - f.measured_value END AS margin_to_max,
    -- Relativní pozice v okně (jen pro oboustranný limit)
    CASE WHEN l.limit_min IS NOT NULL AND l.limit_max IS NOT NULL
              AND l.limit_max != l.limit_min
         THEN (f.measured_value - l.limit_min)
              / (l.limit_max - l.limit_min)
    END                 AS margin_pct
FROM f_traces f
LEFT JOIN d_limit   l ON l.product_id = f.product_id AND l.test_num = f.test_num
LEFT JOIN d_product p ON p.product_id = f.product_id
LEFT JOIN d_time    t ON t.date       = f.timestamp::DATE;