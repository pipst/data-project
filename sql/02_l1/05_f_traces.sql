-- l1.f_traces — fakty (long format, jeden řádek = jedno měření TP testu na jednom kusu).
IF OBJECT_ID('l1.f_traces', 'U') IS NOT NULL
    DROP TABLE l1.f_traces;
GO

CREATE TABLE l1.f_traces (
    id             BIGINT        NOT NULL,
    pu_id          VARCHAR(40)   NULL,
    product_id     INT           NULL,
    [timestamp]    DATETIME2     NULL,
    cycle_time_ms  INT           NULL,
    cycle_dif_ms   INT           NULL,
    loop_counter   SMALLINT      NULL,
    fresult        SMALLINT      NULL,
    error_code     INT           NULL,
    error_text     VARCHAR(120)  NULL,
    TP006          VARCHAR(255)  NULL,
    test_num       VARCHAR(8)    NOT NULL,
    measured_value DECIMAL(18,6) NULL,
    CONSTRAINT pk_f_traces PRIMARY KEY (id, test_num)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'idx_f_traces_product_test')
    CREATE INDEX idx_f_traces_product_test ON l1.f_traces (product_id, test_num);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'idx_f_traces_timestamp')
    CREATE INDEX idx_f_traces_timestamp ON l1.f_traces ([timestamp]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'idx_f_traces_pu_loop')
    CREATE INDEX idx_f_traces_pu_loop ON l1.f_traces (pu_id, loop_counter);
GO
