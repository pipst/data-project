-- l1.d_limit — limity testů (min/max/value) pro každý produkt × test.
-- unit zatím NULL (zdroj v ciselnik2.csv chybí; doplní se později).
IF OBJECT_ID('l1.d_limit', 'U') IS NOT NULL
    DROP TABLE l1.d_limit;
GO

CREATE TABLE l1.d_limit (
    product_id  INT           NOT NULL,
    valid_from  DATE          NOT NULL,
    valid_to    DATE          NULL,
    test_num    VARCHAR(8)    NOT NULL,
    group_name  VARCHAR(20)   NULL,
    descr       VARCHAR(120)  NULL,
    unit        VARCHAR(20)   NULL,
    limit_min   DECIMAL(18,6) NULL,
    limit_max   DECIMAL(18,6) NULL,
    limit_value DECIMAL(18,6) NULL,
    CONSTRAINT pk_d_limit PRIMARY KEY (product_id, test_num, valid_from)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'idx_d_limit_product_test')
    CREATE INDEX idx_d_limit_product_test ON l1.d_limit (product_id, test_num);
GO
