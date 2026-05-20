-- ============================================================
-- Schémata: l0 (raw), l1 (mart), meta (run_log)
-- Idempotent: bezpečné spustit opakovaně.
-- Views a watchdog tabulky/triggery žijí ve schématu l1.
-- ============================================================

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'l0')
    EXEC('CREATE SCHEMA l0');
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'l1')
    EXEC('CREATE SCHEMA l1');
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'meta')
    EXEC('CREATE SCHEMA meta');
GO
