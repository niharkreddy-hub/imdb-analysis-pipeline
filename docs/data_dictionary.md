# IMDb Data Dictionary

> Historical profiling figures below describe saved runs without recorded source hashes. They have not been revalidated with the corrected TSV parser. Current transformation rules are in `sql/03_transform.sql`; inspect `etl.rejects` for the current snapshot.

This document describes every column across all seven IMDb non-commercial datasets used in this project, including types, nullability, observed ranges, and known data quality issues.

**Source:** https://datasets.imdbws.com/
**Profiled on:** 2026-05-05
**Total uncompressed size:** ~9 GB across 7 files
**Profiling tools:** `python/profile_data.py`, `python/investigate_quirks.py`

---

## File Summary

| File | Rows | Size on disk | Primary key |
|---|---|---|---|
| title.basics.tsv | 12,479,598 | 1,032 MB | tconst |
| title.ratings.tsv | 1,668,663 | 28 MB | tconst |
| title.crew.tsv | 12,479,598 | 393 MB | tconst |
| title.episode.tsv | 9,638,312 | 242 MB | tconst |
| title.principals.tsv | ~85,000,000 (4.2 GB) | 4,229 MB | (tconst, ordering) |
| title.akas.tsv | 56,892,184 | 2,746 MB | (titleId, ordering) |
| name.basics.tsv | 15,300,272 | 902 MB | nconst |

---

## 1. title.basics.tsv

Core attributes for every title (movie, TV series, episode, etc.) registered in IMDb.

**Row count:** 12,479,598
**Primary key:** tconst
**Source format:** Tab-separated values, UTF-8, with `\N` as null sentinel.

| Column | Source format | Target SQL type | Nullable | Notes |
|---|---|---|---|---|
| tconst | string | VARCHAR(12) | No | Format `tt[0-9]+`. Globally unique IMDb title identifier. |
| titleType | string | VARCHAR(20) | No | Categorical, 11 distinct values (see below). |
| primaryTitle | string | TEXT | No | The "more popular" title, often the English-market name. May contain Unicode, embedded quotes, commas. |
| originalTitle | string | TEXT | No | Original-language title. Mostly identical to primaryTitle. |
| isAdult | "0" or "1" | BOOLEAN | No | Stored as text. **A saved run reported 487 unexpected values; source/parser cause unverified** — see Data Quality Notes. |
| startYear | YYYY | SMALLINT | Yes | 11.74% null. Range observed: 1874–2115. |
| endYear | YYYY | SMALLINT | Yes | 98.75% null — only populated for ended TV series. |
| runtimeMinutes | integer | INTEGER | Yes | 64.08% null. Extreme outliers up to 3,692,080 retained but flagged. |
| genres | comma-separated | TEXT (will normalize) | Yes | 4.29% null. Up to 3 genres per title. 28 distinct values. To be split into a `title_genre` junction table. |

### Distinct values: titleType (11)

| Type | Count |
|---|---|
| tvEpisode | 9,638,312 |
| short | 1,129,046 |
| movie | 745,211 |
| video | 325,430 |
| tvSeries | 298,893 |
| tvMovie | 154,792 |
| tvMiniSeries | 70,007 |
| tvSpecial | 57,909 |
| videoGame | 49,009 |
| tvShort | 10,988 |
| tvPilot | 1 |

### Distinct values: genres (28)

Action, Adult, Adventure, Animation, Biography, Comedy, Crime, Documentary, Drama, Family, Fantasy, Film-Noir, Game-Show, History, Horror, Music, Musical, Mystery, News, Reality-TV, Romance, Sci-Fi, Short, Sport, Talk-Show, Thriller, War, Western.

### Data quality notes

- **Unexpected isAdult values:** A historical parsed run reported 487 rows. Recheck the raw lines with quoting disabled before attributing the cause. The transform quarantines any current row whose flag is not 0/1, preserving the raw staged fields and reason.
- **runtimeMinutes outliers retained:** 413 titles exceed 1,000 minutes; 17 exceed 10,000; 2 exceed 100,000. Top outlier is `tt7493646` at 3,692,080 minutes (clearly erroneous). Retained for completeness; analysis queries should filter `WHERE runtimeMinutes < 1000` for visualization purposes.
- **Future-dated titles (5 rows) retained.** They represent announced productions.
- **Pre-1880 titles (32 rows) retained.** Legitimate early cinema (Lumière brothers era).
- **endYear pre-1900 (10 rows):** Likely data entry errors but retained as observed.
- **`primaryTitle` may contain literal double-quote characters.** Postgres `\copy` requires `QUOTE E'\b'` to load these correctly.
- The `\N` null sentinel handled via `NULLIF(col, '\N')` during staging-to-core load.

---

## 2. title.ratings.tsv

