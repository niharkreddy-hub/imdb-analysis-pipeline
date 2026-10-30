# Data Analysis using IMDb Non-Commercial Datasets

A learning project exploring data modelling, PostgreSQL database management, SQL analysis and Power BI visualisation using seven IMDb datasets.

The work covers the path from inspecting raw TSV files to designing a relational model, preparing data for analysis and communicating findings. The published repository currently contains profiling evidence, database definitions and SQL analysis scripts. The complete staging-to-core load and Power BI report assets still need to be added.

## Project status

| Component | Evidence in this repository | Current status |
| --- | --- | --- |
| Dataset exploration | [Profiling script](python/profile_data.py), saved profiles in `docs/` and [targeted investigation](docs/quirks_investigation.txt) | Published |
| Relational data model | [Design rationale](docs/data_model.md), [ER diagram](docs/er_diagram.md) and [data dictionary](docs/data_dictionary.md) | Published |
| PostgreSQL setup | [7 staging tables](sql/02_staging.sql), [13 core tables](sql/01_schema.sql) and [setup record](docs/phase3_setup_complete.md) | Published |
| Data cleaning and transformation | [Transformation script](sql/03_transform.sql) | Partial: currently populates the genre lookup only |
| Exploratory SQL analysis | [Content](sql/analysis/content.sql), [people](sql/analysis/people.sql), [ratings](sql/analysis/ratings.sql) and [series](sql/analysis/series.sql) queries | Written; full reproduction requires the remaining data loads and validation |
| Power BI report | Interactive report link and screenshots | Not yet published in this repository |
| Analytical findings | Validated query outputs and interpretation | Still to be published |

## Objectives

- Design a relational model with appropriate keys, data types and constraints.
- Import the seven IMDb source files into PostgreSQL and handle missing values and multi-valued attributes.
- Use SQL to explore content, contributors, audience ratings and television series.
- Build an interactive Power BI report that explains the results and their limitations.

## Data source

