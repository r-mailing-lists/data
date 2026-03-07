"""Helper functions for reading R mailing list parquet data from GitHub.

https://github.com/r-mailing-lists/data

Usage:
    # Download this file, then:
    from rml import rml_available, rml_read

    rml_available()
    df = rml_read("r-devel")
"""

import json
import re
import tempfile
from pathlib import Path
from urllib.request import urlopen, urlretrieve

import polars as pl

_RAW_BASE = "https://raw.githubusercontent.com/r-mailing-lists/data/main/data"
_API_URL = "https://api.github.com/repos/r-mailing-lists/data/contents/data/messages"
_CACHE_DIR = Path(tempfile.gettempdir()) / "rml_cache"
_DECADE_RE = re.compile(r"^(.+)-(\d{4})-(\d{4})\.parquet$")


def _cached_download(url: str, filename: str) -> Path:
    _CACHE_DIR.mkdir(parents=True, exist_ok=True)
    dest = _CACHE_DIR / filename
    if not dest.exists():
        urlretrieve(url, dest)
    return dest


def _list_message_files() -> list[dict]:
    with urlopen(_API_URL) as resp:
        return json.loads(resp.read())


def rml_available() -> list[str]:
    """List available mailing list names (decade splits are merged)."""
    files = _list_message_files()
    names: set[str] = set()
    for f in files:
        m = _DECADE_RE.match(f["name"])
        names.add(m.group(1) if m else f["name"].removesuffix(".parquet"))
    return sorted(names)


def rml_read(list_name: str) -> pl.DataFrame:
    """Download (if needed) and read a mailing list into a Polars DataFrame.

    Split lists like r-help are automatically combined from their
    decade chunks (e.g. r-help-1990-1999.parquet, r-help-2000-2009.parquet).
    """
    files = _list_message_files()
    matched = [
        f for f in files
        if f["name"] == f"{list_name}.parquet"
        or (_DECADE_RE.match(f["name"]) and
            _DECADE_RE.match(f["name"]).group(1) == list_name)
    ]
    if not matched:
        raise ValueError(f"List '{list_name}' not found. See rml_available()")
    dfs = [
        pl.read_parquet(_cached_download(f["download_url"], f["name"]))
        for f in matched
    ]
    return pl.concat(dfs) if len(dfs) > 1 else dfs[0]


def rml_read_threads() -> pl.DataFrame:
    """Download (if needed) and read thread summaries."""
    return pl.read_parquet(
        _cached_download(f"{_RAW_BASE}/threads.parquet", "threads.parquet")
    )


def rml_read_contributors() -> pl.DataFrame:
    """Download (if needed) and read contributor statistics."""
    return pl.read_parquet(
        _cached_download(f"{_RAW_BASE}/contributors.parquet", "contributors.parquet")
    )