User-generated rating data for a subset of titles.

**Row count:** 1,668,663 (only ~13% of all titles are rated)
**Primary key:** tconst (one-to-one with title)

| Column | Source format | Target SQL type | Nullable | Notes |
|---|---|---|---|---|
| tconst | string | VARCHAR(12) | No | FK to title.tconst |
| averageRating | decimal 1.0–10.0 | NUMERIC(3,1) | No | 91 distinct values (steps of 0.1). Mean across all rated titles: 6.96. |
| numVotes | integer | INTEGER | No | Range: 5–3,185,031. Highly skewed (mean 1,037, max 3.2M). |

### Data quality notes

- No nulls. Cleanest file in the dataset.
- Vote count distribution is extreme — a few hundred blockbusters dominate. Any "best of" analysis should use a minimum vote threshold (e.g., `WHERE numVotes >= 1000`) to surface meaningful results.
- Inner joining `title` to `title_rating` filters out 87% of titles; LEFT JOIN preserves them.

---

## 3. title.crew.tsv

Director and writer attribution per title.

**Row count:** 12,479,598
**Primary key:** tconst

| Column | Source format | Target SQL type | Nullable | Notes |
|---|---|---|---|---|
| tconst | string | VARCHAR(12) | No | FK to title.tconst |
| directors | comma-separated nconsts | TEXT (will normalize) | Yes | 44.14% null. Will split into `title_director` junction table. |
| writers | comma-separated nconsts | TEXT (will normalize) | Yes | 49.10% null. Will split into `title_writer` junction table. |

### Data quality notes

- High null rates (~45%) reflect that many shorts, TV episodes, and small productions don't have confirmed crew on IMDb.
- Use LEFT JOIN (not INNER) when joining title to crew, or you'll silently drop half the catalog.

---

## 4. title.episode.tsv

Episode-to-series relationship and episode positioning.

**Row count:** 9,638,312
**Primary key:** tconst

| Column | Source format | Target SQL type | Nullable | Notes |
|---|---|---|---|---|
| tconst | string | VARCHAR(12) | No | The episode's tconst |
| parentTconst | string | VARCHAR(12) | No | The parent series' tconst (FK to title.tconst, self-reference) |
| seasonNumber | integer | SMALLINT | Yes | 20.70% null (specials, unconfirmed episodes) |
| episodeNumber | integer | SMALLINT | Yes | 20.70% null |

### Data quality notes

- 235,886 distinct parent series across the 9.6M episodes.
- Top series by episode count are long-running soap operas and news programs.
- When analyzing seasons, filter `WHERE seasonNumber IS NOT NULL`.

---

## 5. title.principals.tsv

Principal cast and crew per title with role detail.

**Row count:** ~85,000,000 (file is 4.2 GB; profiled on a 1M-row sample)
**Primary key:** (tconst, ordering)

| Column | Source format | Target SQL type | Nullable | Notes |
|---|---|---|---|---|
| tconst | string | VARCHAR(12) | No | FK to title.tconst |
| ordering | integer | SMALLINT | No | Cast order (1 = top-billed). Composite PK with tconst. Up to 44 entries per title in sample. |
| nconst | string | VARCHAR(12) | No | FK to person.nconst |
| category | string | VARCHAR(30) | No | Role category, 13 distinct values (see below) |
| job | string | TEXT | Yes | 79.87% null. Specific role description when category is generic (e.g., "screenplay" when category is "writer"). |
| characters | JSON-formatted string | JSONB | Yes | 45.00% null. **Valid in the inspected sample only.** The transform validates each non-null value as an array of strings. |

### Distinct values: category (13)

actor, actress, archive_footage, archive_sound, casting_director, cinematographer, composer, director, editor, producer, production_designer, self, writer.

Notable: `archive_sound` is rare (514 rows in 5M sample). `tvPilot` is one outlier per dataset.

### Data quality notes

- The `characters` column appears to be JSON-formatted (e.g., `["Tony Stark","Iron Man"]`). All 112,020 sampled non-null values parsed as valid JSON. Loading as JSONB enables `jsonb_array_elements_text(characters)` for character-level queries.
- This is the largest file in the dataset (~85M rows). Loading requires `\copy` (not `INSERT`) and indexing should happen *after* the load.

---

## 6. title.akas.tsv

Localized and alternate titles for each title.

**Row count:** 56,892,184
**Primary key:** (titleId, ordering)

