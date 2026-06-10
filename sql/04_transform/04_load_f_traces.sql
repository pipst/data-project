-- ============================================================
-- 04_load_f_traces.sql
-- Zdroj: l0.traces_wide → l1.f_traces (UNPIVOT wide → long, ~7.5M řádků)
-- Filtr: měřená hodnota nenulová a kombinace (product_id, test_num) v connections.
-- Originál: sql/_postgres_originals/etl_v01.sql, sekce 4.
-- KLÍČOVÁ KONVERZE: PostgreSQL CROSS JOIN LATERAL → T-SQL CROSS APPLY,
--   všechny hodnoty s prefixem f. (jinak T-SQL nepozná referenci na vnější tabulku).
-- ============================================================

TRUNCATE TABLE l1.f_traces;
GO

WITH wide_with_dif AS (
    SELECT
        f.*,
        DATEDIFF_BIG(MILLISECOND,
            LAG(f.[timestamp]) OVER (
                PARTITION BY f.pu_id
                ORDER BY f.[timestamp]
            ),
            f.[timestamp]
        ) AS cycle_dif_ms
    FROM l0.traces_wide f
    WHERE TRY_CAST(f.id AS BIGINT) IS NOT NULL
)
INSERT INTO l1.f_traces
    (id, pu_id, product_id, [timestamp], cycle_time_ms, cycle_dif_ms, loop_counter,
     fresult, error_code, error_text, tp006, test_num, measured_value)
SELECT
    TRY_CAST(f.id AS BIGINT)         AS id,
    f.pu_id,
    TRY_CAST(f.id_product AS INT)    AS product_id,
    f.[timestamp],
    TRY_CAST(f.cycle_time_ms AS INT) AS cycle_time_ms,
    TRY_CAST(f.cycle_dif_ms AS INT)  AS cycle_dif_ms,
    CAST(f.loop_counter AS SMALLINT) AS loop_counter,
    TRY_CAST(f.fresult AS SMALLINT)  AS fresult,
    TRY_CAST(f.error_code AS INT)    AS error_code,
    f.error_text,
    f.TP006,
    t.test_num,
    t.measured_value
FROM wide_with_dif f
CROSS APPLY (VALUES
    ('TP010', f.TP010), ('TP011', f.TP011), ('TP012', f.TP012), ('TP013', f.TP013), ('TP014', f.TP014),
    ('TP015', f.TP015), ('TP016', f.TP016), ('TP017', f.TP017), ('TP018', f.TP018),
    ('TP019', f.TP019), ('TP020', f.TP020), ('TP021', f.TP021), ('TP022', f.TP022),
    ('TP023', f.TP023), ('TP024', f.TP024), ('TP025', f.TP025), ('TP026', f.TP026),
    ('TP027', f.TP027), ('TP028', f.TP028), ('TP029', f.TP029), ('TP030', f.TP030),
    ('TP031', f.TP031), ('TP032', f.TP032), ('TP033', f.TP033), ('TP034', f.TP034),
    ('TP035', f.TP035), ('TP036', f.TP036), ('TP037', f.TP037), ('TP038', f.TP038),
    ('TP039', f.TP039), ('TP040', f.TP040), ('TP041', f.TP041)
) AS t(test_num, measured_value)
WHERE t.measured_value IS NOT NULL
  AND t.measured_value <> 0
  AND EXISTS (
      SELECT 1 FROM l1.connections c
      WHERE c.product_id = TRY_CAST(f.id_product AS INT)
        AND c.test_num   = t.test_num
        AND c.active     = 1
  );
GO
