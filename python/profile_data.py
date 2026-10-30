"""profile_data.py

Profile an IMDb TSV file and emit a structured report.

Usage:
    python python/profile_data.py data/title.basics.tsv
    python python/profile_data.py data/title.principals.tsv --sample 500000
"""

import argparse
import csv
import os
from pathlib import Path

import pandas as pd


def profile_file(filepath, sample_size=None):
    """Profile a TSV file column by column."""

    print("\n" + "=" * 78)
    print("FILE: " + filepath)
    print("=" * 78)

    if not Path(filepath).exists():
        print("ERROR: File not found.")
        return

    size_mb = os.path.getsize(filepath) / (1024 * 1024)
    print(f"File size on disk: {size_mb:,.1f} MB")

    read_kwargs = {
        "sep": "\t",
        "na_values": [r"\N"],
        "keep_default_na": False,
        "low_memory": False,
        "dtype": str,
        "encoding": "utf-8",
        "on_bad_lines": "error",
        "quoting": csv.QUOTE_NONE,
    }
    if sample_size:
        read_kwargs["nrows"] = sample_size
        print(f"Sampling first {sample_size:,} rows")

    try:
        df = pd.read_csv(filepath, **read_kwargs)
    except Exception as e:
        print(f"ERROR loading file: {e}")
        return

    print(f"Rows loaded: {len(df):,}")
    print(f"Columns ({len(df.columns)}): {list(df.columns)}")

    print("\n" + "COLUMN ANALYSIS".center(78, "-"))

    for col in df.columns:
        series = df[col]
        null_count = series.isna().sum()
        null_pct = 100 * null_count / len(df) if len(df) else 0
        non_null = series.dropna()
        unique = non_null.nunique()

        print(f"\n  Column: {col}")
        print(f"    Nulls: {null_count:,} ({null_pct:.2f}%)")
        print(f"    Distinct non-null values: {unique:,}")

        if unique == 0:
            print("    [ALL NULL]")
            continue

        if unique <= 25:
            vals = sorted(non_null.unique().tolist())
            print(f"    All values: {vals}")
        else:
            top = non_null.value_counts().head(5)
            print("    Top 5 values:")
            for val, count in top.items():
                preview = (val[:60] + "...") if len(str(val)) > 60 else val
                print(f"      {count:>10,}  {preview}")

        sample = non_null.head(1000)

        if sample.str.contains(",", na=False).any():
            comma_pct = 100 * sample.str.contains(",", na=False).sum() / len(sample)
            print(f"    [ARRAY-LIKE: {comma_pct:.0f}% of sampled rows contain commas]")

        if sample.str.startswith("[", na=False).any():
            json_pct = 100 * sample.str.startswith("[", na=False).sum() / len(sample)
            print(f"    [JSON-LIKE: {json_pct:.0f}% of sampled rows start with bracket]")

        try:
            numeric = pd.to_numeric(non_null, errors="coerce").dropna()
            if len(numeric) / len(non_null) > 0.95:
                print(
                    f"    Numeric range: min={numeric.min():,.0f}, "
                    f"max={numeric.max():,.0f}, "
                    f"mean={numeric.mean():,.2f}"
                )
        except Exception:
            pass


def main():
    parser = argparse.ArgumentParser(description="Profile an IMDb TSV file.")
    parser.add_argument("filepath", help="Path to the TSV file")
    parser.add_argument(
        "--sample",
        type=int,
        default=None,
        help="Sample only the first N rows (use for huge files)",
    )
    args = parser.parse_args()
    profile_file(args.filepath, args.sample)


if __name__ == "__main__":
    main()

