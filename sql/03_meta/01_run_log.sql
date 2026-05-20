-- meta.run_log — log spouštění SQL skriptů (manuálně i z CI).
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'meta')
    EXEC('CREATE SCHEMA meta');
GO

IF OBJECT_ID('meta.run_log', 'U') IS NOT NULL
    DROP TABLE meta.run_log;
GO

CREATE TABLE meta.run_log (
    id            INT IDENTITY(1,1) PRIMARY KEY,
    run_id        VARCHAR(64)   NOT NULL,  -- timestamp běhu YYYYMMDD_HHMMSS
    script_name   VARCHAR(200)  NOT NULL,
    started_at    DATETIME2     NOT NULL DEFAULT SYSDATETIME(),
    finished_at   DATETIME2     NULL,
    status        VARCHAR(10)   NOT NULL,  -- 'running' | 'ok' | 'error'
    rows_affected INT           NULL,
    error_message VARCHAR(MAX)  NULL,
    triggered_by  VARCHAR(100)  NULL
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'idx_run_log_run_id')
    CREATE INDEX idx_run_log_run_id ON meta.run_log (run_id);
GO
