"""Inspekce surových souborů v data/raw/.

Vypíše tvar, sloupce, dtypes, NULL counts, unikátní hodnoty a sample pro každý CSV.
DOCX soubor vypíše jako seznam odstavců (volitelné).
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

import pandas as pd

# Aby šlo skript spouštět z root i z scripts/
sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib.config import DATA_RAW  # noqa: E402

CSV_READ_OPTS = dict(
    sep=";",
    encoding="utf-8-sig",
    decimal=".",
    na_values=["#NENÍ_K_DISPOZICI", ""],
    keep_default_na=True,
)

TP_RE = re.compile(r"^TP\d+$", re.IGNORECASE)
RP_RE = re.compile(r"^RP\d+$", re.IGNORECASE)


def inspect_csv(path: Path) -> None:
    print(f"\n{'=' * 70}\n📄 {path.name}\n{'=' * 70}")
    df = pd.read_csv(path, **CSV_READ_OPTS)
    print(f"Shape: {df.shape[0]:,} řádků × {df.shape[1]} sloupců")

    tp_cols = [c for c in df.columns if TP_RE.match(c)]
    rp_cols = [c for c in df.columns if RP_RE.match(c)]
    if tp_cols:
        print(f"TP sloupce ({len(tp_cols)}): {tp_cols[0]} … {tp_cols[-1]}")
    if rp_cols:
        print(f"RP sloupce ({len(rp_cols)}): {rp_cols[0]} … {rp_cols[-1]}")

    meta_cols = [c for c in df.columns if c not in tp_cols + rp_cols]
    print(f"\nMetadata sloupce ({len(meta_cols)}):")
    for col in meta_cols:
        n_null = int(df[col].isna().sum())
        n_unique = int(df[col].nunique(dropna=True))
        print(
            f"  - {col:<20} dtype={str(df[col].dtype):<12} "
            f"null={n_null:>7,} unique={n_unique:>7,}"
        )

    print("\nSample (prvních 5 řádků, jen metadata sloupce):")
    with pd.option_context("display.max_columns", 20, "display.width", 200):
        print(df[meta_cols].head(5).to_string(index=False))


def inspect_docx(path: Path) -> None:
    print(f"\n{'=' * 70}\n📄 {path.name}\n{'=' * 70}")
    try:
        from docx import Document  # python-docx
    except ImportError:
        print("python-docx není nainstalovaný — přeskakuji DOCX inspekci.")
        return

    doc = Document(str(path))
    paragraphs = [p.text for p in doc.paragraphs if p.text.strip()]
    print(f"Počet neprázdných odstavců: {len(paragraphs)}")
    print("\nPrvních 10 odstavců:")
    for i, text in enumerate(paragraphs[:10], 1):
        print(f"  {i:2}. {text[:120]}")


def main() -> None:
    if not DATA_RAW.exists():
        print(f"❌ Složka {DATA_RAW} neexistuje.")
        sys.exit(1)

    files = sorted(DATA_RAW.iterdir())
    if not files:
        print(f"⚠️  Složka {DATA_RAW} je prázdná.")
        return

    for path in files:
        if path.name.startswith(".") or path.is_dir():
            continue
        if path.suffix.lower() == ".csv":
            inspect_csv(path)
        elif path.suffix.lower() == ".docx":
            inspect_docx(path)
        else:
            print(f"\n[přeskočeno: nepodporovaný typ] {path.name}")


if __name__ == "__main__":
    main()
