-- ============================================================
-- 03_load_connections.sql
-- Zdroj: l1.d_limit + l0.traces_wide → l1.connections
-- Aktivní kombinace product_id × test_num = existuje v d_limit
-- a zároveň existuje alespoň jedna nenulová naměřená hodnota v traces_wide.
-- Originál: sql/_postgres_originals/etl_v01.sql, sekce 3.
-- ============================================================

TRUNCATE TABLE l1.connections;
GO

INSERT INTO l1.connections (product_id, test_num, active, notes)
SELECT DISTINCT
    l.product_id,
    l.test_num,
    CAST(1 AS BIT)  AS active,
    NULL            AS notes
FROM l1.d_limit l
WHERE EXISTS (
    SELECT 1
    FROM l0.traces_wide f
    CROSS APPLY (VALUES
        ('TP010', f.TP010), ('TP012', f.TP012), ('TP013', f.TP013), ('TP014', f.TP014),
        ('TP015', f.TP015), ('TP016', f.TP016), ('TP017', f.TP017), ('TP018', f.TP018),
        ('TP019', f.TP019), ('TP020', f.TP020), ('TP021', f.TP021), ('TP022', f.TP022),
        ('TP023', f.TP023), ('TP024', f.TP024), ('TP025', f.TP025), ('TP026', f.TP026),
        ('TP027', f.TP027), ('TP028', f.TP028), ('TP029', f.TP029), ('TP030', f.TP030),
        ('TP031', f.TP031), ('TP032', f.TP032), ('TP033', f.TP033), ('TP034', f.TP034),
        ('TP035', f.TP035), ('TP036', f.TP036), ('TP037', f.TP037), ('TP038', f.TP038),
        ('TP039', f.TP039), ('TP040', f.TP040), ('TP041', f.TP041)
    ) AS t(test_num, measured_value)
    WHERE TRY_CAST(f.id_product AS INT) = l.product_id
      AND t.test_num    = l.test_num
      AND t.measured_value IS NOT NULL
      AND t.measured_value <> 0
);
GO

