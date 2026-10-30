# Data model and transformation decisions

The model separates raw staging, a constrained analytical core, ETL auditing and reporting views. See the [core ER diagram](er_diagram.md) and [data dictionary](data_dictionary.md).

## Table inventory and grain

`staging` has seven text tables matching source field order. The strict loader validates TSV structure before importing; `\N` becomes SQL NULL. The transformation also accepts literal `\N` values from older imports.

The 13 `core` tables are:

| Role | Tables | Grain |
|---|---|---|
| Entities | `title`, `person` | One row per `tconst` / `nconst` |
| Lookups | `genre`, `profession` | One row per distinct accepted label |
| Dependants | `title_rating`, `title_episode`, `title_aka` | Rated title; episode; title and alternate-title ordering |
| Relationships | `title_genre`, `title_director`, `title_writer`, `person_profession`, `person_known_for` | One row per unique relationship |
| Principal credit | `title_principal` | Title and principal ordering, with person and role attributes |

The design follows normalization principles for the five comma-separated relationship fields. It is not strictly atomic everywhere: `characters` intentionally remains a JSONB array, and alternate-title `types`/`attributes` remain lossless source text. `reporting.aka_types` splits `types` on ASCII 0x02 without modifying the source. Further normalization is possible if those attributes become central to analysis.

Separate rating rows distinguish an unrated title from a zero rating. Episode relationships reference `title` twice: the episode itself and its parent series. Names are display labels, not identifiers; same-named series and people stay distinct.

## Refresh behaviour

`03_transform.sql` holds a stable staging snapshot using table locks, validates required inputs, then rebuilds all core tables in one transaction. Failure rolls the core changes back. Staging remains unchanged. Use this workflow only in the dedicated project database; it is a full-snapshot rebuild, not an incremental-update service.

Duplicate valid entity keys abort the refresh. Set-valued arrays use distinct relationships, so repeated genre/director tokens do not multiply counts. Lookup IDs are regenerated deterministically for one unchanged snapshot, but can shift across snapshots; BI should use stable source identifiers and genre/profession names.

The schema creation scripts expect an empty database. Existing-schema migration is outside this workflow. Constraints/indexes remain enabled during inserts for simplicity and integrity; full-volume load performance has not been measured or optimized.

## Validation and rejection policy

`etl.rejects` stores the latest successful refresh's rejected source row or split token, source identifier and first detected reason. A record can have additional issues beyond its recorded first reason. `etl.load_summary` records source/core table counts and the load transaction time.

| Condition | Handling |
|---|---|
| Missing required IDs/names, invalid adult flags, unknown title/category values | Quarantine the source row with a reason |
| Unknown optional year/runtime/season/episode | Keep NULL; never replace missing with zero |
| Non-integer, negative or out-of-range numeric fields | Quarantine; no silent overflow or coerced rounding |
| Years | Accept 0–9999; retain plausible historical/future values rather than inventing a cutoff tied to today's date |
| Runtime | Accept nonnegative INTEGER values; visual-specific exclusions must be declared separately |
| Ratings | Require 1.0–10.0 with at most one decimal place; votes must be a nonnegative INTEGER |
| Characters | Require NULL or a valid JSON array of strings |
| Missing referenced title/person | Quarantine the link/dependant; preserve source IDs; do not fabricate people |
| Episodes | Require an episode title and a series/mini-series parent, distinct IDs and nonnegative optional numbering |
| Genre/profession arrays | Trim tokens, reject empty/overlength tokens, normalize accepted tokens and deduplicate links |
| Duplicate valid primary keys | Fail and roll back rather than choose arbitrarily |

Invalid optional values reject the row so that errors remain visible; this intentionally trades some coverage for explicit typed integrity. Inspect rejected rows before deciding whether a new source category or valid domain case requires a model change. Some dependent rows may be rejected because their parent failed validation.

The six direct mappings reconcile staging count = loaded count + rejected count. Bridge outputs have different grains from source rows, so inspect both relationship counts and token-level rejection reasons. Never sum rejected tokens and rejected titles as one loss rate.

## Reporting and interpretation

`reporting.titles` left-joins ratings at one row per title. Genre and actor-credit bridges stay separate to prevent duplicate title/vote totals. `reporting.episodes` includes unrated episodes and both episode/series IDs; `reporting.season_ratings` exposes observed and rated episode counts plus an unweighted episode-rating mean for regular seasons only.

Indexes cover title type/year/runtime, ratings/votes, episode parents, alternate-title region/language and reverse relationship lookups. Their existence is not evidence of a measured speed improvement.

The historical profile counts and proposed stub-person handling in older output are not current implementation guarantees. Current rules and validation limits are documented here and in [validation.md](validation.md); recheck the original source with the corrected parser before asserting corruption.
