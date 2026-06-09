# Setup & onboarding

## Prerekvizity

- **Python 3.11+**
- **ODBC Driver 18 for SQL Server**
  - macOS: `brew tap microsoft/mssql-release && brew install msodbcsql18`
  - Windows: stáhni z [Microsoft Download](https://learn.microsoft.com/sql/connect/odbc/download-odbc-driver-for-sql-server)
  - Linux (Ubuntu): viz Microsoft docs
- **Azure CLI** (`az`): `brew install azure-cli` / [official docs](https://learn.microsoft.com/cli/azure/install-azure-cli)
- **VS Code** + extension **SQL Server (mssql)** (Microsoft)
- **Power BI Desktop** (jen Windows; Mac users mohou používat Power BI Service v prohlížeči)

## Získání přístupu k databázi

Připojovací údaje (server, název databáze) a registraci Entra ID účtu spravuje majitel projektu. Pro přístup ho kontaktuj samostatně.

## Krok-za-krokem

```bash
# 1. Clone
git clone <repo-url>
cd data_project

# 2. Python venv
python3.11 -m venv .venv
source .venv/bin/activate         # macOS/Linux
# .venv\Scripts\activate          # Windows

# 3. Závislosti
pip install -r requirements.txt

# 4. Konfigurace
cp .env.example .env
# .env uprav podle pokynů od majitele projektu
# (auth nech default ActiveDirectoryInteractive)

# 5. Azure login
az login

# 6. Test připojení
python -c "from scripts.lib.db import get_engine; \
           import sqlalchemy as sa; \
           print(get_engine().connect().execute(sa.text('SELECT @@VERSION')).scalar())"
```

## Workflow

Viz [../README.md](../README.md), sekce "Workflow".

## Troubleshooting

### `Login failed for user '<token-identified principal>'`
- Tvůj Entra ID účet ještě nebyl přidán do databáze. Napiš majiteli projektu.

### `Cannot open server 'xxx' requested by the login. Client with IP address 'x.x.x.x' is not allowed to access the server.`
- IP firewall blokuje. Pošli majiteli aktuální IP (`curl ifconfig.me`).

### `Connection timeout` / `Login timeout expired` při prvním spuštění po pauze
- Free tier Azure SQL se po nečinnosti pauzuje (cca po 1h). Při prvním požadavku trvá 30–60s wake-up.
- V `.env` zvyš `SQL_CONNECTION_TIMEOUT=180` nebo `300`.
- Pokud první pokus selže, prostě spusť příkaz znovu — DB se mezitím probudila.

### `No driver found` v Pythonu
- ODBC Driver 18 není nainstalovaný. Viz Prerekvizity výše.

### `Library not loaded: libodbc.2.dylib` (macOS)
- Chybí `unixodbc`. Spusť `brew install unixodbc`.

### `pyodbc` neumí `GO`
- Správně. Spouštěj SQL soubory přes `scripts/03_run_sql.py` (helper rozdělí po `GO`),
  nikoli přes `conn.execute()` přímo.

### Browser okno pro Entra Interactive auth se neotevřelo
- Použij token z `az login` místo Interactive. Stačí `az login` v terminálu — `db.py`
  automaticky preferuje token přes `DefaultAzureCredential` před browser-based auth.

## Audit log: meta.run_log

Každý běh `scripts/03_run_sql.py` se loguje do `meta.run_log`:

```sql
SELECT TOP 20 id, run_id, script_name, status, started_at, finished_at,
              rows_affected, triggered_by, error_message
FROM meta.run_log
ORDER BY started_at DESC;
```

`run_id` = timestamp běhu (`YYYYMMDD_HHMMSS`), `triggered_by` = OS username.

## Mac vs Windows specifika

- **Mac**: připojení přes ODBC 18 funguje, ale autentizace `ActiveDirectoryInteractive` otevře okno
  v defaultním prohlížeči. Pokud máš více účtů v prohlížeči, zkontroluj, že jsi přihlášen tím správným.
- **Windows**: stejné jako Mac, jen `ODBC Driver 18` se instaluje přes MSI installer.
- **Power BI Desktop**: pouze Windows. Mac users → Power BI Service (web) + nahrávat dataset přes
  Gateway nebo cloud connector.
