"""Připojení k Azure SQL + helper pro spouštění .sql souborů s GO separátorem.

Auth strategie:
  1. Access token z `az login` (preferováno, DefaultAzureCredential)
  2. ActiveDirectoryInteractive jako fallback (otevírá browser)
"""
from __future__ import annotations

import re
import struct
from pathlib import Path
from urllib.parse import quote_plus

from sqlalchemy import create_engine, event
from sqlalchemy.engine import Connection, Engine

from .config import get_env, load_env

ODBC_DRIVER = "ODBC Driver 18 for SQL Server"
GO_PATTERN = re.compile(r"^\s*GO\s*$", re.MULTILINE | re.IGNORECASE)

# pyodbc connection attribute pro access token auth (Microsoft docs)
SQL_COPT_SS_ACCESS_TOKEN = 1256
AZURE_SQL_SCOPE = "https://database.windows.net/.default"


def _build_odbc_string(use_token: bool) -> str:
    load_env()
    server = get_env("AZURE_SQL_SERVER", required=True)
    database = get_env("AZURE_SQL_DATABASE", required=True)
    conn_timeout = get_env("SQL_CONNECTION_TIMEOUT", "60")

    if use_token:
        # Token auth: žádný Authentication= v connection stringu, token se předá zvlášť.
        auth_part = ""
    else:
        auth_mode = get_env("AZURE_SQL_AUTH", "ActiveDirectoryInteractive")
        auth_part = f"Authentication={auth_mode};"

    return (
        f"DRIVER={{{ODBC_DRIVER}}};"
        f"SERVER={server};DATABASE={database};"
        f"{auth_part}"
        f"Encrypt=yes;TrustServerCertificate=no;"
        f"Connection Timeout={conn_timeout};"
    )


def _pack_token(token: str) -> bytes:
    """Zabaluje access token do struktury, kterou očekává SQL_COPT_SS_ACCESS_TOKEN."""
    token_bytes = token.encode("utf-16-le")
    return struct.pack(f"<I{len(token_bytes)}s", len(token_bytes), token_bytes)


def _try_get_token() -> str | None:
    """Vrátí access token z `az login`. Nebo None, pokud žádný credential není dostupný."""
    try:
        from azure.identity import DefaultAzureCredential
    except ImportError:
        return None
    try:
        cred = DefaultAzureCredential(exclude_interactive_browser_credential=True)
        return cred.get_token(AZURE_SQL_SCOPE).token
    except Exception:  # noqa: BLE001
        return None


def get_engine() -> Engine:
    # Preferováno: token z `az login`
    token = _try_get_token()
    if token:
        odbc_str = _build_odbc_string(use_token=True)
        url = f"mssql+pyodbc:///?odbc_connect={quote_plus(odbc_str)}"
        engine = create_engine(url, fast_executemany=True, future=True)

        @event.listens_for(engine, "do_connect")
        def _provide_token(dialect, conn_rec, cargs, cparams):  # noqa: ARG001
            # Token může expirovat — vezmi čerstvý při každém připojení.
            fresh = _try_get_token() or token
            cparams["attrs_before"] = {SQL_COPT_SS_ACCESS_TOKEN: _pack_token(fresh)}

        return engine

    # Fallback: Interactive auth (otevírá browser)
    odbc_str = _build_odbc_string(use_token=False)
    url = f"mssql+pyodbc:///?odbc_connect={quote_plus(odbc_str)}"
    return create_engine(url, fast_executemany=True, future=True)


def split_sql_batches(sql_text: str) -> list[str]:
    parts = GO_PATTERN.split(sql_text)
    return [p.strip() for p in parts if p.strip()]


def run_sql_file(connection: Connection, path: Path) -> int:
    """Spustí SQL soubor rozdělený po `GO`. Vrátí součet rowcount přes všechny batche (kde dostupné)."""
    sql_text = Path(path).read_text(encoding="utf-8")
    total_rows = 0
    for batch in split_sql_batches(sql_text):
        result = connection.exec_driver_sql(batch)
        if result.rowcount is not None and result.rowcount > 0:
            total_rows += result.rowcount
    return total_rows
