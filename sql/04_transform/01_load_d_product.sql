-- ============================================================
-- 01_load_d_product.sql
-- Zdroj: l0.ciselnik_products → l1.d_product
-- product_group = RP003 (textová skupina).
-- Filtr: vyřadit '#NENÍ_K_DISPOZICI' (už by mělo být NULL po importu, ale jistota).
-- Originál: sql/_postgres_originals/etl_v01.sql (sekce 1).
-- ============================================================

TRUNCATE TABLE l1.d_product;
GO

INSERT INTO l1.d_product (product_id, valid_from, valid_to, product_group)
SELECT DISTINCT
    TRY_CAST(product_id AS INT)          AS product_id,
    CAST(valid_from AS DATE)             AS valid_from,
    CAST(valid_to   AS DATE)             AS valid_to,
    RP003                                AS product_group
FROM l0.ciselnik_products
WHERE product_id IS NOT NULL
  AND product_id <> '#NENÍ_K_DISPOZICI'
  AND TRY_CAST(product_id AS INT) IS NOT NULL
  AND valid_from IS NOT NULL;
GO
