# Datový model — l0 (raw) a l1 (mart)

## Architektura — 2 vrstvy

```
data/raw/*.csv  ──Python──▶  l0 (raw 1:1)  ──SQL──▶  l1 (star schema)  ──▶  Power BI
```

- `l0` = surová data 1:1 ze zdrojových CSV. Žádná business logika, žádné PK, žádné indexy.
- `l1` = mart vrstva. Star schema, optimalizováno pro Power BI.
- `meta` = run_log pro logování spouštění SQL skriptů (CI i manuál).

## Star schema (l1)

```
                  ┌──────────────┐
                  │  d_product   │
                  │ product_id PK│
                  │ valid_from PK│
                  │ valid_to     │
                  │ product_group│
                  └───────┬──────┘
                          │
                          │ product_id
                          ▼
   ┌───────────┐    ┌──────────────┐    ┌─────────────┐
   │  d_time   │    │   f_traces   │    │  d_limit    │
   │ date PK   │◀───┤  id PK       │───▶│ product_id  │
   │ year      │    │  test_num PK │    │ test_num    │
   │ month     │    │  measured_v. │    │ valid_from  │
   │ ...       │    │  timestamp   │    │ limit_min   │
   └───────────┘    │  product_id  │    │ limit_max   │
                   │  ...         │    │ limit_value │
                   └──────┬───────┘    └─────────────┘
                          │
                          │ (product_id, test_num)
                          ▼
                   ┌──────────────┐
                   │ connections  │   bridge: aktivní kombinace
                   │ product_id PK│
                   │ test_num PK  │
                   │ active       │
                   └──────────────┘
```

Plus:
- `l1.watchdog_alerts` — alert tabulka naplňovaná triggerem `trg_watchdog_consecutive_fails` na `f_traces`
- `l1.v_analysis` — analytické view (join f_traces × d_limit × d_product × d_time s pass/fail logikou)
- `l1.v_watchdog_latest` — semafor RED/ORANGE/GREEN pro Power BI watchdog dashboard

## Popis tabulek

### l0.traces_wide
Surový dump z `traces_gbs.csv`. 9 metadata sloupců + 31 TP sloupců (`TP010`, `TP012`..`TP041`; TP011 neexistuje).
**Wide format** — jeden řádek = jeden testovaný kus, hodnoty každého testu v samostatném sloupci.

### l0.ciselnik_products
Z `ciselnik1.csv`. 5 metadata sloupců (valid_from/to, product_id, MLFB_A5E, Device_Typ) + 71 RP sloupců (`RP001..RP071`).
`RP003`, `RP004`, `RP005`, `RP009` jsou textové (skupina/MLFB), zbytek numerický (limity).

### l0.ciselnik_mapping
Z `ciselnik2.csv`. Mapuje TP testy na RP sloupce v `ciselnik_products`:
- `test_num` (např. `TP010`)
- `min_col` (např. `RP030` — odpovídající minimum limit v `ciselnik1`)
- `max_col`
- `val_col` (pro testy s přesnou hodnotou, ne rozsahem)

### l1.f_traces (fact, long format)
Po UNPIVOTu z `l0.traces_wide` přes `ciselnik_mapping`. **Jeden řádek = jedno měření jednoho testu na jednom kusu.**
- PK: `(id, test_num)`
- ~7.5M řádků (244k kusů × ~31 testů, mínus filtrované nuly)
- Indexy: `(product_id, test_num)`, `[timestamp]`, `(pu_id, loop_counter)`

### l1.d_product (dimenze)
- PK: `(product_id, valid_from)` — podpora SCD-like verzování
- `product_group` = `RP003` z ciselnik (textová skupina)

### l1.d_limit (dimenze testů × produktu)
- PK: `(product_id, test_num, valid_from)`
- Sloupce `limit_min` / `limit_max` / `limit_value` se plní z `ciselnik_products` přes mapování `ciselnik_mapping`.
- `unit` zatím NULL (zdroj chybí, doplní se později).

