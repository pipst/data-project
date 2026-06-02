"""Simulátor výrobních testovacích dat.

Generuje nový "test cycle" (jeden kus na výrobní lince) a INSERTuje ho jako
řádek do l0.traces_wide. Trigger l0.trg_traces_wide_to_f_traces pak
automaticky:
  1. UNPIVOTuje TP010..TP041 do l1.f_traces
  2. Doplní nové datumy do l1.d_time

A trigger l1.trg_watchdog_consecutive_fails reaguje na nové řádky ve f_traces
a generuje alerty do l1.watchdog_alerts.

Generátor je realistický:
  - 80 % měření je uvnitř limitu (kolem středu, gaussian noise)
  - 15 % je blízko hranice limitu (margin < 10 % nebo > 90 %)
  - 5 %  je za hranicí limitu (FAIL)

Použití:
    python scripts/04_simulator.py                       # nekonečno, 2s mezi kusy
    python scripts/04_simulator.py --interval 5          # 5s mezi kusy
    python scripts/04_simulator.py --count 50            # 50 kusů a konec
    python scripts/04_simulator.py --fail-rate 0.2       # 20% fail rate (víc RED)
"""
from __future__ import annotations

import argparse
import random
import sys
import time
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib.db import get_engine  # noqa: E402
from sqlalchemy import text  # noqa: E402

# Měření, která může produkt obsahovat (31 TP testů)
TP_COLUMNS = ['TP010'] + [f'TP{i:03d}' for i in range(12, 42)]


def load_catalog(engine) -> dict[int, list[dict]]:
    """Načte pro každý product_id seznam aktivních testů + jejich limity."""
    query = text("""
        SELECT c.product_id, c.test_num,
               dl.limit_min, dl.limit_max, dl.limit_value
        FROM l1.connections c
        LEFT JOIN l1.d_limit dl
               ON dl.product_id = c.product_id AND dl.test_num = c.test_num
        WHERE c.active = 1
        ORDER BY c.product_id, c.test_num
    """)
    catalog: dict[int, list[dict]] = {}
    with engine.connect() as conn:
        for row in conn.execute(query):
            catalog.setdefault(row.product_id, []).append({
                "test_num": row.test_num,
                "limit_min": float(row.limit_min) if row.limit_min is not None else None,
                "limit_max": float(row.limit_max) if row.limit_max is not None else None,
                "limit_value": float(row.limit_value) if row.limit_value is not None else None,
            })
    return catalog


def next_id(engine) -> int:
    """Najde největší id v traces_wide + 1 (nebo BIG number, ať se nepřekrývá s historickým importem)."""
    with engine.connect() as conn:
        max_id = conn.execute(text("""
            SELECT MAX(TRY_CAST(id AS BIGINT)) FROM l0.traces_wide
        """)).scalar()
    return (max_id or 99_000_000) + 1


def gen_measurement(limit_min, limit_max, limit_value, fail_rate, orange_rate) -> float:
    """Vrátí realistické měření pro dané limity."""
    # Pokud jsou všechny limity NULL → vrať nějakou rozumnou hodnotu
    if limit_min is None and limit_max is None and limit_value is None:
        return round(random.uniform(0.1, 100.0), 4)

    # limit_value (přesná hodnota) — jen drobný šum
    if limit_value is not None and limit_min is None and limit_max is None:
        # Exact value test: v_analysis porovnává s rovností (=), takže pro PASS
        # musí být měření PŘESNĚ rovno limit_value (žádný šum).
        # FAIL = vrátit detekovatelnou odchylku.
        if random.random() < fail_rate:
            offset = abs(limit_value) * 0.1 if limit_value != 0 else 0.5
            return round(limit_value + offset * random.choice([-1, 1]), 4)
        return round(limit_value, 4)

    # Jednostranný limit (jen min nebo jen max)
    if limit_min is None:
        # jen max — kolem max/2 (bezpečně pod max)
        center = (limit_max or 1.0) * 0.5
        spread = abs(limit_max or 1.0) * 0.2
    elif limit_max is None:
        center = (limit_min or 0.0) + abs(limit_min or 1.0) * 0.5
        spread = abs(limit_min or 1.0) * 0.2
    else:
        # Oboustranný limit
        center = (limit_min + limit_max) / 2
        spread = (limit_max - limit_min) * 0.15

    roll = random.random()
    if roll < fail_rate:
        # FAIL: za hranicí
        if random.random() < 0.5 and limit_min is not None:
            value = limit_min - abs(spread) * random.uniform(0.1, 0.5)
        elif limit_max is not None:
            value = limit_max + abs(spread) * random.uniform(0.1, 0.5)
        else:
            value = center + random.gauss(0, spread * 3)
    elif roll < fail_rate + orange_rate:
        # ORANGE: blízko hranice
        if limit_min is not None and limit_max is not None:
            edge = random.choice([limit_min, limit_max])
            value = edge + random.gauss(0, abs(spread) * 0.05)
        else:
            value = center + random.gauss(0, spread * 1.5)
    else:
        # GREEN: kolem středu
        value = random.gauss(center, spread * 0.3)

    return round(value, 4)


