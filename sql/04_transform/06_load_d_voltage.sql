-- ============================================================
-- 01_load_d_voltage.sql
-- Zdroj: l0.ciselnik_voltage → l1.d_voltage
-- product_group = RP003 (textová skupina).
-- Filtr: vyřadit '#NENÍ_K_DISPOZICI' (už by mělo být NULL po importu, ale jistota).
-- Originál: sql/_postgres_originals/etl_v01.sql (sekce 1).
-- ============================================================

TRUNCATE TABLE l1.d_voltage;
GO

INSERT INTO l1.d_voltage (product_id, unom_min, unom_max, unom)
SELECT DISTINCT
    TRY_CAST(product_id AS INT)          AS product_id,
    CAST(unom_min AS INT)                AS unom_min,
    CAST(unom_max   AS INT)              AS unom_max,
    CAST(unom   AS INT)                  AS unom
FROM l0.ciselnik_voltage
WHERE product_id IS NOT NULL
  AND product_id <> '#NENÍ_K_DISPOZICI'
  AND TRY_CAST(product_id AS INT) IS NOT NULL;
GO
