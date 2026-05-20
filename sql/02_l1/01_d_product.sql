-- l1.d_product — dimenze produktů (SCD2-like přes valid_from/valid_to).
IF OBJECT_ID('l1.d_product', 'U') IS NOT NULL
    DROP TABLE l1.d_product;
GO

CREATE TABLE l1.d_product (
    product_id    INT          NOT NULL,
    valid_from    DATE         NOT NULL,
    valid_to      DATE         NULL,
    product_group VARCHAR(40)  NULL,
    CONSTRAINT pk_d_product PRIMARY KEY (product_id, valid_from)
);
GO
