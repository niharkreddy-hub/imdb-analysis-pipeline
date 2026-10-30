"""Native psql integration test. Requires a new, empty database passed by name.

Exports synthetic staged rows as TSV, reloads via the real loader, then exercises
the transform and assertions. Does not download IMDb files or use real credentials.
"""
import argparse
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("loader", ROOT / "python/load_staging.py")
loader = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(loader)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", required=True)
    args = parser.parse_args()
    base = ["psql", "-X", "--dbname", args.database, "-v", "ON_ERROR_STOP=1"]
    def query(sql):
        return subprocess.check_output(base + ["-At", "-c", sql])
    if query("SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name IN ('staging','core','etl','reporting')").strip() != b"0":
        raise SystemExit("Refusing test: database already contains project schemas")
    for path in ["sql/02_staging.sql", "sql/01_schema.sql", "tests/fixture.sql"]:
        subprocess.run(base + ["-f", str(ROOT / path)], check=True)
    with tempfile.TemporaryDirectory() as directory:
        directory = Path(directory)
        for stem, (table, header) in loader.DATASETS.items():
            body = query(f"COPY staging.{table} TO STDOUT WITH (FORMAT csv, DELIMITER E'\\t', NULL '\\N', QUOTE E'\\b')")
            (directory / f"{stem}.tsv").write_bytes(("\t".join(header.split())+"\n").encode() + body)
        subprocess.run([sys.executable, str(ROOT / "python/load_staging.py"),
                        "--database", args.database, "--data-dir", str(directory),
                        "--manifest", str(directory / "manifest.json")], check=True)
    for path in ["sql/03_transform.sql", "sql/04_reporting_views.sql", "sql/05_validate.sql",
                 "tests/assertions.sql", "sql/03_transform.sql", "sql/05_validate.sql",
                 "tests/assertions.sql", "sql/analysis/content.sql", "sql/analysis/people.sql",
                 "sql/analysis/ratings.sql", "sql/analysis/series.sql"]:
        subprocess.run(base + ["-f", str(ROOT / path)], check=True)
    print("PASS native PostgreSQL TSV import, transform, reconciliation, repeat run and analysis")


if __name__ == "__main__":
    main()
