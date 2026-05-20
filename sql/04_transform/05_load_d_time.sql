-- ============================================================
-- 05_load_d_time.sql
-- Generovaný kalendář z rozsahu dat v l1.f_traces.
-- Originál: sql/_postgres_originals/etl_v01.sql, sekce 5.
-- KLÍČOVÁ KONVERZE: PostgreSQL generate_series → T-SQL rekurzivní CTE
--   + OPTION (MAXRECURSION 0) pro neomezenou hloubku.
-- ============================================================

TRUNCATE TABLE l1.d_time;
GO

WITH bounds AS (
    SELECT
        MIN(CAST([timestamp] AS DATE)) AS d_from,
        MAX(CAST([timestamp] AS DATE)) AS d_to
    FROM l1.f_traces
),
dates AS (
    SELECT d_from AS d, d_to FROM bounds
    UNION ALL
    SELECT DATEADD(DAY, 1, d), d_to FROM dates WHERE d < d_to
)
INSERT INTO l1.d_time
    ([date], [day], day_name, [month], month_name, [quarter], [year], is_weekend)
SELECT
    d                                      AS [date],
    DAY(d)                                 AS [day],
    DATENAME(WEEKDAY, d)                   AS day_name,
    MONTH(d)                               AS [month],
    DATENAME(MONTH, d)                     AS month_name,
    DATEPART(QUARTER, d)                   AS [quarter],
    YEAR(d)                                AS [year],
    CASE WHEN DATEPART(WEEKDAY, d) IN (1, 7) THEN 1 ELSE 0 END AS is_weekend
FROM dates
OPTION (MAXRECURSION 0);
GO
