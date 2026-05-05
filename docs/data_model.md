# Data Model — Design Decisions

This document captures the design rationale behind the `core` schema. Read alongside `er_diagram.md`.

## Modeling Philosophy

The core schema is **3rd Normal Form (3NF)**. Every multi-valued attribute (comma-separated lists in the source data) is normalized into a junction table. Lookups are factored out into their own small tables. Foreign keys are strictly enforced.

This was chosen over flat denormalization or a star schema because:

- 3NF demonstrates relational modeling competence to evaluators.
- Junction tables enable indexed many-to-many queries (e.g., all action films directed by Tarantino).
- Strict FK enforcement catches data quality issues immediately rather than letting them propagate.
- Denormalized BI views can be layered on top for Power BI in Phase 6 without polluting the core.

## Two-Schema Architecture

The database has two schemas:

- **`staging`** — 7 tables, every column TEXT, no constraints. Mirrors the raw TSV files exactly. Loaded via `\copy`.
- **`core`** — 13 tables, full constraints. Populated from staging via SQL transformations in Phase 4.

This pattern is standard in ETL pipelines. Loading directly into `core` would mean any data anomaly aborts a multi-gigabyte import. Staging absorbs all anomalies; the staging-to-core transform handles them explicitly with documented rules.

## Table Inventory

13 tables in `core`, organized by role:

- **Strong entities (2):** `title`, `person`
- **Lookup tables (2):** `genre`, `profession`
- **Dependent tables (3):** `title_rating`, `title_episode`, `title_aka`
- **Junction tables (6):** `title_genre`, `title_director`, `title_writer`, `title_principal`, `person_known_for`, `person_profession`

## Key Design Decisions

### Why `title_rating` is a separate table
Only ~13% of titles are rated. Merging rating columns into `title` would mean 87% of rows have NULL `average_rating` and NULL `num_votes`. Splitting reduces table width and isolates frequently-updated rating data from rarely-changing title data.

### Why `title_episode` is a separate table
Only ~77% of titles are episodes. The 23% that aren't would have NULL `season_number`, NULL `episode_number`, NULL `parent_tconst`. The separate table also enables clean self-referencing FK from episode-tconst to parent-tconst.

### Why three separate junction tables (director, writer, principal)?
Each represents a semantically different relationship. Director and writer are simple links. Principal includes role metadata (category, job, characters). Merging would require a `role_type` discriminator column and conditional NULLs — uglier than three clean tables.

### Why `title_principal` uses composite PK `(tconst, ordering)` not surrogate?
IMDb's `ordering` represents cast billing order (1 = top-billed). It carries semantic meaning. A `SERIAL principal_id` would add a column that no query needs. Composite PK is both compact and meaningful.

### Why `genre` and `profession` are lookups but `region`/`language` are not?
Genres and professions repeat millions of times across junctions. A 4-byte `genre_id` is far smaller than the 5-character string `'Drama'`. Plus, renaming genres would touch one row.

`region` and `language` in `title_aka` are 2-letter ISO codes — already small. A `region` lookup would only let us join to a `country_name` we don't have. Not worth the complexity.

### Why `characters` is JSONB and not a junction table?
The quirks investigation confirmed `characters` is 100% valid JSON. Storing as JSONB enables in-place queries with `jsonb_array_elements_text(characters)`. A junction table `title_principal_character(tconst, ordering, character_name)` would be technically more normalized but adds query complexity for marginal benefit. The data is already nested by IMDb; we preserve that structure.

### Why FK constraints are strict (not `NOT VALID`)?
The quirks investigation found only 0.00% orphan rate (2 orphans in 1M sampled directors). The 2 orphan nconsts are inserted as stubs (`primary_name = '[UNKNOWN]'`) before the directors load, allowing strict FK enforcement everywhere. This is a stronger schema than tolerating orphans via `NOT VALID`.

### Why `ON DELETE CASCADE` on FK to title?
If a title is deleted, its ratings, episodes, akas, and junction entries should also disappear. There's no scenario where keeping orphan child rows makes sense.

### Why `ON DELETE RESTRICT` on FK to lookups?
A genre or profession should never be deleted while still in use. Restricting the delete enforces that lookup table integrity.

### Why CHECK constraints on enumerated columns?
`title_type` and `category` have small fixed value sets (11 and 13 distinct values). CHECK constraints prevent any row with an unexpected value from being inserted. If IMDb adds a new title_type in a future data refresh, the load fails loudly — exactly what we want.

## Data Quality Decisions Reflected in the Schema

These design choices implement decisions made during Phase 1's data quality investigation:

- **isAdult corruption (487 rows):** `core.title.is_adult` is `NOT NULL BOOLEAN`. The 487 corrupt rows are filtered out by the staging-to-core transform.
- **Year/runtime outliers (small counts):** Retained. CHECK constraints only enforce non-negative runtime; future-dated and pre-1700 birth years are valid data.
- **`\x02` separator in akas.types:** The column is stored as TEXT in `title_aka`. Splitting on `\x02` happens in analytical queries, not in the schema.
- **Orphan nconsts (2 found):** Inserted as `[UNKNOWN]` stubs in `person` before the director/writer/principal loads to maintain strict FK integrity.
- **Genre normalization:** 28 distinct genres confirmed by quirks investigation. Pre-populated in the `genre` table during the load.

## Indexes

Primary keys auto-create unique indexes. Additional indexes are defined for:

- Filtering: `title.title_type`, `title.start_year`
- Ordering: `title_rating.average_rating`, `title_rating.num_votes`
- Reverse junction lookups: `title_director.nconst`, `title_writer.nconst`, `title_principal.nconst`, etc.
- Self-reference: `title_episode.parent_tconst`

Indexes are created **after** the tables are defined but **before** data loads. This order is important: indexing during a bulk load is much slower than indexing the final populated table.