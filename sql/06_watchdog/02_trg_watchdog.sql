-- ============================================================
-- sp_watchdog_check + trg_watchdog_consecutive_fails
-- Po INSERT do l1.f_traces zkontroluje, zda poslední 2 měření selhala;
-- pokud ano, zapíše alert do l1.watchdog_alerts.
-- Originál: sql/_postgres_originals/watchdog.sql (PostgreSQL → T-SQL).
-- Pozor: trigger používá kurzor přes `inserted` (T-SQL nemá FOR EACH ROW jako PG).
-- Pro initial bulk load se doporučuje trigger vytvořit AŽ PO 04_load_f_traces.sql.
-- ============================================================

CREATE OR ALTER PROCEDURE l1.sp_watchdog_check
    @product_id INT,
    @test_num   VARCHAR(8),
    @measured   DECIMAL(18,6)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @consecutive INT;
    DECLARE @limit_min   DECIMAL(18,6);
    DECLARE @limit_max   DECIMAL(18,6);
    DECLARE @limit_value DECIMAL(18,6);

    -- Načti limity (poslední platná verze)
    SELECT TOP 1
        @limit_min   = limit_min,
        @limit_max   = limit_max,
        @limit_value = limit_value
    FROM l1.d_limit
    WHERE product_id = @product_id AND test_num = @test_num
    ORDER BY valid_from DESC;

    -- Spočítej kolik z posledních 2 měření selhalo
    SELECT @consecutive = COUNT(*)
    FROM (
        SELECT TOP 2
            CASE
                WHEN @limit_min IS NOT NULL AND @limit_max IS NOT NULL
                     THEN CASE WHEN measured_value BETWEEN @limit_min AND @limit_max THEN 1 ELSE 0 END
                WHEN @limit_min IS NOT NULL
                     THEN CASE WHEN measured_value >= @limit_min THEN 1 ELSE 0 END
                WHEN @limit_max IS NOT NULL
                     THEN CASE WHEN measured_value <= @limit_max THEN 1 ELSE 0 END
                WHEN @limit_value IS NOT NULL
                     THEN CASE WHEN measured_value = @limit_value THEN 1 ELSE 0 END
                ELSE 1
            END AS pass
        FROM l1.f_traces
        WHERE product_id = @product_id AND test_num = @test_num
        ORDER BY [timestamp] DESC
    ) sub
    WHERE pass = 0;

    IF @consecutive >= 2
    BEGIN
        INSERT INTO l1.watchdog_alerts
            (product_id, test_num, fail_count, last_value,
             limit_min, limit_max, limit_value, [message])
        VALUES (
            @product_id, @test_num, @consecutive, @measured,
            @limit_min, @limit_max, @limit_value,
            CONCAT('ALERT: ', @consecutive, ' consecutive fails for product ',
                   @product_id, ' test ', @test_num,
                   ' (last value: ', CAST(@measured AS VARCHAR(30)), ')')
        );
    END
END;
GO

CREATE OR ALTER TRIGGER l1.trg_watchdog_consecutive_fails
ON l1.f_traces
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @product_id INT;
    DECLARE @test_num   VARCHAR(8);
    DECLARE @measured   DECIMAL(18,6);

    DECLARE ins_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT product_id, test_num, measured_value FROM inserted;

    OPEN ins_cursor;
    FETCH NEXT FROM ins_cursor INTO @product_id, @test_num, @measured;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC l1.sp_watchdog_check @product_id, @test_num, @measured;
        FETCH NEXT FROM ins_cursor INTO @product_id, @test_num, @measured;
    END;

    CLOSE ins_cursor;
    DEALLOCATE ins_cursor;
END;
GO
