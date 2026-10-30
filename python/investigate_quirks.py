"""investigate_quirks.py

Targeted data quality checks for the IMDb dataset, based on issues
surfaced during initial profiling.

Usage:
    python python/investigate_quirks.py
"""

import csv
import json
import pandas as pd

DATA = "data"


def section(title):
    print("\n" + "=" * 78)
    print(title)
    print("=" * 78)


def check_title_types():
    section("CHECK 1: title.basics.titleType - full distribution")
    df = pd.read_csv(
        f"{DATA}/title.basics.tsv",
        sep="\t",
        quoting=csv.QUOTE_NONE,
        on_bad_lines="error",
        usecols=["titleType"],
        na_values=[r"\N"],
        keep_default_na=False,
        dtype=str,
    )
    counts = df["titleType"].value_counts()
    print(f"Distinct values: {counts.size}")
    print(counts.to_string())


def check_isadult_values():
    section("CHECK 2: title.basics.isAdult - unexpected values (cause unverified)")
    df = pd.read_csv(
        f"{DATA}/title.basics.tsv",
        sep="\t",
        quoting=csv.QUOTE_NONE,
        on_bad_lines="error",
        usecols=["tconst", "isAdult"],
        na_values=[r"\N"],
        keep_default_na=False,
        dtype=str,
    )
    valid_mask = df["isAdult"].isin(["0", "1"])
    corrupt = df[~valid_mask]
    print(f"Total rows: {len(df):,}")
    print(f"Rows with isAdult NOT in (0,1): {len(corrupt):,}")
    print(f"Percentage unexpected: {100 * len(corrupt) / len(df):.4f}%")
    print(f"\nDistinct unexpected values:")
    print(corrupt["isAdult"].value_counts().head(20).to_string())
    print(f"\nSample unexpected tconsts (first 10):")
    print(corrupt["tconst"].head(10).tolist())
    print("\nReview original lines and parser behavior; invalid values are quarantined in etl.rejects.")


def check_genres():
    section("CHECK 3: title.basics.genres - actual distinct genre count")
    df = pd.read_csv(
        f"{DATA}/title.basics.tsv",
        sep="\t",
        quoting=csv.QUOTE_NONE,
        on_bad_lines="error",
        usecols=["genres"],
        na_values=[r"\N"],
        keep_default_na=False,
        dtype=str,
    )
    df = df.dropna(subset=["genres"])
    exploded = df["genres"].str.split(",").explode().str.strip()
    exploded = exploded[exploded != ""]
    distinct = sorted(exploded.unique().tolist())
    print(f"Total non-null rows: {len(df):,}")
    print(f"Distinct genres after splitting: {len(distinct)}")
    print(f"\nAll genres (alphabetical):")
    for g in distinct:
        print(f"  {g}")
    print(f"\nGenre frequency (top 10):")
    print(exploded.value_counts().head(10).to_string())


def check_year_outliers():
    section("CHECK 4: title.basics - year and runtime outliers")
    df = pd.read_csv(
        f"{DATA}/title.basics.tsv",
        sep="\t",
        quoting=csv.QUOTE_NONE,
        on_bad_lines="error",
        usecols=["tconst", "startYear", "endYear", "runtimeMinutes"],
        na_values=[r"\N"],
        keep_default_na=False,
        dtype=str,
    )
    df["startYear"] = pd.to_numeric(df["startYear"], errors="coerce")
    df["endYear"] = pd.to_numeric(df["endYear"], errors="coerce")
    df["runtimeMinutes"] = pd.to_numeric(df["runtimeMinutes"], errors="coerce")

    print("startYear:")
    print(f"  Range: {df['startYear'].min():.0f} to {df['startYear'].max():.0f}")
    print(f"  Pre-1880:  {(df['startYear'] < 1880).sum():,}")
    print(f"  Post-2030: {(df['startYear'] > 2030).sum():,}")

    print("\nendYear:")
    print(f"  Range: {df['endYear'].min():.0f} to {df['endYear'].max():.0f}")
    print(f"  Pre-1900: {(df['endYear'] < 1900).sum():,}")

    print("\nruntimeMinutes:")
    print(f"  Range: {df['runtimeMinutes'].min():.0f} to {df['runtimeMinutes'].max():.0f}")
    print(f"  Over 1,000 min:   {(df['runtimeMinutes'] > 1000).sum():,}")
    print(f"  Over 10,000 min:  {(df['runtimeMinutes'] > 10000).sum():,}")
    print(f"  Over 100,000 min: {(df['runtimeMinutes'] > 100000).sum():,}")

    print("\nTop 5 runtime outliers:")
    extreme = df.dropna(subset=["runtimeMinutes"]).nlargest(5, "runtimeMinutes")
    print(extreme[["tconst", "runtimeMinutes"]].to_string(index=False))