def simulate_cycle(engine, catalog: dict, row_id: int, fail_rate: float, orange_rate: float,
                   product_id: int | None = None, timestamp_override=None) -> dict:
    """Vygeneruje jeden řádek dat a INSERTuje do l0.traces_wide.

    product_id: pokud None, vybere random z katalogu. Jinak použije zadaný.
    timestamp_override: pokud zadán (datetime), použije se místo datetime.now().
    """
    if product_id is None:
        product_id = random.choice(list(catalog.keys()))
    elif product_id not in catalog:
        raise ValueError(f"Produkt {product_id} nemá aktivní testy v katalogu")
    active_tests = {t["test_num"]: t for t in catalog[product_id]}

    # Vygeneruj měření pro každý TP sloupec (jen pro aktivní testy, ostatní NULL)
    measurements: dict[str, float | None] = {}
    fail_count = 0
    for tp in TP_COLUMNS:
        if tp in active_tests:
            t = active_tests[tp]
            val = gen_measurement(t["limit_min"], t["limit_max"], t["limit_value"], fail_rate, orange_rate)
            measurements[tp] = val
            # FAIL check pro statistiku
            if t["limit_min"] is not None and val < t["limit_min"]:
                fail_count += 1
            elif t["limit_max"] is not None and val > t["limit_max"]:
                fail_count += 1
        else:
            measurements[tp] = None

    # Sestavi řádek
    ts = timestamp_override if timestamp_override is not None else datetime.now()
    row_data = {
        "id": str(row_id),
        "pu_id": str(random.randint(220_000_000_000, 260_000_000_000)),
        "id_product": str(product_id),
        "timestamp": ts,
        "cycle_time_ms": random.randint(800, 1500),
        "loop_counter": random.randint(1, 5),
        "fresult": 0 if fail_count == 0 else 1,
        "error_code": None if fail_count == 0 else random.randint(100, 999),
        "error_text": None if fail_count == 0 else f"FAIL on {fail_count} test(s)",
    }
    row_data.update({tp.lower(): measurements[tp] for tp in TP_COLUMNS})

    # INSERT
    cols = list(row_data.keys())
    placeholders = ', '.join(f':{c}' for c in cols)
    bracketed_cols = ', '.join(f'[{c}]' for c in cols)
    sql = text(f"INSERT INTO l0.traces_wide ({bracketed_cols}) VALUES ({placeholders})")

    with engine.begin() as conn:
        conn.execute(sql, row_data)

    return {
        "id": row_id,
        "product_id": product_id,
        "tests": len(active_tests),
        "fails": fail_count,
        "status": "FAIL" if fail_count > 0 else "PASS",
    }


def get_db_stats(engine) -> dict:
    with engine.connect() as conn:
        return {
            "l0_traces_wide": conn.execute(text("SELECT COUNT(*) FROM l0.traces_wide")).scalar(),
            "l1_f_traces": conn.execute(text("SELECT COUNT(*) FROM l1.f_traces")).scalar(),
            "l1_d_time": conn.execute(text("SELECT COUNT(*) FROM l1.d_time")).scalar(),
            "l1_alerts": conn.execute(text("SELECT COUNT(*) FROM l1.watchdog_alerts")).scalar(),
        }


