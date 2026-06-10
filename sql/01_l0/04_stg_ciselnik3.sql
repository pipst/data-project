-- ============================================================
-- l0.ciselnik_voltage — raw kopie ciselnik3.csv (TP → RP mapping).
-- Tabulka mapuje jmenovité napětí pro jednotlivá product_id
-- ============================================================

IF OBJECT_ID('l0.ciselnik_voltage', 'U') IS NOT NULL
    DROP TABLE l0.ciselnik_voltage;
GO

CREATE TABLE l0.ciselnik_voltage (
    product_id  VARCHAR(40)   NULL,
    mlfb        VARCHAR(1)    NULL,
    group_name  VARCHAR(8)    NULL,
    type        VARCHAR(1)    NULL,
    unom_min    INT           NULL,
    unom_max    INT           NULL,
    unom        INT           NULL
);
GO
