# ETL: l0 (staging) → l1 (mart)

Tyto skripty jsou přeloženy z `etl_v01.sql` (PostgreSQL) do T-SQL (Azure SQL).
Originál je v `sql/_postgres_originals/etl_v01.sql`.

## Pořadí spouštění

1. `01_load_d_product.sql` — `l0.ciselnik_products` → `l1.d_product` (RP003 jako `product_group`).
2. `02_load_d_limit.sql` — JOIN `ciselnik_products × ciselnik_mapping` s CASE mappingem všech 71 RP sloupců → `l1.d_limit`.
3. `03_load_connections.sql` — aktivní kombinace `product_id × test_num` z `l0.traces_wide`.
4. `04_load_f_traces.sql` — UNPIVOT `l0.traces_wide` (wide → long) → `l1.f_traces` (~7.5M řádků).
5. `05_load_d_time.sql` — generovaný kalendář z rozsahu dat v `l1.f_traces` (rekurzivní CTE).

**Důležité:** Watchdog trigger (`sql/06_watchdog/02_trg_watchdog.sql`) se kvůli výkonu vytváří **až po** těchto skriptech.

## Idempotence

Každý skript začíná `TRUNCATE TABLE l1.<tbl>` a pak `INSERT`. Lze spustit opakovaně.

## Testy po loadu

```sql
SELECT 'd_product' AS tbl, COUNT(*) AS cnt FROM l1.d_product
UNION ALL SELECT 'd_limit',     COUNT(*) FROM l1.d_limit
UNION ALL SELECT 'connections', COUNT(*) FROM l1.connections
UNION ALL SELECT 'f_traces',    COUNT(*) FROM l1.f_traces
UNION ALL SELECT 'd_time',      COUNT(*) FROM l1.d_time;

-- Orphan check: existuje produkt z f_traces, který není v d_product?
SELECT COUNT(*) AS orphans
FROM l1.f_traces f
LEFT JOIN l1.d_product p ON f.product_id = p.product_id
WHERE p.product_id IS NULL;

-- Sanity check: počet testů na produkt
SELECT TOP 10 product_id, COUNT(DISTINCT test_num) AS n_tests
FROM l1.f_traces
GROUP BY product_id
ORDER BY n_tests DESC;
```

## Klíčové konverze (PostgreSQL → T-SQL)

| PostgreSQL | T-SQL ekvivalent | Kde |
|---|---|---|
| `row_to_json(c1) ->> lower(c2.min_col)` | Explicitní `CASE c2.min_col WHEN 'RP001' THEN c1.RP001 …` | `02_load_d_limit.sql` |
| `CROSS JOIN LATERAL (VALUES …)` | `CROSS APPLY (VALUES …)` s explicitním prefixem `f.TPxxx` | `03/04` |
| `generate_series(start, end, '1 day')` | Rekurzivní CTE + `OPTION (MAXRECURSION 0)` | `05_load_d_time.sql` |
| `ON CONFLICT … DO UPDATE` | `TRUNCATE` + `INSERT` (idempotentní reset) | všechny |
| `TO_CHAR(d, 'Day')` | `DATENAME(WEEKDAY, d)` | `05` |
| `EXTRACT(MONTH FROM d)::INT` | `MONTH(d)` | `05` |
