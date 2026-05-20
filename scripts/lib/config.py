"""Path resolver a načítání .env."""
from __future__ import annotations

import os
from pathlib import Path

from dotenv import load_dotenv

PROJECT_ROOT: Path = Path(__file__).resolve().parents[2]
DATA_RAW: Path = PROJECT_ROOT / "data" / "raw"
SQL_DIR: Path = PROJECT_ROOT / "sql"

_env_loaded = False


def load_env() -> None:
    global _env_loaded
    if _env_loaded:
        return
    env_path = PROJECT_ROOT / ".env"
    if env_path.exists():
        load_dotenv(env_path)
    _env_loaded = True


def get_env(name: str, default: str | None = None, required: bool = False) -> str | None:
    load_env()
    value = os.getenv(name, default)
    if required and not value:
        raise RuntimeError(f"Chybí povinná env proměnná: {name}")
    return value
