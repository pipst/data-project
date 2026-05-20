-- ============================================================
-- l1.watchdog_alerts — tabulka pro zachytávání alertů.
-- Naplňuje ji procedura sp_watchdog_check volaná z triggeru.
-- Originál: sql/_postgres_originals/watchdog.sql (PostgreSQL).
-- ============================================================

IF OBJECT_ID('l1.watchdog_alerts', 'U') IS NOT NULL
    DROP TABLE l1.watchdog_alerts;
GO

CREATE TABLE l1.watchdog_alerts (
    alert_id     INT IDENTITY(1,1) PRIMARY KEY,
    product_id   INT           NULL,
    test_num     VARCHAR(8)    NULL,
    triggered_at DATETIME2     NOT NULL DEFAULT SYSDATETIME(),
    fail_count   INT           NULL,
    last_value   DECIMAL(18,6) NULL,
    limit_min    DECIMAL(18,6) NULL,
    limit_max    DECIMAL(18,6) NULL,
    [message]    VARCHAR(MAX)  NULL
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'idx_watchdog_alerts_product_test')
    CREATE INDEX idx_watchdog_alerts_product_test
        ON l1.watchdog_alerts (product_id, test_num);
GO
