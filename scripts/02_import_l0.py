"""Import surových CSV do schématu l0 v Azure SQL.

Strategie:
  1. Spustí DDL z sql/01_l0/*.sql (DROP + CREATE TABLE s pevnými typy).
  2. Pandas read_csv → to_sql(if_exists='append') — zachová naše DDL typy.

Velký traces_gbs.csv se nahrává po chunknech s tqdm progress barem.
"""
from __future__ import annotations

import sys
from pathlib import Path

import pandas as pd
from sqlalchemy import text
from tqdm import tqdm

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib.config import DATA_RAW, SQL_DIR  # noqa: E402
from lib.db import get_engine, run_sql_file  # noqa: E402

SCHEMA = "l0"
# Pro Azure SQL: fast_executemany v db.py + dostatečně velký chunk, ale BEZ method='multi'.
# method='multi' generuje jednu INSERT s tisíci VALUES → naráží na limit 2100 parametrů/batch.
CHUNK_SIZE = 2000

CSV_READ_OPTS = dict(
    sep=";",
    encoding="utf-8-sig",
    decimal=".",
    na_values=["#NENÍ_K_DISPOZICI", ""],
    keep_default_na=True,
)

# Mapování CSV → cílová tabulka
TARGETS = {
    "traces_gbs.csv": "traces_wide",
    "ciselnik1.csv": "ciselnik_products",
    "ciselnik2.csv": "ciselnik_mapping",
}


def recreate_l0_tables(engine) -> None:
    """Spustí všechny DDL skripty z sql/01_l0/ (DROP + CREATE s pevnými typy)."""
    ddl_dir = SQL_DIR / "01_l0"
    print(f"\n▶ Recreating l0 tables from {ddl_dir}/")
    with engine.begin() as conn:
        for path in sorted(ddl_dir.glob("*.sql")):
            print(f"   - {path.name}")
            run_sql_file(conn, path)


def normalize_columns(df: pd.DataFrame) -> pd.DataFrame:
    df.columns = [c.strip().lower().replace(" ", "_") for c in df.columns]
    return df


def parse_timestamps(
    df: pd.DataFrame, columns: list[str], fmt: str = "%d.%m.%Y %H:%M"
) -> pd.DataFrame:
    for col in columns:
        if col in df.columns:
            df[col] = pd.to_datetime(df[col], format=fmt, errors="coerce")
    return df


def clean_int_string(df: pd.DataFrame, columns: list[str]) -> pd.DataFrame:
    """Pandas načítá sloupec s NaN jako float ('294' → '294.0'). Odstraň trailing '.0'."""
    for col in columns:
        if col in df.columns:
            df[col] = (
                df[col]
                .astype("string")
                .str.replace(r"\.0$", "", regex=True)
                .replace({"<NA>": None, "nan": None, "NaN": None})
            )
    return df


def import_traces(engine, path: Path) -> int:
    table = TARGETS["traces_gbs.csv"]
    print(f"\n▶ Importuju {path.name} → {SCHEMA}.{table}")
    total_rows = 0
    reader = pd.read_csv(path, chunksize=CHUNK_SIZE * 5, **CSV_READ_OPTS)
    with engine.begin() as conn:
        for chunk in tqdm(reader, unit="chunk", desc=path.name):
            chunk = normalize_columns(chunk)
            chunk = parse_timestamps(chunk, ["timestamp"], fmt="%d.%m.%Y %H:%M:%S")
            chunk.to_sql(
                table,
                conn,
                schema=SCHEMA,
                if_exists="append",
                index=False,
                chunksize=CHUNK_SIZE,
            )
            total_rows += len(chunk)
    return total_rows


def import_small(
    engine,
    path: Path,
    table: str,
    ts_cols: list[str] | None = None,
    ts_fmt: str = "%d.%m.%Y %H:%M",
    int_string_cols: list[str] | None = None,
) -> int:
    print(f"\n▶ Importuju {path.name} → {SCHEMA}.{table}")
    df = pd.read_csv(path, **CSV_READ_OPTS)
    df = normalize_columns(df)
    if ts_cols:
        df = parse_timestamps(df, ts_cols, fmt=ts_fmt)
    if int_string_cols:
        df = clean_int_string(df, int_string_cols)
    with engine.begin() as conn:
        df.to_sql(
            table,
            conn,
            schema=SCHEMA,
            if_exists="append",
            index=False,
            chunksize=CHUNK_SIZE,
        )
    return len(df)


def report_row_counts(engine) -> None:
    print("\n📊 Row counts v l0:")
    with engine.connect() as conn:
        for table in TARGETS.values():
            try:
                count = conn.execute(
                    text(f"SELECT COUNT(*) FROM {SCHEMA}.{table}")
                ).scalar_one()
                print(f"  - {SCHEMA}.{table:<22}  {count:>10,} řádků")
            except Exception as exc:  # noqa: BLE001
                print(f"  - {SCHEMA}.{table:<22}  ❌ {exc}")


def main() -> None:
    expected = [DATA_RAW / name for name in TARGETS]
    missing = [p for p in expected if not p.exists()]
    if missing:
        print("❌ Chybí soubory:")
        for p in missing:
            print(f"   - {p}")
        sys.exit(1)

    engine = get_engine()

    # 1. Vytvoř (nebo převytvoř) l0 tabulky s pevnými typy z DDL
    recreate_l0_tables(engine)

    # 2. Naimportuj data
    import_traces(engine, DATA_RAW / "traces_gbs.csv")
    import_small(
        engine,
        DATA_RAW / "ciselnik1.csv",
        TARGETS["ciselnik1.csv"],
        ts_cols=["valid_from", "valid_to"],
        ts_fmt="%d.%m.%Y %H:%M:%S",  # ciselnik1 má vteřiny
        int_string_cols=["product_id"],  # "294.0" → "294"
    )
    import_small(
        engine,
        DATA_RAW / "ciselnik2.csv",
        TARGETS["ciselnik2.csv"],
    )

    report_row_counts(engine)
    print("\n✅ Import do l0 hotov.")


if __name__ == "__main__":
    main()
