# Real-time ETL trigger (l0 → l1)

Trigger `l0.trg_traces_wide_to_f_traces` automaticky transformuje **nově vložené řádky** z `l0.traces_wide` (wide formát) do `l1.f_traces` (long formát) **AFTER INSERT**. Plus doplňuje nové datumy do `l1.d_time`.

## Účel

Umožnit **live ingest** výrobních dat:
1. Klient INSERTne řádek do `l0.traces_wide` (1 kus = 1 řádek se 31 TP měřeními)
2. Trigger UNPIVOTuje 31 TP měření do 31 řádků v `l1.f_traces`
3. Doplní `l1.d_time` o nový datum (pokud ještě nebyl)
4. Existující watchdog trigger na `l1.f_traces` reaguje na consecutive fails

Bez tohoto triggeru by ETL musel běžet ručně přes `sql/04_transform/04_load_f_traces.sql` (jednorázový rebuild celé `f_traces`).

## Co dělá konkrétně

```sql
CREATE OR ALTER TRIGGER l0.trg_traces_wide_to_f_traces
ON l0.traces_wide
AFTER INSERT
AS BEGIN
    -- 1. UNPIVOT inserted (jen nově vložené řádky)
    INSERT INTO l1.f_traces (id, pu_id, product_id, [timestamp], ...,
                              test_num, measured_value)
    SELECT ... FROM inserted f CROSS APPLY (VALUES
        ('TP010', f.TP010), ('TP012', f.TP012), ...
    ) AS t(test_num, measured_value)
    WHERE t.measured_value IS NOT NULL AND t.measured_value <> 0
      AND EXISTS (SELECT 1 FROM l1.connections c
                  WHERE c.product_id = TRY_CAST(f.id_product AS INT)
                    AND c.test_num = t.test_num AND c.active = 1);

    -- 2. d_time: doplnit nové datumy (idempotentně)
    INSERT INTO l1.d_time (...)
    SELECT DISTINCT ... FROM inserted
    WHERE NOT EXISTS (SELECT 1 FROM l1.d_time dt WHERE dt.[date] = CAST(f.[timestamp] AS DATE));
END
```

## Filtry v triggeru

- `measured_value IS NOT NULL AND <> 0` — vyřadit nulová měření (test se pro daný kus nedělal)
- `EXISTS v l1.connections` — vyřadit kombinace `(product, test)` které pro produkt nejsou aktivní
- `TRY_CAST(id AS BIGINT) IS NOT NULL` — jen řádky s validním ID

## Pořadí instalace

Trigger se nasazuje **až po naplnění `l1.connections`**, jinak by nic neinsertl (EXISTS filtr by vyloučil vše). Správné pořadí:

1. DDL: `sql/00_schemas.sql` → `01_l0/` → `02_l1/` → `03_meta/` → `06_watchdog/01_watchdog_alerts.sql`
2. Import raw dat: `python scripts/02_import_l0.py`
3. Jednorázový ETL: `sql/04_transform/*` (naplní `l1.connections`, `l1.d_limit`, `l1.f_traces`, …)
4. Trigger: **až teď** `sql/07_etl_trigger/01_etl.sql`
5. Watchdog trigger: `sql/06_watchdog/02_trg_watchdog.sql`

> ⚠ Pokud bys naopak naimportoval `l0.traces_wide` s aktivním triggerem (před krokem 3), zaplnil bys `l1.f_traces` 2× (jednou triggerem, podruhé `04_transform/04_load_f_traces.sql`).

## Test funkčnosti

Po instalaci ověř INSERT-ovým testem:

```sql
-- Před: spočítej rows
SELECT COUNT(*) AS rows_before FROM l1.f_traces;  -- např. 5,692,867

-- Test INSERT do l0 (smazat hned po testu!)
INSERT INTO l0.traces_wide (id, pu_id, id_product, [timestamp],
                            cycle_time_ms, loop_counter, fresult,
                            TP010, TP020, TP040)
VALUES ('99999999', '999', '124', SYSDATETIME(), 900, 1, 0, 5.4, 5.4, -1.1);

-- Po: zkontroluj, že 1 řádek v l0 vygeneroval N řádků v f_traces
SELECT COUNT(*) AS rows_after FROM l1.f_traces;
-- Rozdíl = počet aktivních TP testů pro produkt 124, které mají non-zero hodnotu

-- Smazat test
DELETE FROM l1.f_traces WHERE id = 99999999;
DELETE FROM l0.traces_wide WHERE id = '99999999';
```

## Souvislosti

- **Watchdog trigger** (`sql/06_watchdog/02_trg_watchdog.sql`) běží na `l1.f_traces` AFTER INSERT — tj. kaskádově se aktivuje po každém triggeru `trg_traces_wide_to_f_traces`.
- **Simulator** (`scripts/04_simulator.py`) využívá tenhle trigger — INSERTuje jen do `l0.traces_wide`, ostatní vrstvy doplní triggery automaticky.

## Pozor na výkon

Trigger zpracovává `inserted` set-based (jeden SQL statement přes všechny vložené řádky), takže i bulk INSERT funguje. Ale pro **iniciální load 244k řádků** je pořád rychlejší použít `sql/04_transform/04_load_f_traces.sql` (vypnout trigger nebo neinstalovat ho před iniciálním importem).
