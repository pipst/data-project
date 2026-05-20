-- l1.connections — bridge mezi produktem a testem (aktivní kombinace).
IF OBJECT_ID('l1.connections', 'U') IS NOT NULL
    DROP TABLE l1.connections;
GO

CREATE TABLE l1.connections (
    product_id INT          NOT NULL,
    test_num   VARCHAR(8)   NOT NULL,
    active     BIT          NOT NULL,
    notes      VARCHAR(200) NULL,
    CONSTRAINT pk_connections PRIMARY KEY (product_id, test_num)
);
GO
