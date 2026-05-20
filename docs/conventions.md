# Konvence projektu

## Naming

| Typ | Konvence | Příklad |
|---|---|---|
| Schémata | lowercase | `l0`, `l1`, `meta` |
| Tabulky l0 | snake_case, bez prefixu | `l0.traces_wide`, `l0.ciselnik_products` |
| Tabulky l1 — dimenze | `d_<entity>` | `d_product`, `d_limit`, `d_time` |
| Tabulky l1 — fakty | `f_<process>` | `f_traces` |
| Tabulky l1 — bridge | bez prefixu | `connections` |
| Views | `v_<účel>` | `v_analysis`, `v_watchdog_latest` |
| Indexy | `idx_<table>_<cols>` | `idx_f_traces_product_test` |
| PK constraints | `pk_<table>` | `pk_f_traces` |
| Stored procedures | `sp_<co_dělá>` | `sp_watchdog_check` |
| Triggers | `trg_<co_dělá>` | `trg_watchdog_consecutive_fails` |
| Python soubory | `NN_<účel>.py` | `01_inspect.py`, `02_import_l0.py` |
| SQL skripty | `NN_<účel>.sql` | `01_d_product.sql`, `04_load_f_traces.sql` |

Čísla v prefixu zaručují správné pořadí spouštění (abecední řazení).

## SQL styl

- **Klíčová slova UPPERCASE**: `SELECT`, `FROM`, `WHERE`, `INSERT INTO`.
- **Identifikátory lowercase snake_case**: `product_id`, `valid_from`.
- **Rezervovaná slova v `[hranatých závorkách]`**: `[date]`, `[year]`, `[month]`, `[day]`,
  `[quarter]`, `[timestamp]`, `[message]`.
- **Plný název s schématem**: `l1.f_traces`, ne jen `f_traces` (kvůli auth/sec).
- **`GO` batch separator** mezi DDL příkazy.
- **Idempotence**: každý skript spustitelný opakovaně.
  - DDL: `IF OBJECT_ID('schema.table','U') IS NOT NULL DROP TABLE …` + `CREATE TABLE …`
  - DML: `TRUNCATE` + `INSERT`, nebo `MERGE`
  - Views/SP/Trg: `CREATE OR ALTER`
- **Krátké komentáře v hlavičce skriptu**: účel, zdroj, originál v `_postgres_originals/`.

### Příklad správného DDL

```sql
IF OBJECT_ID('l1.d_product', 'U') IS NOT NULL
    DROP TABLE l1.d_product;
GO

CREATE TABLE l1.d_product (
    product_id    INT          NOT NULL,
    valid_from    DATE         NOT NULL,
    valid_to      DATE         NULL,
    product_group VARCHAR(40)  NULL,
    CONSTRAINT pk_d_product PRIMARY KEY (product_id, valid_from)
);
GO
```

## Python styl

- **Type hints**: ano (`def get_engine() -> Engine:`).
- **`from __future__ import annotations`** v každém modulu (postpone evaluation, povolí PEP 604 `str | None`).
- **`pathlib.Path`** místo `os.path.join`.
- **f-stringy** místo `%` formátování.
- **Konstanty** UPPER_SNAKE_CASE na úrovni modulu.
- **Skripty** mají `if __name__ == "__main__": main()` a `main()` vrací `int` (exit code).
- **`scripts/lib/`** = sdílené utility (config, db). Skripty v `scripts/` je importují.
- **Error handling**: u skriptů `try/except` na úrovni `main()` jen pro logování; vnitřní funkce nechej padnout.

## Git workflow

- **Hlavní větev**: `main` (chráněná, merguje se přes pull request).
- **Feature branche**: `feature/<krátký-popis>` (např. `feature/d-limit-units`).
- **Bugfix branche**: `fix/<co-opravujeme>`.
- **Commit messages**: imperativ, česky, krátká věta + volitelný popis.
  - ✅ `feat: přidat d_limit unit sloupec`
  - ✅ `fix: opravit BIGINT cast pro id ve f_traces`
  - ✅ `docs: doplnit setup pro nového člena týmu`
  - ❌ `udelane`, `fix`
- **Prefix** podle typu změny: `feat`, `fix`, `docs`, `refactor`, `chore`, `ci`.
- **PR**: vždy přes pull request, ne přímý push na main (kvůli code review).

## Bezpečnost

1. **Nikdy** necommitovat:
   - `.env` (skutečná hesla/secrets)
   - `data/raw/*` (produkční testovací data)
   - `*.pbix` soubory s daty
2. **`.env.example`** smí obsahovat pouze placeholdery.
3. **Connection stringy a hesla** vždy přes env proměnné nebo Azure Key Vault.
4. **Auth**: token z `az login` (DefaultAzureCredential), fallback `ActiveDirectoryInteractive`.
5. **DB role pro uživatele**: `db_datareader` + `db_datawriter` + `db_ddladmin`. Nikoli `db_owner`.
