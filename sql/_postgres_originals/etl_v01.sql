-- ============================================================
-- ETL: staging → datový model
-- ============================================================

-- ── 0. Vytvoření cílových tabulek ───────────────────────────

CREATE TABLE IF NOT EXISTS d_product (
    product_id    TEXT PRIMARY KEY,
    product_group TEXT,
    valid_from    TIMESTAMPTZ,
    valid_to      TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS d_limit (
    product_id  TEXT,
    test_num    TEXT,
    valid_from  TIMESTAMPTZ,
    valid_to    TIMESTAMPTZ,
    group_name  TEXT,
    descr       TEXT,
    limit_min   FLOAT,
    limit_max   FLOAT,
    limit_value FLOAT,
    PRIMARY KEY (product_id, test_num)
);

CREATE TABLE IF NOT EXISTS connections (
    product_id TEXT,
    test_num   TEXT,
    active     BOOLEAN,
    PRIMARY KEY (product_id, test_num)
);

CREATE TABLE IF NOT EXISTS f_traces (
    id            TEXT,
    pu_id         TEXT,
    product_id    TEXT,
    timestamp     TIMESTAMPTZ,
    cycle_time_ms FLOAT,
    loop_counter  INT,
    fresult       TEXT,
    error_code    TEXT,
    error_text    TEXT,
    test_num      TEXT,
    measured_value FLOAT
);

CREATE TABLE IF NOT EXISTS d_time (
    date        DATE PRIMARY KEY,
    day         VARCHAR(10),
    month       INT,
    month_name  VARCHAR(20),
    year        INT
);

-- ── 1. d_product ────────────────────────────────────────────
-- Zdrojem je ciselnik1: product_id + RP003 jako product_group
-- Vyřadit #NENÍ_K_DISPOZICI

INSERT INTO d_product (product_id, product_group, valid_from, valid_to)
SELECT DISTINCT
    product_id,
    RP003       AS product_group,
    valid_from,
    valid_to
FROM stg_ciselnik1
WHERE product_id != '#NENÍ_K_DISPOZICI'
ON CONFLICT (product_id) DO UPDATE
    SET product_group = EXCLUDED.product_group,
        valid_from    = EXCLUDED.valid_from,
        valid_to      = EXCLUDED.valid_to;

-- ── 2. d_limit ──────────────────────────────────────────────
-- Unpivot ciselnik1 přes ciselnik2 pomocí row_to_json triku
-- Vyřadit záznamy kde min i max = 0 (test se pro produkt nedělá)

INSERT INTO d_limit (product_id, test_num, valid_from, valid_to,
                     group_name, descr, limit_min, limit_max, limit_value)
SELECT
    c1.product_id,
    c2.test_num,
    c1.valid_from,
    c1.valid_to,
    c2.group_name,
    c2.description                                                          AS descr,
    CASE WHEN c2.min_col IS NOT NULL
         THEN (row_to_json(c1) ->> lower(c2.min_col))::FLOAT
    END                                                                     AS limit_min,
    CASE WHEN c2.max_col IS NOT NULL
         THEN (row_to_json(c1) ->> lower(c2.max_col))::FLOAT
    END                                                                     AS limit_max,
    CASE WHEN c2.val_col IS NOT NULL
         THEN (row_to_json(c1) ->> lower(c2.val_col))::FLOAT
    END                                                                     AS limit_value
FROM stg_ciselnik1 c1
CROSS JOIN stg_ciselnik2 c2
WHERE c1.product_id != '#NENÍ_K_DISPOZICI'
  -- Vyřadit testy kde obě hranice jsou 0 = test se nedělá
  AND NOT (
        COALESCE((row_to_json(c1) ->> lower(c2.min_col))::FLOAT, 0) = 0
    AND COALESCE((row_to_json(c1) ->> lower(c2.max_col))::FLOAT, 0) = 0
    AND c2.val_col IS NULL
  )
ON CONFLICT (product_id, test_num) DO UPDATE
    SET limit_min   = EXCLUDED.limit_min,
        limit_max   = EXCLUDED.limit_max,
        limit_value = EXCLUDED.limit_value,
        valid_from  = EXCLUDED.valid_from,
        valid_to    = EXCLUDED.valid_to;

-- ── 3. connections ───────────────────────────────────────────
-- Aktivní kombinace product_id + test_num = existuje záznam v d_limit

INSERT INTO connections (product_id, test_num, active)
SELECT
    l.product_id,
    l.test_num,
    TRUE AS active
FROM d_limit l
-- Vyřadit kombinace kde všechny naměřené hodnoty ve fact jsou 0
WHERE EXISTS (
    SELECT 1
    FROM stg_fact f
    CROSS JOIN LATERAL (VALUES
        ('TP010', TP010), ('TP012', TP012), ('TP013', TP013),
        ('TP014', TP014), ('TP015', TP015), ('TP016', TP016),
        ('TP017', TP017), ('TP018', TP018), ('TP019', TP019),
        ('TP020', TP020), ('TP021', TP021), ('TP022', TP022),
        ('TP023', TP023), ('TP024', TP024), ('TP025', TP025),
        ('TP026', TP026), ('TP027', TP027), ('TP028', TP028),
        ('TP029', TP029), ('TP030', TP030), ('TP031', TP031),
        ('TP032', TP032), ('TP033', TP033), ('TP034', TP034),
        ('TP035', TP035), ('TP036', TP036), ('TP037', TP037),
        ('TP038', TP038), ('TP039', TP039), ('TP040', TP040),
        ('TP041', TP041)
    ) AS t(test_num, measured_value)
    WHERE f.id_product  = l.product_id
      AND t.test_num    = l.test_num
      AND t.measured_value IS NOT NULL
      AND t.measured_value != 0   -- alespoň jedna nenulová hodnota existuje
)
ON CONFLICT (product_id, test_num) DO UPDATE
    SET active = EXCLUDED.active;

-- ── 4. f_traces ─────────────────────────────────────────────
-- Unpivot faktové tabulky (wide → tall)
-- Vyřadit řádky kde measured_value = 0 (test se nedělal)
-- Vyřadit kombinace které nejsou v connections (test se pro produkt nedělá)

INSERT INTO f_traces (id, pu_id, product_id, timestamp, cycle_time_ms,
                      loop_counter, fresult, error_code, error_text,
                      test_num, measured_value)
SELECT
    f.id, f.pu_id, f.id_product AS product_id,
    f.timestamp, f.cycle_time_ms, f.loop_counter,
    f.fresult, f.error_code, f.error_text,
    t.test_num, t.measured_value
FROM stg_fact f
CROSS JOIN LATERAL (VALUES
    ('TP010', TP010), ('TP012', TP012), ('TP013', TP013),
    ('TP014', TP014), ('TP015', TP015), ('TP016', TP016),
    ('TP017', TP017), ('TP018', TP018), ('TP019', TP019),
    ('TP020', TP020), ('TP021', TP021), ('TP022', TP022),
    ('TP023', TP023), ('TP024', TP024), ('TP025', TP025),
    ('TP026', TP026), ('TP027', TP027), ('TP028', TP028),
    ('TP029', TP029), ('TP030', TP030), ('TP031', TP031),
    ('TP032', TP032), ('TP033', TP033), ('TP034', TP034),
    ('TP035', TP035), ('TP036', TP036), ('TP037', TP037),
    ('TP038', TP038), ('TP039', TP039), ('TP040', TP040),
    ('TP041', TP041)
) AS t(test_num, measured_value)
-- Vyřadit nuly (test se nedělal) a NULL
WHERE t.measured_value IS NOT NULL
  AND t.measured_value != 0
  -- Pouze aktivní kombinace product_id + test_num
  AND EXISTS (
      SELECT 1 FROM connections c
      WHERE c.product_id = f.id_product
        AND c.test_num   = t.test_num
        AND c.active     = TRUE
  );

-- ── 5. d_time ───────────────────────────────────────────────
-- Generovat kalendář z rozsahu dat v f_traces

INSERT INTO d_time (date, day, month, month_name, year)
SELECT
    d::DATE                                      AS date,
    TO_CHAR(d, 'Day')                            AS day,
    EXTRACT(MONTH FROM d)::INT                   AS month,
    TO_CHAR(d, 'Month')                          AS month_name,
    EXTRACT(YEAR FROM d)::INT                    AS year
FROM generate_series(
    (SELECT MIN(timestamp)::DATE FROM f_traces),
    (SELECT MAX(timestamp)::DATE FROM f_traces),
    INTERVAL '1 day'
) AS g(d)
ON CONFLICT (date) DO NOTHING;

-- ── 6. Indexy pro výkon ──────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_f_traces_product   ON f_traces (product_id);
CREATE INDEX IF NOT EXISTS idx_f_traces_test      ON f_traces (test_num);
CREATE INDEX IF NOT EXISTS idx_f_traces_timestamp ON f_traces (timestamp);
CREATE INDEX IF NOT EXISTS idx_d_limit_product    ON d_limit  (product_id, test_num);


