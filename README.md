# Data Analysis using IMDb Non-Commercial Datasets

A learning project in relational modelling, PostgreSQL, SQL analysis and Power BI using seven IMDb datasets.

The repository now implements the complete staging-to-core transformation, explicit rejection auditing, SQL analysis and reporting views. Synthetic-data checks exercise the pipeline and known failure cases. **A full IMDb snapshot run, verified analytical findings and the finished Power BI report are still pending.**

## Project status

| Component | Evidence | Status |
|---|---|---|
| Data model | [ER diagram](docs/er_diagram.md), [design decisions](docs/data_model.md), [data dictionary](docs/data_dictionary.md) | 7 staging and 13 core tables |
| Import | [TSV validator and loader](python/load_staging.py) | Header/width/encoding checks, hashes and atomic staging load |
| Transformation | [Complete SQL load](sql/03_transform.sql) | All 13 core tables; tested with synthetic fixtures |
| Validation | [Reconciliation SQL](sql/05_validate.sql), [test evidence and limits](docs/validation.md) | Python, PGlite SQL and native PostgreSQL 16 fixture checks passed; full-data run pending |
| Analysis | [Content](sql/analysis/content.sql), [people](sql/analysis/people.sql), [ratings](sql/analysis/ratings.sql), [series](sql/analysis/series.sql) | Queries execute on fixtures; corrected series grouping and added actor/correlation analysis |
| Power BI | [Reporting views](sql/04_reporting_views.sql), [build guide](powerbi/README.md), [DAX measures](powerbi/measures.dax) | Sources prepared; saved report, screenshots and URL pending |
| Findings | Validated snapshot-specific outputs and interpretation | Pending; fixture values are not IMDb findings |

## Objective and data

Practise designing a relational database, cleaning and loading real-world data, querying it and communicating interpretable results. This is an academic portfolio project; no production deployment or business impact is claimed.

