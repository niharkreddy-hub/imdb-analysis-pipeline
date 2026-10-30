"""Validate all seven decompressed IMDb TSVs, record hashes, then load atomically.

Uses Python's standard library and the PostgreSQL psql client. No database driver.
Run from the repository root: python python/load_staging.py --database imdb_portfolio
Use --validate-only to inspect files without touching the database.
"""

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
import subprocess
import sys

DATASETS = {
    "title.basics": ("title_basics", "tconst titleType primaryTitle originalTitle isAdult startYear endYear runtimeMinutes genres"),
    "name.basics": ("name_basics", "nconst primaryName birthYear deathYear primaryProfession knownForTitles"),
    "title.ratings": ("title_ratings", "tconst averageRating numVotes"),
    "title.crew": ("title_crew", "tconst directors writers"),
    "title.episode": ("title_episode", "tconst parentTconst seasonNumber episodeNumber"),
    "title.principals": ("title_principals", "tconst ordering nconst category job characters"),
    "title.akas": ("title_akas", "titleId ordering title region language types attributes isOriginalTitle"),
}


def inspect_file(path, expected_header):
    """Read once in binary mode so the hash describes the exact validated bytes."""
    digest = hashlib.sha256()
    count = 0
    size = 0
    before = path.stat()
    with path.open("rb") as source:
        for line_number, raw in enumerate(source, 1):
            digest.update(raw)
            size += len(raw)
            if any(c in raw for c in (b"\x00", b"\x08")):
                raise ValueError(f"{path}:{line_number}: NUL/backspace is not supported")
            text = raw.decode("utf-8").removesuffix("\n").removesuffix("\r")
            if "\r" in text:
                raise ValueError(f"{path}:{line_number}: embedded carriage return")
            fields = text.split("\t")
            if line_number == 1:
                if fields != expected_header:
                    raise ValueError(f"{path}: unexpected header {fields!r}")
            else:
                if len(fields) != len(expected_header):
                    raise ValueError(f"{path}:{line_number}: expected {len(expected_header)} fields, got {len(fields)}")
                count += 1
    if count == 0:
        raise ValueError(f"{path}: no data rows")
    after = path.stat()
    if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
        raise ValueError(f"{path}: file changed during validation")
    return {"file": path.name, "bytes": size, "rows": count,
            "sha256": digest.hexdigest(), "mtime_ns": after.st_mtime_ns}


def copy_statement(path, table):
    # psql meta-commands are line based. Backslash paths are not used here.
    value = path.resolve().as_posix()
    if any(c in value for c in ("\n", "\r", "\\")):
        raise ValueError("Unsupported character in data path")
    value = value.replace("'", "''")
    return (f"\\copy staging.{table} FROM '{value}' WITH "
            "(FORMAT csv, DELIMITER E'\\t', HEADER true, NULL '\\N', QUOTE E'\\b', ENCODING 'UTF8');")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir", type=Path, default=Path("data"))
    parser.add_argument("--database", default="imdb_portfolio")
    parser.add_argument("--manifest", type=Path, default=Path("data/load_manifest.json"))
    parser.add_argument("--validate-only", action="store_true")
    args = parser.parse_args()
    entries, paths = [], []
    for stem, (table, header) in DATASETS.items():
        path = args.data_dir / f"{stem}.tsv"
        entry = inspect_file(path, header.split())
        entries.append(entry)
        paths.append((path, table))
        print(f"Validated {path.name}: {entry['rows']:,} rows", flush=True)
    manifest = {"validated_at_utc": datetime.now(timezone.utc).isoformat(),
                "source": "https://datasets.imdbws.com/", "downloaded_at_utc": None,
                "status": "validated_not_loaded", "datasets": entries}
    args.manifest.parent.mkdir(parents=True, exist_ok=True)
    args.manifest.write_text(json.dumps(manifest, indent=2) + "\n")
    if args.validate_only:
        return
    # Guard changes between validation and COPY. Keep input files immutable during load.
    for (path, _), entry in zip(paths, entries):
        stat = path.stat()
        if (stat.st_size, stat.st_mtime_ns) != (entry["bytes"], entry["mtime_ns"]):
            raise ValueError(f"{path}: changed since validation")
    sql = "BEGIN;\nTRUNCATE " + ", ".join(f"staging.{t}" for _, t in paths) + ";\n"
    sql += "\n".join(copy_statement(p, t) for p, t in paths) + "\n"
    for (_, table), entry in zip(paths, entries):
        sql += (f"DO $$ BEGIN IF (SELECT COUNT(*) FROM staging.{table}) <> {entry['rows']} "
                f"THEN RAISE EXCEPTION 'Row count mismatch: {table}'; END IF; END $$;\n")
    sql += "COMMIT;\n"
    # Connection credentials use the normal libpq environment/.pgpass, never a source file.
    subprocess.run(["psql", "-X", "--dbname", args.database, "-v", "ON_ERROR_STOP=1"],
                   input=sql, text=True, check=True)
    manifest["status"] = "staging_loaded"
    manifest["loaded_at_utc"] = datetime.now(timezone.utc).isoformat()
    args.manifest.write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, UnicodeError, subprocess.CalledProcessError) as exc:
        print(f"Load stopped: {exc}", file=sys.stderr)
        sys.exit(1)
