-- ============================================================
-- l0.ciselnik_mapping — raw kopie ciselnik2.csv (TP → RP mapping).
-- Tabulka mapuje testy (TP010..TP041) na sloupce limitů v ciselnik_products
-- (min_col, max_col, val_col) — viz transformace 02_load_d_limit.sql.
-- ============================================================

IF OBJECT_ID('l0.ciselnik_mapping', 'U') IS NOT NULL
    DROP TABLE l0.ciselnik_mapping;
GO

CREATE TABLE l0.ciselnik_mapping (
    group_name  VARCHAR(40)   NULL,
    description VARCHAR(255)  NULL,
    test_num    VARCHAR(8)    NULL,
    min_col     VARCHAR(10)   NULL,
    max_col     VARCHAR(10)   NULL,
    val_col     VARCHAR(10)   NULL
);
GO