### l1.d_time (kalendář)
- PK: `[date]` (DATE)
- Generuje se z rozsahu `MIN/MAX([timestamp])` v `f_traces` přes rekurzivní CTE.
- Sloupce: `[day]`, `day_name`, `[month]`, `month_name`, `[quarter]`, `[year]`, `is_weekend`.

### l1.connections (bridge)
- PK: `(product_id, test_num)`
- `active = 1` pokud kombinace existuje v `d_limit` a zároveň alespoň jedna nenulová hodnota
  v `l0.traces_wide`. Filtr pro `f_traces` (nepřidávat měření pro testy, které se pro produkt nedělají).

## Vztahy a cardinality

| Z | Do | Cardinality | Typ |
|---|---|---|---|
| `f_traces` | `d_product` | M:1 | LEFT JOIN přes `product_id` |
| `f_traces` | `d_limit` | M:1 | LEFT JOIN přes `(product_id, test_num)` |
| `f_traces` | `d_time` | M:1 | LEFT JOIN přes `CAST([timestamp] AS DATE) = [date]` |
| `f_traces` | `connections` | M:1 | bridge, filtr aktivních kombinací |

## Transformace l0 → l1

Detail v [../sql/04_transform/README.md](../sql/04_transform/README.md).

### Jak se staví `d_limit`
1. JOIN `ciselnik_products × ciselnik_mapping` (cross join každý produkt × každý test).
2. Pro každou kombinaci se z `ciselnik_mapping` přečte `min_col` / `max_col` / `val_col` (např. `'RP030'`).
3. Hodnota odpovídajícího RP sloupce z `ciselnik_products` se vezme jako `limit_min` / `limit_max` / `limit_value`.
4. **Konverze T-SQL**: PostgreSQL používá `row_to_json(c1) ->> lower(c2.min_col)` (dynamický přístup ke sloupci).
   T-SQL toto neumí → musí se napsat **explicitní `CASE c2.min_col WHEN 'RP001' THEN c1.RP001 …`** pro všech 71 RP.
5. Filtr: vyřadit záznamy, kde `min = max = 0` a `val_col IS NULL` (test se pro produkt nedělá).

### Jak se dělá UNPIVOT pro `f_traces`
1. `l0.traces_wide` má 31 TP sloupců.
2. Přes `CROSS APPLY (VALUES ('TP010', f.TP010), ('TP012', f.TP012), …)` se každý řádek rozpadne na 31 řádků (jeden per test).
3. Filtr: `measured_value <> 0 AND IS NOT NULL` + kombinace `(product_id, test_num)` musí být v `connections`.
4. **Konverze T-SQL**: PostgreSQL `CROSS JOIN LATERAL` → T-SQL `CROSS APPLY`; každá hodnota musí mít prefix `f.` (T-SQL neumí implicitní referenci na vnější tabulku jako PG).

### Jak se generuje `d_time`
PostgreSQL `generate_series(start, end, '1 day')` → **T-SQL rekurzivní CTE** s `OPTION (MAXRECURSION 0)`.

## Real-time ingest

Po prvotním naplnění existují **2 T-SQL triggery**, které drží mart vrstvu konzistentní bez nutnosti opakovaného spouštění `04_transform/`:

| Trigger | Tabulka | Akce |
|---|---|---|
| `l0.trg_traces_wide_to_f_traces` | `l0.traces_wide` AFTER INSERT | UNPIVOT nových řádků do `l1.f_traces` + doplnit `l1.d_time` |
| `l1.trg_watchdog_consecutive_fails` | `l1.f_traces` AFTER INSERT | Detekce 2 consecutive failů, INSERT do `l1.watchdog_alerts` |

Triggery jsou kaskádové: INSERT do `l0.traces_wide` → trigger UNPIVOT do `l1.f_traces` → watchdog trigger případně vygeneruje alert. Power BI (Import + Refresh) tak vidí změny ihned.

Generování realistických dat: viz [`scripts/04_simulator.py`](../scripts/04_simulator.py) — live režim i backfill konkrétních dnů. Detail triggerů: [`sql/07_etl_trigger/README.md`](../sql/07_etl_trigger/README.md), [`sql/06_watchdog/`](../sql/06_watchdog/).
