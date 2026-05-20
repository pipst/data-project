# Data Project

Datový mart nad výrobními testovacími daty postavený nad Azure SQL Database, výstup pro Power BI. Týmový projekt na VŠE.

## Quick start

Předpoklady (jednorázově): Python 3.11+, ODBC Driver 18 for SQL Server, Azure CLI, VS Code + extension SQL Server (mssql). Detail viz [docs/setup.md](docs/setup.md).

```bash
# 1. Klonuj repo
git clone <repo-url> && cd data_project

# 2. Python virtual env
python3 -m venv .venv
source .venv/bin/activate     # macOS/Linux
# .venv\Scripts\activate      # Windows

# 3. Závislosti
pip install -r requirements.txt

# 4. Konfigurace
cp .env.example .env
# uprav .env podle pokynů od majitele projektu

# 5. Přihlas se do Azure CLI
az login
```

Připojení k databázi vyžaduje přístupové údaje a registraci Entra ID účtu — kontaktuj majitele projektu.

## Struktura projektu

```
data_project/
├── CLAUDE.md                # brief pro Claude Code sessions
├── README.md                # tento soubor
├── data/raw/                # zdrojové CSV (gitignored)
├── docs/                    # data_model.md, setup.md, conventions.md
├── scripts/                 # Python skripty
│   ├── lib/                 # db.py, config.py
│   ├── 01_inspect.py        # inspekce raw souborů
│   ├── 02_import_l0.py      # raw CSV → l0
│   └── 03_run_sql.py        # runner SQL skriptů s logováním
└── sql/
    ├── 00_schemas.sql       # CREATE SCHEMA l0, l1, meta
    ├── 01_l0/               # DDL raw tabulek
    ├── 02_l1/               # DDL mart tabulek (star schema)
    ├── 03_meta/             # DDL run_log
    ├── 04_transform/        # ETL l0 → l1 (T-SQL)
    ├── 05_views/            # analytické views
    ├── 06_watchdog/         # alert tabulka + trigger
    └── _postgres_originals/ # původní PostgreSQL skripty (reference)
```

## Workflow

### 1. Inspekce dat
```bash
python scripts/01_inspect.py
```
Vypíše tvar, sloupce, NULL counts, sample pro každý CSV soubor v `data/raw/`.

### 2. Vytvoř schémata + DDL (přes MSSQL extension ve VS Code)
Otevři a spusť (pravým klikem → "Execute query") v pořadí:
1. `sql/00_schemas.sql`
2. `sql/01_l0/01_stg_fact.sql`, `02_stg_ciselnik1.sql`, `03_stg_ciselnik2.sql`
3. `sql/02_l1/01_d_product.sql` … `05_f_traces.sql`
4. `sql/03_meta/01_run_log.sql`
5. `sql/06_watchdog/01_watchdog_alerts.sql`

### 3. Naimportuj raw data do `l0`
```bash
python scripts/02_import_l0.py
```
Naplní `l0.traces_wide`, `l0.ciselnik_products`, `l0.ciselnik_mapping`.

### 4. Spusť transformace `l0 → l1`
Přes MSSQL extension nebo Python runner:
```bash
python scripts/03_run_sql.py sql/04_transform/
python scripts/03_run_sql.py sql/05_views/
python scripts/03_run_sql.py sql/06_watchdog/02_trg_watchdog.sql
```
Každý běh se zaloguje do `meta.run_log` (kdo, kdy, status, počet řádků) pro audit.

### 5. Power BI
Otevři Power BI Desktop → Get Data → Azure SQL Database → vyber tabulky a views ze schématu `l1`.

## Bezpečnost

1. **Nikdy** necommituj `.env` (v `.gitignore`).
2. Data v `data/raw/` jsou produkční testovací — ignorovaná v gitu.
3. Připojení vždy přes Entra ID, žádné SQL loginy.
4. `.env.example` smí obsahovat pouze placeholdery.

## Další dokumentace

- [docs/setup.md](docs/setup.md) — onboarding nového člena
- [docs/data_model.md](docs/data_model.md) — popis star schema
- [docs/conventions.md](docs/conventions.md) — naming, SQL/Python styl
- [sql/04_transform/README.md](sql/04_transform/README.md) — ETL pořadí + testy