def check_birth_death_outliers():
    section("CHECK 5: name.basics - birth and death year outliers")
    df = pd.read_csv(
        f"{DATA}/name.basics.tsv",
        sep="\t",
        quoting=csv.QUOTE_NONE,
        on_bad_lines="error",
        usecols=["nconst", "primaryName", "birthYear", "deathYear"],
        na_values=[r"\N"],
        keep_default_na=False,
        dtype=str,
    )
    df["birthYear"] = pd.to_numeric(df["birthYear"], errors="coerce")
    df["deathYear"] = pd.to_numeric(df["deathYear"], errors="coerce")

    print("birthYear:")
    print(f"  Range: {df['birthYear'].min():.0f} to {df['birthYear'].max():.0f}")
    print(f"  Pre-1700:       {(df['birthYear'] < 1700).sum():,}")
    print(f"  Future (>2026): {(df['birthYear'] > 2026).sum():,}")

    print("\ndeathYear:")
    print(f"  Range: {df['deathYear'].min():.0f} to {df['deathYear'].max():.0f}")
    print(f"  Pre-1700: {(df['deathYear'] < 1700).sum():,}")

    print("\nSample suspicious birthYears (under 1700):")
    suspicious = df[df["birthYear"] < 1700].head(5)
    print(suspicious[["nconst", "primaryName", "birthYear"]].to_string(index=False))


def check_characters_json():
    section("CHECK 6: title.principals.characters - JSON validity")
    df = pd.read_csv(
        f"{DATA}/title.principals.tsv",
        sep="\t",
        quoting=csv.QUOTE_NONE,
        on_bad_lines="error",
        usecols=["characters"],
        na_values=[r"\N"],
        keep_default_na=False,
        dtype=str,
        nrows=200000,
    )
    non_null = df["characters"].dropna()
    valid = 0
    invalid = 0
    invalid_samples = []
    for s in non_null:
        try:
            json.loads(s)
            valid += 1
        except (json.JSONDecodeError, TypeError):
            invalid += 1
            if len(invalid_samples) < 5:
                invalid_samples.append(s)
    print(f"Sampled non-null characters: {len(non_null):,}")
    print(f"Valid JSON:   {valid:,}")
    print(f"Invalid JSON: {invalid:,}")
    if invalid_samples:
        print("\nSample invalid values:")
        for s in invalid_samples:
            print(f"  {s!r}")
    else:
        print("\nAll sampled values parse as valid JSON. Safe to load as JSONB.")


def check_akas_separator():
    section("CHECK 7: title.akas.types - non-standard sub-delimiter")
    df = pd.read_csv(
        f"{DATA}/title.akas.tsv",
        sep="\t",
        quoting=csv.QUOTE_NONE,
        on_bad_lines="error",
        usecols=["types"],
        na_values=[r"\N"],
        keep_default_na=False,
        dtype=str,
        nrows=2000000,
    )
    non_null = df["types"].dropna()
    has_x02 = non_null.str.contains("\x02", na=False)
    print(f"Sampled non-null types: {len(non_null):,}")
    print(f"Containing x02 separator: {has_x02.sum():,}")
    print(f"Percentage: {100 * has_x02.sum() / len(non_null):.2f}%")

    if has_x02.any():
        print("\nDistinct atomic types after splitting on x02:")
        atoms = non_null.str.split("\x02").explode().str.strip().unique()
        for a in sorted(atoms):
            print(f"  {a}")
    print("\nKey insight: split on x02 (NOT comma) when normalizing this column.")


def check_orphan_nconsts():
    section("CHECK 8: orphan nconsts in title.crew")
    print("Loading all nconsts from name.basics (this may take 30s)...")
    names = pd.read_csv(
        f"{DATA}/name.basics.tsv",
        sep="\t",
        quoting=csv.QUOTE_NONE,
        on_bad_lines="error",
        usecols=["nconst"],
    )
    name_set = set(names["nconst"])
    print(f"Total nconsts in name.basics: {len(name_set):,}")

    print("\nSampling 1M rows of title.crew to find orphan directors...")
    crew = pd.read_csv(
        f"{DATA}/title.crew.tsv",
        sep="\t",
        quoting=csv.QUOTE_NONE,
        on_bad_lines="error",
        usecols=["directors"],
        na_values=[r"\N"],
        keep_default_na=False,
        dtype=str,
        nrows=1000000,
    ).dropna()
    crew_dirs = set(
        crew["directors"].str.split(",").explode().str.strip()
    )
    orphans = crew_dirs - name_set
    print(f"Distinct director nconsts in sample: {len(crew_dirs):,}")
    print(f"NOT found in name.basics: {len(orphans):,}")
    print(f"Orphan rate: {100 * len(orphans) / len(crew_dirs):.2f}%")
    if orphans:
        print(f"\nSample orphan nconsts: {list(orphans)[:5]}")
    print("\nDecision: declare FK constraints loosely (NOT VALID) or insert UNKNOWN stubs.")


def check_principal_categories():
    section("CHECK 9: title.principals.category - full distribution")
    df = pd.read_csv(
        f"{DATA}/title.principals.tsv",
        sep="\t",
        quoting=csv.QUOTE_NONE,
        on_bad_lines="error",
        usecols=["category"],
        na_values=[r"\N"],
        keep_default_na=False,
        dtype=str,
        nrows=5000000,
    )
    counts = df["category"].value_counts()
    print(f"Distinct values: {counts.size}")
    print(counts.to_string())


def main():
    check_title_types()
    check_isadult_values()
    check_genres()
    check_year_outliers()
    check_birth_death_outliers()
    check_characters_json()
    check_akas_separator()
    check_orphan_nconsts()
    check_principal_categories()
    print("\n" + "=" * 78)
    print("DONE.")
    print("=" * 78)


if __name__ == "__main__":
    main()
