"""Runner SQL skriptů s logováním do meta.run_log.

Použití:
    python scripts/03_run_sql.py sql/04_transform/
    python scripts/03_run_sql.py sql/05_views/01_v_analysis.sql
    python scripts/03_run_sql.py file1.sql file2.sql --fail-fast

Každý běh se loguje do meta.run_log s aktuálním datumem, jménem souboru
a uživatelem (z $USER), aby šlo zpětně dohledat historii spouštění.
"""
from __future__ import annotations

import argparse
import os
import sys
import traceback
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

from sqlalchemy import text

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib.db import get_engine, split_sql_batches  # noqa: E402


@dataclass
class Result:
    script: str
    status: str
    duration_s: float
    rows: int | None
    error: str | None


def collect_files(inputs: list[str]) -> list[Path]:
    files: list[Path] = []
    for raw in inputs:
        p = Path(raw)
        if not p.exists():
            print(f"⚠️  Cesta neexistuje: {p}", file=sys.stderr)
            continue
        if p.is_dir():
            files.extend(sorted(p.rglob("*.sql")))
        elif p.suffix.lower() == ".sql":
            files.append(p)
    # Deduplikace s zachováním pořadí
    seen: set[Path] = set()
    ordered: list[Path] = []
    for f in files:
        rp = f.resolve()
        if rp not in seen:
            seen.add(rp)
            ordered.append(f)
    return ordered


def run_id() -> str:
    """Identifikátor běhu — datum+čas pro audit log."""
    return datetime.now().strftime("%Y%m%d_%H%M%S")


def triggered_by() -> str:
    return os.getenv("USER") or "unknown"


def _run_log_exists(conn) -> bool:
    result = conn.execute(text("SELECT OBJECT_ID('meta.run_log', 'U')")).scalar()
    return result is not None


def log_start(conn, script_name: str) -> int | None:
    if not _run_log_exists(conn):
        print("  ⚠️  meta.run_log neexistuje — pokračuji bez logování (bootstrap mode).", file=sys.stderr)
        return None
    result = conn.execute(
        text(
            """
            INSERT INTO meta.run_log (run_id, script_name, started_at, status, triggered_by)
            OUTPUT INSERTED.id
            VALUES (:run_id, :script_name, SYSDATETIME(), 'running', :triggered_by)
            """
        ),
        {
            "run_id": run_id(),
            "script_name": script_name,
            "triggered_by": triggered_by(),
        },
    )
    return int(result.scalar_one())


def log_finish(conn, log_id: int | None, status: str, rows: int | None, error: str | None) -> None:
    if log_id is None:
        return
    conn.execute(
        text(
            """
            UPDATE meta.run_log
               SET finished_at   = SYSDATETIME(),
                   status        = :status,
                   rows_affected = :rows,
                   error_message = :error
             WHERE id = :id
            """
        ),
        {"id": log_id, "status": status, "rows": rows, "error": error},
    )


def execute_file(engine, path: Path) -> Result:
    sql_text = path.read_text(encoding="utf-8")
    batches = split_sql_batches(sql_text)
    started = datetime.now()

    # Otevři connection s autocommit pro log řádek; SQL batche v transakci
    with engine.begin() as log_conn:
        log_id = log_start(log_conn, str(path))

    total_rows = 0
    try:
        with engine.begin() as conn:
            for batch in batches:
                result = conn.exec_driver_sql(batch)
                if result.rowcount is not None and result.rowcount > 0:
                    total_rows += result.rowcount
    except Exception:  # noqa: BLE001
        tb = traceback.format_exc()
        duration = (datetime.now() - started).total_seconds()
        with engine.begin() as log_conn:
            log_finish(log_conn, log_id, "error", None, tb[:4000])
        return Result(str(path), "error", duration, None, tb)

    duration = (datetime.now() - started).total_seconds()
    with engine.begin() as log_conn:
        log_finish(log_conn, log_id, "ok", total_rows, None)
    return Result(str(path), "ok", duration, total_rows, None)


def print_summary(results: list[Result]) -> None:
    print("\n" + "=" * 80)
    print(f"{'Soubor':<55} {'Status':<8} {'Čas (s)':>8} {'Rows':>8}")
    print("-" * 80)
    for r in results:
        rows = "-" if r.rows is None else f"{r.rows:,}"
        print(f"{r.script[-54:]:<55} {r.status:<8} {r.duration_s:>8.2f} {rows:>8}")
    print("=" * 80)
    ok = sum(1 for r in results if r.status == "ok")
    err = sum(1 for r in results if r.status == "error")
    print(f"Souhrn: {ok} OK, {err} ERROR\n")


def main() -> int:
    parser = argparse.ArgumentParser(description="Runner SQL skriptů s logováním do meta.run_log")
    parser.add_argument("paths", nargs="+", help="SQL soubor(y) nebo složka(y)")
    parser.add_argument(
        "--fail-fast",
        action="store_true",
        help="Zastavit po prvním selhání (default: pokračovat dál).",
    )
    args = parser.parse_args()

    files = collect_files(args.paths)
    if not files:
        print("❌ Žádné SQL soubory k spuštění.", file=sys.stderr)
        return 1

    print(f"▶ Run ID: {run_id()}  |  Triggered by: {triggered_by()}")
    print(f"▶ Soubory ({len(files)}):")
    for f in files:
        print(f"   - {f}")

    engine = get_engine()
    results: list[Result] = []
    any_failed = False

    for path in files:
        print(f"\n→ {path}")
        result = execute_file(engine, path)
        results.append(result)
        if result.status == "error":
            any_failed = True
            print(f"❌ {path}: {result.error}", file=sys.stderr)
            if args.fail_fast:
                break
        else:
            print(f"✅ {path}  ({result.duration_s:.2f}s, rows={result.rows})")

    print_summary(results)
    return 1 if any_failed else 0


if __name__ == "__main__":
    sys.exit(main())