| Column | Source format | Target SQL type | Nullable | Notes |
|---|---|---|---|---|
| titleId | string | VARCHAR(12) | No | **Same as tconst elsewhere — IMDb naming inconsistency.** Aliased to `tconst` in the staging-to-core load. |
| ordering | integer | SMALLINT | No | Composite PK with titleId. Up to 313 entries per title. |
| title | string | TEXT | No | The localized/alternate title |
| region | string (2-letter code) | VARCHAR(10) | Yes | 21.97% null. 251 distinct values. Top: IN, DE, JP, FR, ES. |
| language | string (2-letter code) | VARCHAR(10) | Yes | 32.79% null. 110 distinct values. Top: ja, fr, hi, es, de. |
| types | sub-delimited string | TEXT (will normalize) | Yes | 67.98% null. **Sub-delimited by `\x02`, NOT comma.** 8 atomic types. |
| attributes | string | TEXT | Yes | 99.45% null. 184 distinct values. Generally low value for analysis; consider not normalizing. |
| isOriginalTitle | "0" or "1" | BOOLEAN | No | 22% of localized titles are flagged as originals. |

### Distinct atomic values: types (8)

After splitting on `\x02`: alternative, dvd, festival, imdbDisplay, original, tv, video, working.

### Data quality notes

- **CRITICAL:** the `types` column uses `\x02` (ASCII Start of Text, U+0002) as a sub-delimiter, NOT a comma. Standard CSV-array splitting will produce garbage like `imdbDisplaytv` as a single value. Only 0.01% of rows actually use the sub-delimiter, but ignoring it produces silent data corruption. Document and split on `\x02` first.
- `attributes` is 99.45% null — likely not worth a separate junction table. Either inline as TEXT or drop from the model.
- The `titleId` → `tconst` rename is the cleanest place to fix IMDb's naming inconsistency.

---

## 7. name.basics.tsv

Core attributes for every person in IMDb.

**Row count:** 15,300,272
**Primary key:** nconst

| Column | Source format | Target SQL type | Nullable | Notes |
|---|---|---|---|---|
| nconst | string | VARCHAR(12) | No | Format `nm[0-9]+`. Unique person identifier. |
| primaryName | string | TEXT | No | 67 nulls (~0.0004%). Free text, UTF-8. |
| birthYear | YYYY | SMALLINT | Yes | 95.61% null. Range: 4–2026. Some pre-1700 values are real (Shakespeare, Vivaldi, Aeschylus). |
| deathYear | YYYY | SMALLINT | Yes | 98.31% null. Range: 17–2026. |
| primaryProfession | comma-separated | TEXT (will normalize) | Yes | 20.12% null. ~26K distinct value combinations; ~30 atomic professions. To be split into `person_profession` junction. |
| knownForTitles | comma-separated tconsts | TEXT (will normalize) | Yes | 11.94% null. To be split into `person_known_for` junction. |

### Data quality notes

- High null rates on birth/death years are normal — IMDb often doesn't have this data, especially for crew, minor performers, and historical figures.
- Pre-1700 birth years (369 rows) are mostly legitimate: classical composers, playwrights, ancient figures whose works appear in films. **Do not filter as outliers.**
- A saved run reported 67 null `primaryName` values. The current core requires a name; affected rows are quarantined with a reason, not inserted as fabricated people.

---

## Cross-File Data Quality Summary

The most important issues found during profiling and investigation, ordered by impact on the data model:

1. **`\N` is the universal null marker.** All seven files use it. Every staging-to-core transform applies `NULLIF(col, '\N')` to nullable columns.

2. **Unexpected isAdult values** — the saved 487-row observation has an unverified cause. Invalid flags in a newly validated snapshot are quarantined, not silently dropped.

3. **Five comma-separated array columns** require normalization into junction tables: `title.basics.genres`, `title.crew.directors`, `title.crew.writers`, `name.basics.primaryProfession`, `name.basics.knownForTitles`.

4. **One JSON column:** `title.principals.characters` is checked as a JSON array of strings before casting to JSONB.

5. **One non-standard sub-delimiter:** `title.akas.types` uses `\x02`, not comma. Critical to split correctly.

6. **One naming inconsistency:** `title.akas.titleId` is the same as `tconst` everywhere else. Aliased during the load.

7. **Missing references are audited.** The saved prefix sample found two unresolved director IDs; it does not establish a full-dataset rate. Unresolved links are quarantined with source identifiers and reasons; no synthetic people are inserted.

8. **Outliers retained, not filtered.** Future years, runtimes up to 3.7M minutes, pre-1700 birth years all retained as observed. Analysis queries apply situational filters (e.g., `runtimeMinutes < 1000` for charting).

9. **Expected categorical constraints for the schema:**
   - `title.title_type` IN (11 values listed above)
   - `title_principal.category` IN (13 values listed above)
   - `genre.genre_name` populated dynamically from valid loaded-title genre tokens (28 in the historical inspection)

10. **Title-to-rating ratio:** ~13% of titles have ratings. Most analytical queries should INNER JOIN to `title_rating` to focus on rated content; descriptive queries about IMDb's catalog as a whole should LEFT JOIN.
