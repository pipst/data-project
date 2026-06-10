-- ============================================================
-- l0.traces_wide — raw kopie traces_gbs.csv (wide format)
-- 9 metadata sloupců + 31 TP sloupců (TP010, TP012..TP041).
-- Žádné PK, žádné indexy — surová data.
-- ============================================================

IF OBJECT_ID('l0.traces_wide', 'U') IS NOT NULL
    DROP TABLE l0.traces_wide;
GO

CREATE TABLE l0.traces_wide (
    id            VARCHAR(40)    NULL,
    pu_id         VARCHAR(40)    NULL,
    id_product    VARCHAR(40)    NULL,
    [timestamp]   DATETIME2      NULL,
    cycle_time_ms FLOAT          NULL,
    loop_counter  INT            NULL,
    fresult       VARCHAR(20)    NULL,
    error_code    VARCHAR(40)    NULL,
    error_text    VARCHAR(255)   NULL,
    TP006 VARCHAR(255),
    TP010 DECIMAL(18,6) NULL, TP011 DECIMAL(18,6) NULL, TP012 DECIMAL(18,6) NULL, TP013 DECIMAL(18,6) NULL,
    TP014 DECIMAL(18,6) NULL, TP015 DECIMAL(18,6) NULL, TP016 DECIMAL(18,6) NULL,
    TP017 DECIMAL(18,6) NULL, TP018 DECIMAL(18,6) NULL, TP019 DECIMAL(18,6) NULL,
    TP020 DECIMAL(18,6) NULL, TP021 DECIMAL(18,6) NULL, TP022 DECIMAL(18,6) NULL,
    TP023 DECIMAL(18,6) NULL, TP024 DECIMAL(18,6) NULL, TP025 DECIMAL(18,6) NULL,
    TP026 DECIMAL(18,6) NULL, TP027 DECIMAL(18,6) NULL, TP028 DECIMAL(18,6) NULL,
    TP029 DECIMAL(18,6) NULL, TP030 DECIMAL(18,6) NULL, TP031 DECIMAL(18,6) NULL,
    TP032 DECIMAL(18,6) NULL, TP033 DECIMAL(18,6) NULL, TP034 DECIMAL(18,6) NULL,
    TP035 DECIMAL(18,6) NULL, TP036 DECIMAL(18,6) NULL, TP037 DECIMAL(18,6) NULL,
    TP038 DECIMAL(18,6) NULL, TP039 DECIMAL(18,6) NULL, TP040 DECIMAL(18,6) NULL,
    TP041 DECIMAL(18,6) NULL
);
GO