Source: [IMDb Non-Commercial Datasets](https://developer.imdb.com/non-commercial-datasets/). Download the files from [IMDb's dataset directory](https://datasets.imdbws.com/).

IMDb supplies UTF-8, gzipped, tab-separated files with a header row. The `\N` marker denotes a missing value. The source is refreshed daily, so row counts and results depend on the download date.

| Source file | Contents | Main identifiers |
| --- | --- | --- |
| `title.basics.tsv.gz` | Title type, names, years, runtime and genres | `tconst` |
| `title.akas.tsv.gz` | Alternative and localised titles | `titleId` corresponds to `tconst`; `ordering` identifies each alternative |
| `title.crew.tsv.gz` | Directors and writers | `tconst`; arrays of `nconst` values |
| `title.episode.tsv.gz` | Episode-to-series relationships | Episode `tconst` and series `parentTconst` |
| `title.principals.tsv.gz` | Principal cast and crew credits | `tconst`, `ordering`, `nconst` |
| `title.ratings.tsv.gz` | Average audience rating and number of votes | `tconst` |
| `name.basics.tsv.gz` | People, professions and known-for titles | `nconst`; arrays of `tconst` values |

Obtain source data directly from IMDb and follow its linked non-commercial terms. Raw datasets are excluded from this repository.

## Data model

The database separates raw input from the relational model:

- **`staging`** contains seven tables with text columns matching the source-file column order. It provides a place to inspect values before casting them.
- **`core`** contains 13 tables for titles, people, ratings, episodes, alternative titles, genres, professions and their relationships.

Junction tables represent many-to-many relationships such as titles and genres, or titles and directors. Primary keys, foreign keys and check constraints define the intended integrity rules. Indexes support common filters and joins; no measured performance improvement is claimed here.

See the [complete ER diagram](docs/er_diagram.md), [column definitions](docs/data_dictionary.md) and [modelling decisions](docs/data_model.md).

## Repository guide

| Path | Purpose |
| --- | --- |
| `python/profile_data.py` | Column-level null counts, distinct values, distributions and sample inspection |
| `python/investigate_quirks.py` | Targeted checks for field values, outliers, JSON and orphan references |
| `python/requirements.txt` | Dependency versions recorded for the Python work |
| `sql/02_staging.sql` | Staging table definitions |
| `sql/01_schema.sql` | Core table definitions, constraints and indexes |
| `sql/03_transform.sql` | Initial transformation step; remaining table loads are not implemented |
| `sql/analysis/` | Exploratory queries grouped by topic |
| `docs/` | Model documentation and saved profiling outputs |

## Local setup

Use PostgreSQL 16 with the `psql` client, Python 3 and a local checkout of this repository. Power BI is used for the visualisation component. Allow sufficient local disk space and memory for the downloaded files and database; the full datasets are large.

These steps document the schema and staging workflow. They do not yet reproduce a complete analytical database. A clean installation of the recorded Python dependency pins has not been verified.

### 1. Prepare the source files

Download and decompress all seven `.tsv.gz` files into a local `data/` directory at the repository root. Retain the header row in each `.tsv` file and record the download date. Keep files from the same download session together.

Run commands from the repository root so that the relative paths below resolve correctly.

### 2. Prepare the Python environment

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r python/requirements.txt
```

Profile one file, or inspect a limited prefix for an initial check:

```bash
python python/profile_data.py data/title.basics.tsv
python python/profile_data.py data/title.principals.tsv --sample 500000
python python/investigate_quirks.py
```

`--sample` reads the first N records, not a random sample. Some investigation checks also read only a prefix. Interpret those results as observations about the inspected records, not guarantees about the whole dataset.

### 3. Create a fresh local database and schemas

Use a new database to avoid changing an existing project database:

```bash
createdb imdb_portfolio
psql -X -v ON_ERROR_STOP=1 -d imdb_portfolio -f sql/02_staging.sql
psql -X -v ON_ERROR_STOP=1 -d imdb_portfolio -f sql/01_schema.sql
```

The intended order is staging first, then core, despite the numeric filenames. The table-creation scripts expect a fresh database and are not general rerun scripts.

### 4. Load the raw files into staging

Open `psql` from the repository root:

```bash
psql -X -v ON_ERROR_STOP=1 -d imdb_portfolio
```

Run each `\copy` command as one line:

```sql
\copy staging.title_basics FROM 'data/title.basics.tsv' WITH (FORMAT csv, DELIMITER E'\t', HEADER true, NULL '\N', QUOTE E'\b', ENCODING 'UTF8');
\copy staging.title_akas FROM 'data/title.akas.tsv' WITH (FORMAT csv, DELIMITER E'\t', HEADER true, NULL '\N', QUOTE E'\b', ENCODING 'UTF8');
\copy staging.title_crew FROM 'data/title.crew.tsv' WITH (FORMAT csv, DELIMITER E'\t', HEADER true, NULL '\N', QUOTE E'\b', ENCODING 'UTF8');
\copy staging.title_episode FROM 'data/title.episode.tsv' WITH (FORMAT csv, DELIMITER E'\t', HEADER true, NULL '\N', QUOTE E'\b', ENCODING 'UTF8');
\copy staging.title_principals FROM 'data/title.principals.tsv' WITH (FORMAT csv, DELIMITER E'\t', HEADER true, NULL '\N', QUOTE E'\b', ENCODING 'UTF8');
\copy staging.title_ratings FROM 'data/title.ratings.tsv' WITH (FORMAT csv, DELIMITER E'\t', HEADER true, NULL '\N', QUOTE E'\b', ENCODING 'UTF8');
\copy staging.name_basics FROM 'data/name.basics.tsv' WITH (FORMAT csv, DELIMITER E'\t', HEADER true, NULL '\N', QUOTE E'\b', ENCODING 'UTF8');
```

CSV mode is configured with a tab delimiter and a backspace quote character so ordinary double quotes in titles and JSON are preserved. This assumes the files contain no backspace quoting. Validate parsing on the downloaded snapshot before treating a shifted field as a source-data defect. See [PostgreSQL COPY documentation](https://www.postgresql.org/docs/16/sql-copy.html) for the import options.

These commands append records. Run them once against empty staging tables. Record each `COPY` row count, compare it with the source-file record count, and inspect sample rows, nulls and key columns before proceeding.

### 5. Transform and validate

The current `sql/03_transform.sql` only inserts distinct genres into `core.genre`. It does not yet populate titles, people, ratings, episodes, alternative titles or the junction tables. Do not treat it as a complete ETL pipeline.

Remaining work includes typed casts, array splitting, referential-integrity handling and a documented approach to invalid records. Resolve parent records before dependent records, preserve rejected rows with reasons, and check row counts and key integrity after each load. The genre insert is also not safe to rerun unchanged against an already populated lookup.

## SQL analysis

Once the required core tables are populated and validated, the analysis scripts address:

| Script | Questions and metrics |
| --- | --- |
| [Content](sql/analysis/content.sql) | Title-type counts, genre distribution, runtime buckets, production by year and average rating by genre |
| [People](sql/analysis/people.sql) | Prolific directors and writers, highly rated directors, director/writer credits and profession distribution |
| [Ratings](sql/analysis/ratings.sql) | Rating distribution, vote-count buckets, top-rated titles, most-voted titles and average ratings by title type |
| [Series](sql/analysis/series.sql) | Top series and episodes, episode counts, season averages and changes across seasons |

For example, after completing the required loads:

```bash
psql -X -v ON_ERROR_STOP=1 -d imdb_portfolio -f sql/analysis/content.sql
```

Suggested extensions from the brief include actor rankings and lowest-rated titles. Vote-count buckets currently support a descriptive comparison; a correlation coefficient would provide an additional analysis of the vote/rating relationship.

Before reporting season trends, update Series Q3 to group by the unique series identifier as well as the display title. Grouping only by `primary_title` can merge distinct shows with the same name. Review how specials, missing seasons, vote thresholds and unrated episodes affect the other series metrics.

## Power BI report

**Report link and screenshots are not yet available in this repository.** No live report or dashboard result is implied by the SQL scripts.

The report is intended to contain:

- A content overview with title types, genres and runtime distributions.
- Audience-rating and vote-count comparisons with clearly explained thresholds.
- Contributor and television-series views supported by validated queries.
- Filters for relevant dimensions such as title type, genre and year.

When the report assets are available, add an interactive viewing link and screenshots here, followed by three findings that identify the metric, population, filters and limitations. Test the report link as an intended external viewer. Keep a static preview available alongside the interactive report.

The current `.gitignore` excludes `.pbix` and CSV files. A report URL and PNG screenshots can be added without changing that rule.

## Data quality observations and limitations

The [saved investigation output](docs/quirks_investigation.txt) records 487 unexpected `isAdult` values in 12,479,598 parsed title records, unusual alternative-title separators, runtime/year outliers and orphan-reference checks. These are observations from that saved run; the source snapshot date and file hashes still need recording.

Confirm the original records and parser behaviour before attributing anomalies to IMDb. The existing investigation's printed suggestion to drop records is a proposed handling rule, not evidence that the full filtering step was implemented.

Additional limits:

- Current scripts do not reproduce the complete database load from a fresh checkout.
- Analytical query outputs, dashboard screenshots and final findings are not published here.
- IMDb coverage and user votes do not represent the entire viewing audience. Associations between votes and ratings do not establish causation.
- A vote-weighted average across title ratings is a project-defined summary, not a reconstruction of IMDb's title-rating algorithm.

## Completion checklist

- [ ] Record dataset snapshot dates, file hashes and row counts.
- [ ] Complete staging-to-core transformations and rejected-record handling.
- [ ] Verify counts, unique keys and foreign-key relationships after loading.
- [ ] Correct series grouping and validate query outputs.
- [ ] Consider extending the analysis with actor rankings, lowest-rated titles and a defined vote/rating correlation measure.
- [ ] Build the Power BI report and publish its permitted viewing link and screenshots.
- [ ] Write findings with their definitions, filters and limitations.
- [ ] Verify the documented workflow in a fresh local environment.

## Author

Nihar Reddy Kumbham

[GitHub profile](https://github.com/niharkreddy-hub) | [LinkedIn](https://www.linkedin.com/in/nihar-reddy-kumbham-73a47a216/)
