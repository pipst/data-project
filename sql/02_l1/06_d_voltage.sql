-- l1.d_voltage — dimenze jmenovitého napětí.
IF OBJECT_ID('l1.d_voltage', 'U') IS NOT NULL
    DROP TABLE l1.d_voltage;
GO

CREATE TABLE l1.d_voltage (
    product_id    INT          NOT NULL,
    unom_min      INT          NULL,
    unom_max      INT          NULL,
    unom          INT          NULL
    CONSTRAINT pk_d_voltage PRIMARY KEY (product_id)
);
GO
