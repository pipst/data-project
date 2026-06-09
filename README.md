# Data Project

Datový mart nad výrobními testovacími daty postavený nad **Azure SQL Database**, výstup pro **Power BI**. Týmový projekt na VŠE.

Architektura: **2 vrstvy** v Azure SQL (`l0` = raw, `l1` = mart, star schema) + audit log v `meta`. Real-time ETL přes T-SQL triggery, watchdog detekuje 2 consecutive fails.

## Quick start

### Předpoklady (jednorázově)

- Python 3.11+
- ODBC Driver 18 for SQL Server (`brew install msodbcsql18` na macOS, `brew install unixodbc` jako prereq)
- Azure CLI (`brew install azure-cli`)
- VS Code + extension **SQL Server (mssql)** od Microsoftu

Detailní setup (Mac / Windows / Linux + troubleshooting): [docs/setup.md](docs/setup.md).

### Klonování + environment

```bash
git clone <repo-url> && cd data_project

python3 -m venv .venv
source .venv/bin/activate     # macOS/Linux
# .venv\Scripts\activate      # Windows

pip install -r requirements.txt

cp .env.example .env
# uprav .env — server, database (hodnoty dostaneš od majitele projektu)

az login                       # přihlas se školním účtem
```

Připojení k databázi vyžaduje registraci Entra ID účtu — kontaktuj majitele projektu.

## Struktura projektu

```
data_project/
├── README.md                    # dokumentace
├── .env.example                 # vzor connection config
├── requirements.txt             # Python deps
├── data/raw/                    # zdrojové CSV (gitignored)
├── docs/                        # data_model.md, setup.md, conventions.md
├── scripts/
│   ├── lib/                     # db.py (engine), config.py (paths, env)
│   ├── 01_inspect.py            # inspekce raw CSV
│   ├── 02_import_l0.py          # raw → l0 (Python import přes pandas)
│   ├── 03_run_sql.py            # runner SQL skriptů + logging do meta.run_log
│   └── 04_simulator.py          # generátor dat (live i backfill režim)
└── sql/
    ├── 00_schemas.sql           # CREATE SCHEMA l0, l1, meta
    ├── 01_l0/                   # DDL raw tabulek
    ├── 02_l1/                   # DDL mart (star schema: f_traces, d_*, connections)
    ├── 03_meta/                 # DDL run_log (audit)
    ├── 04_transform/            # ETL skripty l0 → l1 (jednorázový rebuild)
    ├── 05_views/                # v_analysis, v_watchdog_latest, v_analysis_live
    ├── 06_watchdog/             # watchdog_alerts + trigger (2 consecutive fails)
    ├── 07_etl_trigger/          # real-time trigger l0 → l1 (UNPIVOT po INSERT)
    └── _postgres_originals/     # původní PostgreSQL skripty (reference)
```

## End-to-end workflow

Pořadí pro **první nasazení od nuly**:

### 1. Inspekce dat (volitelné)
```bash
python scripts/01_inspect.py
```
Vypíše tvar, sloupce, NULL counts a sample pro každý CSV v `data/raw/`.

### 2. Schémata + prázdné tabulky
Spusť přes Python runner (loguje do `meta.run_log` od kroku 3):
```bash
python scripts/03_run_sql.py sql/00_schemas.sql
python scripts/03_run_sql.py sql/03_meta/01_run_log.sql
python scripts/03_run_sql.py sql/01_l0/ sql/02_l1/ sql/06_watchdog/01_watchdog_alerts.sql
```

### 3. Naimport raw data do `l0`
```bash
python scripts/02_import_l0.py
```
Naplní `l0.traces_wide` (~244k řádků, ~3 min), `l0.ciselnik_products`, `l0.ciselnik_mapping`.

### 4. ETL `l0 → l1` + views + watchdog
```bash
python scripts/03_run_sql.py sql/04_transform/
python scripts/03_run_sql.py sql/05_views/
python scripts/03_run_sql.py sql/06_watchdog/02_trg_watchdog.sql
python scripts/03_run_sql.py sql/07_etl_trigger/01_etl.sql
```

Co se nasadí:
- `04_transform/*` — jednorázové naplnění `l1` z `l0` (cca 6 min pro UNPIVOT do `f_traces`)
- `05_views/*` — analytické views pro Power BI
- `06_watchdog/02_trg_watchdog.sql` — trigger watchdog na `f_traces`
- `07_etl_trigger/01_etl.sql` — trigger UNPIVOT na `l0.traces_wide` (real-time ETL při nových INSERT)

### 5. Sanity check
```bash
python -c "
import sys; sys.path.insert(0, 'scripts')
from lib.db import get_engine
from sqlalchemy import text
with get_engine().connect() as c:
    for t in ['l1.f_traces', 'l1.d_product', 'l1.d_limit', 'l1.d_time']:
        n = c.execute(text(f'SELECT COUNT(*) FROM {t}')).scalar()
        print(f'  {t:<20} {n:>10,}')
"
```
Očekávané hodnoty: `f_traces` ~5,7M, `d_product` ~62, `d_limit` ~1500, `d_time` ~478.

### 6. Power BI
Power BI Desktop → Get Data → **Azure SQL Database**:
- Server / Database: viz `.env`
- Authentication: **Microsoft account** (tvůj `@vse.cz`)
- Vyber tabulky/views ze schématu `l1` (doporučeno: `v_analysis`, `v_analysis_live`, `v_watchdog_latest`)

## Real-time demo (simulator)

Generuje výrobní data jako kdyby přicházela z linky, INSERT do `l0.traces_wide` → trigger `07_etl_trigger` automaticky UNPIVOT do `l1.f_traces`:

```bash
# Live mode: 1 kus / 2s, nekonečně (Ctrl+C ukončí)
python scripts/04_simulator.py

# Backfill mode: historická data pro konkrétní dny + produkt
python scripts/04_simulator.py --date 2026-06-01 --date 2026-06-02 \
                                --product 124 --count-per-day 500
```

Detail: `python scripts/04_simulator.py --help`.


## Další dokumentace

- [docs/setup.md](docs/setup.md) — kompletní onboarding + troubleshooting
- [docs/data_model.md](docs/data_model.md) — star schema, vztahy, popis sloupců
- [docs/conventions.md](docs/conventions.md) — naming, SQL/Python styl, git workflow
- [sql/04_transform/README.md](sql/04_transform/README.md) — ETL pořadí + sanity testy
- [sql/07_etl_trigger/README.md](sql/07_etl_trigger/README.md) — real-time trigger detail
