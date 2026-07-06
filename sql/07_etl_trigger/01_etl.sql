-- ============================================================
-- trg_traces_wide_to_f_traces
-- Po INSERT do l0.traces_wide transformuje pouze nově vložené
-- řádky (přes pseudotabulku inserted) do l1.f_traces.
-- Filtr: měřená hodnota nenulová + kombinace v l1.connections.
-- ============================================================

CREATE OR ALTER TRIGGER l0.trg_traces_wide_to_f_traces
ON l0.traces_wide
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    -- cycle_dif_ms: rozdíl oproti předchozímu záznamu stejného pu_id
    -- Musíme vzít inserted + existující f_traces pro správný LAG přes hranici insertu
    WITH wide_with_dif AS (
        SELECT
            f.id,
            f.pu_id,
            f.id_product,
            f.[timestamp],
            f.cycle_time_ms,
            f.loop_counter,
            f.fresult,
            f.error_code,
            f.error_text,
            f.TP006,
            f.TP010, f.TP011, f.TP012, f.TP013, f.TP014,
            f.TP015, f.TP016, f.TP017, f.TP018, f.TP019,
            f.TP020, f.TP021, f.TP022, f.TP023, f.TP024,
            f.TP025, f.TP026, f.TP027, f.TP028, f.TP029,
            f.TP030, f.TP031, f.TP032, f.TP033, f.TP034,
            f.TP035, f.TP036, f.TP037, f.TP038, f.TP039,
            f.TP040, f.TP041,
            is_new = 1,
            DATEDIFF_BIG(MILLISECOND,
                LAG(f.[timestamp]) OVER (
                    PARTITION BY f.pu_id
                    ORDER BY f.[timestamp]
                ),
                f.[timestamp]
            ) AS cycle_dif_ms
        FROM inserted f
    )
    INSERT INTO l1.f_traces
        (id, pu_id, product_id, [timestamp], cycle_time_ms, cycle_dif_ms, loop_counter,
         fresult, error_code, error_text, tp006, test_num, measured_value)
    SELECT
        TRY_CAST(f.id AS BIGINT)          AS id,
        f.pu_id,
        TRY_CAST(f.id_product AS INT)     AS product_id,
        f.[timestamp],
        TRY_CAST(f.cycle_time_ms AS INT)  AS cycle_time_ms,
        TRY_CAST(f.cycle_dif_ms AS INT)   AS cycle_dif_ms,
        CAST(f.loop_counter AS SMALLINT)  AS loop_counter,
        TRY_CAST(f.fresult AS SMALLINT)   AS fresult,
        TRY_CAST(f.error_code AS INT)     AS error_code,
        f.error_text,
        f.TP006,
        t.test_num,
        t.measured_value
    FROM wide_with_dif f
    CROSS APPLY (VALUES
        ('TP010', f.TP010), ('TP011', f.TP011), ('TP012', f.TP012), ('TP013', f.TP013), ('TP014', f.TP014),
        ('TP015', f.TP015), ('TP016', f.TP016), ('TP017', f.TP017), ('TP018', f.TP018),
        ('TP019', f.TP019), ('TP020', f.TP020), ('TP021', f.TP021), ('TP022', f.TP022),
        ('TP023', f.TP023), ('TP024', f.TP024), ('TP025', f.TP025), ('TP026', f.TP026),
        ('TP027', f.TP027), ('TP028', f.TP028), ('TP029', f.TP029), ('TP030', f.TP030),
        ('TP031', f.TP031), ('TP032', f.TP032), ('TP033', f.TP033), ('TP034', f.TP034),
        ('TP035', f.TP035), ('TP036', f.TP036), ('TP037', f.TP037), ('TP038', f.TP038),
        ('TP039', f.TP039), ('TP040', f.TP040), ('TP041', f.TP041)
    ) AS t(test_num, measured_value)
    WHERE t.measured_value IS NOT NULL
      AND t.measured_value <> 0
      AND TRY_CAST(f.id AS BIGINT) IS NOT NULL
      AND EXISTS (
          SELECT 1 FROM l1.connections c
          WHERE c.product_id = TRY_CAST(f.id_product AS INT)
            AND c.test_num   = t.test_num
            AND c.active     = 1
      );
      
    -- d_time: doplnit případné nové datumy (ignoruje existující)
    INSERT INTO l1.d_time
        ([date], [day], day_name, [month], month_name, [quarter], [year], is_weekend)
    SELECT DISTINCT
        CAST(f.[timestamp] AS DATE)                                    AS [date],
        DAY(f.[timestamp])                                             AS [day],
        DATENAME(WEEKDAY, f.[timestamp])                               AS day_name,
        MONTH(f.[timestamp])                                           AS [month],
        DATENAME(MONTH, f.[timestamp])                                 AS month_name,
        DATEPART(QUARTER, f.[timestamp])                               AS [quarter],
        YEAR(f.[timestamp])                                            AS [year],
        CASE WHEN DATEPART(WEEKDAY, f.[timestamp]) IN (1,7) THEN 1
             ELSE 0 END                                                AS is_weekend
    FROM inserted f
    WHERE f.[timestamp] IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM l1.d_time dt
          WHERE dt.[date] = CAST(f.[timestamp] AS DATE)
      );

END;
GO