Source: [IMDb Non-Commercial Datasets](https://data.imdb.com/non-commercial-datasets/). Download from [IMDb's dataset directory](https://datasets.imdbws.com/) under its linked non-commercial terms. Files are refreshed daily and contain UTF-8 TSV data with a header and `\N` null marker.

| File | Contents | Main identifiers |
|---|---|---|
| `title.basics.tsv.gz` | Title type, names, years, runtime, genres | `tconst` |
| `title.akas.tsv.gz` | Alternative/localised titles | `titleId` = `tconst`, `ordering` |
| `title.crew.tsv.gz` | Directors and writers | `tconst`, lists of `nconst` |
| `title.episode.tsv.gz` | Episode-to-series links | `tconst`, `parentTconst` |
| `title.principals.tsv.gz` | Selected principal cast/crew credits | `tconst`, `ordering`, `nconst` |
| `title.ratings.tsv.gz` | Audience rating and votes | `tconst` |
| `name.basics.tsv.gz` | People, professions, known-for titles | `nconst` |

Raw data, generated CSVs and PBIX files are excluded from GitHub. Keep source files from one download session together and record the download time.

## Database model

- `staging`: seven unconstrained text tables matching source column order.
- `core`: 13 constrained tables with primary keys, foreign keys and indexes. Comma-separated genres, professions, directors, writers and known-for titles become junction rows.
- `etl`: latest rejected rows/tokens and table-count audit. These are supporting tables, outside the 13-table core model.
- `reporting`: views with explicit grains for Power BI. Title facts stay separate from genre/credit bridges to avoid double-counting.

See the [full ER diagram](docs/er_diagram.md). JSON character arrays and alternative-title metadata are deliberate exceptions to fully atomic relational modelling; their handling is documented in [the model rationale](docs/data_model.md).

## Reproduce a full-data run

Requires PostgreSQL **16 or later**, its `psql`/`createdb` clients, Python 3 and a checkout of this repository. The loader uses only Python's standard library. Node/PGlite is optional for tests, and pandas is optional for profiling. Use a dedicated project database and allow substantial disk space for the decompressed files, staging, indexes and transaction logs. Full-volume runtime and memory usage have not been benchmarked.

Run commands from the repository root.

### 1. Download and inspect

Download and decompress all seven files into `data/`, retaining their headers. Keep these files unchanged during validation/import.

```bash
python3 python/load_staging.py --validate-only
```

This streams each file once, validates the exact header, UTF-8, field count and unsupported control bytes, and writes `data/load_manifest.json` with SHA-256 hashes, byte sizes, row counts and validation time. **Validation time is not download time**: fill the separate download-time field from your own record; do not guess it. Each loader invocation rewrites this manifest, so add the download record to the final successful manifest and retain it with the source snapshot.

Literal quotes, JSON and `NA` are preserved. An invalid line stops the run with its location; it is not silently skipped. Source files are not repaired automatically.

### 2. Create a fresh database

```bash
createdb imdb_portfolio
psql -X -v ON_ERROR_STOP=1 -d imdb_portfolio -f sql/02_staging.sql
psql -X -v ON_ERROR_STOP=1 -d imdb_portfolio -f sql/01_schema.sql
```

The creation scripts expect a fresh database; run staging before core despite the numeric filenames. Existing schema users should test in a new database, not rerun creation over an old project.

### 3. Load staging

```bash
python3 python/load_staging.py --database imdb_portfolio
```

The loader validates all seven files before touching the database, replaces all seven staging tables in one transaction, and reconciles imported counts before committing. A failed COPY rolls the transaction back. Credentials use normal PostgreSQL connection settings/environment or `.pgpass`; do not put them in repository files.

Internally, COPY uses tab-delimited CSV mode with a backspace quote character, preserving ordinary title/JSON quotes and converting the exact `\N` sentinel. The validator rejects backspace bytes so they cannot be interpreted as quotes. See [PostgreSQL COPY options](https://www.postgresql.org/docs/16/sql-copy.html).

### 4. Transform, reconcile and expose report views

```bash
psql -X -v ON_ERROR_STOP=1 -d imdb_portfolio -f sql/03_transform.sql
psql -X -v ON_ERROR_STOP=1 -d imdb_portfolio -f sql/05_validate.sql
psql -X -v ON_ERROR_STOP=1 -d imdb_portfolio -f sql/04_reporting_views.sql
```

`03_transform.sql` **replaces the project's core tables and latest ETL audit** within one transaction. It locks staging against changes during the transformation, checks that all seven inputs are nonempty, loads parents before dependants and rebuilds lookup/junction tables. Rerunning the same snapshot produces the same logical content. Surrogate genre/profession IDs are internal to the snapshot and must not be used as permanent external identifiers.

Invalid source rows and unresolved links are preserved in `etl.rejects` with a source, key, reason and raw values. Source person names are not fabricated. Duplicate valid primary keys cause an error and roll back the refresh rather than selecting an arbitrary record. Inspect errors, fix the source/import issue and rerun. The pipeline does not establish that every plausible value is factually correct.

Review the latest audit:

```sql
SELECT * FROM etl.load_summary ORDER BY table_name;
SELECT source_table, reason, COUNT(*) AS rejected_rows_or_tokens
FROM etl.rejects
GROUP BY source_table, reason ORDER BY source_table, reason;
```

Row rejections and split-token rejections have different units. A successful validation reconciles source/loaded/rejected rows for the six directly mapped tables and confirms validated core constraints; it does **not** mean all source data was accepted. Review rejection reasons before publishing analysis. The audit represents the latest successful refresh; export it if historical runs must be retained.

### 5. Run and capture analysis

```bash
mkdir -p reports
psql -X -v ON_ERROR_STOP=1 -P pager=off -d imdb_portfolio -f sql/analysis/content.sql > reports/content.txt
psql -X -v ON_ERROR_STOP=1 -P pager=off -d imdb_portfolio -f sql/analysis/people.sql > reports/people.txt
psql -X -v ON_ERROR_STOP=1 -P pager=off -d imdb_portfolio -f sql/analysis/ratings.sql > reports/ratings.txt
psql -X -v ON_ERROR_STOP=1 -P pager=off -d imdb_portfolio -f sql/analysis/series.sql > reports/series.txt
```

| Script | Questions and definitions |
|---|---|
| Content | Title-type/genre counts, movie runtime buckets, fixed 1994–2024 movie-title comparison and ratings by genre. Genre counts overlap. |
| People | Prolific directors/writers, rated-director cohorts, both-role credits, professions and actors by distinct movie credits. Principal credits are not the full cast. |
| Ratings | Distributions, vote buckets, highest/lowest rated movies at >=50K votes, title-type means and Pearson correlation using both votes and log votes. |
| Series | Top series/episodes, observed regular-season counts, season means and first-to-last observed rated season change. Series are grouped by ID; season 0 is excluded from regular-season trends. |

Thresholds are project choices, not significance guarantees or official IMDb rankings. Ratings are audience opinions; vote counts are not unique viewers. Correlation does not imply causation. A vote-weighted mean across title ratings does not reconstruct IMDb's internal per-title rating formula. The last observed rated season may not be a show's final season.

## Power BI

Follow the [three-page build guide](powerbi/README.md) for Content & Coverage, Ratings & Votes, and Series & Seasons. It specifies table grains, relationships, measures, filter behaviour and SQL reconciliation checks.

**No completed Power BI report, report URL or screenshots are claimed yet.** Add the genuine report link and screenshots only after refreshing from the validated source and checking the intended viewer's access. Finish with three findings stating the population, filters, values and limitations. Do not use synthetic fixtures as portfolio results.

## Tests and evidence

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
npm ci
npm test
```

Python tests check TSV boundary cases. The optional PGlite suite executes PostgreSQL SQL on synthetic data, checks all 13 core tables, import parsing, analysis results, repeat refresh and rollback on bad inputs. See [validation details](docs/validation.md) for what was actually run and what remains unverified.

For a native PostgreSQL integration test, create a separate empty database:

```bash
createdb imdb_test
python3 tests/run_import_integration.py --database imdb_test
```

The test refuses databases with existing project schemas. It generates synthetic TSVs from fixtures, runs the actual Python/psql loader, transforms, reconciles and executes the analysis. The [GitHub Actions workflow](.github/workflows/validate.yml) provides a PostgreSQL 16 service for this test. The [recorded native integration run passed](https://github.com/niharkreddy-hub/imdb-analysis-pipeline/actions/runs/40980222815) using synthetic data.

## Optional profiling and historical observations

The existing [profiling script](python/profile_data.py) and [targeted investigation](python/investigate_quirks.py) use pandas. Their original dependency pins are in `python/requirements.txt`; a clean installation of those legacy pins has not been verified. `--sample` means the first N records, not a random sample; some investigations also inspect only prefixes. Full-file profiling can use substantial memory.

The saved `docs/profile_*.txt` and `docs/quirks_investigation.txt` are historical outputs without source hashes/dates. The older parser treated double quotes as CSV syntax. It has been changed to preserve quotes and fail on bad lines. **The saved claim of 487 unexpected `isAdult` values needs revalidation against the original source; its cause has not been established.** Do not label it confirmed IMDb corruption or a verified cleaning outcome.

## Remaining completion work

- [x] Implement transformations, rejection audit and repeatable refresh.
- [x] Fix series grouping and add actor, lowest-rating and correlation analysis.
- [x] Execute synthetic SQL/parser checks and prepare native integration tests.
- [x] Prepare Power BI source views, measures and build instructions.
- [ ] Run against a dated, hashed full IMDb snapshot on native PostgreSQL and review rejections.
- [ ] Record query outputs and validate interpretation against the loaded population.
- [ ] Build and verify the Power BI report; add genuine screenshots and a working viewing link.
- [ ] Publish three defensible findings with filters and limitations.

## Author

Nihar Reddy Kumbham

[GitHub](https://github.com/niharkreddy-hub) | [LinkedIn](https://www.linkedin.com/in/nihar-reddy-kumbham-73a47a216/)