def run_backfill(engine, catalog, dates, count_per_day, product_id, fail_rate, orange_rate,
                 shift_start_h=6, shift_end_h=22) -> int:
    """Backfill mode: vygeneruje count_per_day kusů pro každý den z `dates` (YYYY-MM-DD).

    Časy kusů jsou rovnoměrně rozprostřené v pracovní směně (shift_start_h..shift_end_h).
    """
    from datetime import datetime as dt, timedelta
    if product_id not in catalog:
        print(f"❌ Produkt {product_id} nemá aktivní testy v katalogu")
        return 1

    row_id = next_id(engine)
    total = 0
    print(f"\nBackfill: produkt {product_id}, {len(dates)} dní × {count_per_day} kusů")
    print(f"Časy: {shift_start_h}:00–{shift_end_h}:00 (rovnoměrně)")
    print("-" * 70)

    shift_sec = (shift_end_h - shift_start_h) * 3600
    for day_str in dates:
        day = dt.strptime(day_str, "%Y-%m-%d")
        step = shift_sec / count_per_day
        fail_today = 0
        for i in range(count_per_day):
            base = i * step + random.uniform(-step * 0.3, step * 0.3)
            ts = day.replace(hour=shift_start_h) + timedelta(seconds=max(0, base))
            try:
                r = simulate_cycle(engine, catalog, row_id, fail_rate, orange_rate,
                                   product_id=product_id, timestamp_override=ts)
                if r["status"] == "FAIL":
                    fail_today += 1
                row_id += 1
                total += 1
            except Exception as exc:  # noqa: BLE001
                print(f"  ❌ {exc}")
        print(f"  {day_str}: {count_per_day} kusů uloženo ({fail_today} FAIL, {fail_today/count_per_day*100:.1f}%)")
    print(f"\n✅ Backfill hotov: {total} kusů")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Simulátor výrobních testovacích dat")
    parser.add_argument("--interval", type=float, default=2.0,
                        help="Sekundy mezi cykly (default: 2.0)")
    parser.add_argument("--count", type=int, default=None,
                        help="Počet kusů (default: nekonečno, ukonči Ctrl+C)")
    parser.add_argument("--fail-rate", type=float, default=0.05,
                        help="Pravděpodobnost FAIL měření (default: 0.05 = 5%%)")
    parser.add_argument("--orange-rate", type=float, default=0.15,
                        help="Pravděpodobnost ORANGE měření (default: 0.15 = 15%%)")
    # Backfill režim
    parser.add_argument("--date", action="append", default=None, metavar="YYYY-MM-DD",
                        help="Backfill mode: zadaný den (lze opakovat: --date 2026-06-01 --date 2026-06-02)")
    parser.add_argument("--product", type=int, default=None,
                        help="Backfill mode: konkrétní product_id (jinak random per cyklus)")
    parser.add_argument("--count-per-day", type=int, default=750,
                        help="Backfill mode: kolik kusů na den (default: 750)")
    args = parser.parse_args()

    engine = get_engine()
    print("=" * 70)

    # Backfill režim — generuje historická data místo real-time
    if args.date:
        print("BACKFILL MODE")
        print("=" * 70)
        print(f"Product:       {args.product}")
        print(f"Dny:           {args.date}")
        print(f"Kusů/den:      {args.count_per_day}")
        print(f"Fail rate:     {args.fail_rate * 100:.0f}%")
        print(f"Orange rate:   {args.orange_rate * 100:.0f}%")
        print("\nNačítám katalog...")
        catalog = load_catalog(engine)
        stats0 = get_db_stats(engine)
        rc = run_backfill(engine, catalog, args.date, args.count_per_day,
                          args.product, args.fail_rate, args.orange_rate)
        print("\nStav DB po backfillu:")
        stats1 = get_db_stats(engine)
        for k in stats0:
            d = stats1[k] - stats0[k]
            print(f"  {k:<22} {stats1[k]:>10,}  (+{d:,})")
        return rc

    # Live (původní) režim
    print("UVR Data Simulator")
    print("=" * 70)
    print(f"Interval:    {args.interval}s")
    print(f"Count:       {args.count or 'infinite (Ctrl+C to stop)'}")
    print(f"Fail rate:   {args.fail_rate * 100:.0f}%")
    print(f"Orange rate: {args.orange_rate * 100:.0f}%")
    print()

    print("Načítám katalog (aktivní produkty × testy)...")
    catalog = load_catalog(engine)
    print(f"  {len(catalog)} produktů s aktivními testy")
    print(f"  Celkem aktivních kombinací: {sum(len(v) for v in catalog.values())}")

    print("\nVýchozí stav DB:")
    stats0 = get_db_stats(engine)
    for k, v in stats0.items():
        print(f"  {k:<22} {v:>10,}")

    print(f"\nStart: {datetime.now().strftime('%H:%M:%S')}")
    print("-" * 70)

    row_id = next_id(engine)
    cycle = 0
    try:
        while args.count is None or cycle < args.count:
            cycle += 1
            try:
                result = simulate_cycle(engine, catalog, row_id, args.fail_rate, args.orange_rate)
                status_icon = "🔴" if result["status"] == "FAIL" else "🟢"
                print(f"  [{datetime.now().strftime('%H:%M:%S')}] "
                      f"#{cycle:>4} | id={result['id']:>10} | "
                      f"product={result['product_id']:<6} | "
                      f"tests={result['tests']:>2} | "
                      f"{status_icon} {result['status']}"
                      + (f" ({result['fails']} fails)" if result["fails"] else ""))
                row_id += 1
            except Exception as exc:  # noqa: BLE001
                print(f"  ❌ Chyba: {exc}")

            if args.count is None or cycle < args.count:
                time.sleep(args.interval)
    except KeyboardInterrupt:
        print("\n\nUkončeno uživatelem (Ctrl+C).")

    print("-" * 70)
    print(f"Konec: {datetime.now().strftime('%H:%M:%S')}, {cycle} cyklů")
    print("\nKonečný stav DB:")
    stats1 = get_db_stats(engine)
    for k in stats0:
        diff = stats1[k] - stats0[k]
        sign = '+' if diff >= 0 else ''
        print(f"  {k:<22} {stats1[k]:>10,}  ({sign}{diff:,})")

    return 0


if __name__ == "__main__":
    sys.exit(main())
