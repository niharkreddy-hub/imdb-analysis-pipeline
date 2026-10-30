# Validation record and limits

## Executed locally

The following checks passed during implementation using entirely synthetic fixtures:

- Seven Python standard-library TSV tests: exact headers, missing/extra fields, empty input, UTF-8/control-byte errors, literal quotes/JSON/NA/null markers and safe COPY paths.
- SQL suite on **PGlite 0.5.13**, which reported **PostgreSQL 18.6 on WebAssembly**. This is PostgreSQL SQL execution, not a native PostgreSQL 16 server test.
- PostgreSQL COPY parsing with tab delimiter/backspace quote character: title quotes and JSON preserved, literal `NA` retained and exact `\N` converted to NULL.
- Both schemas, all 13 core-table transformations, reporting views and source/loaded/rejected reconciliation.
- Null handling, invalid flag/year/runtime/vote values, unknown types, JSON validation, missing references, duplicate array tokens and known-for links.
- Identical logical fixture content/counts on repeated refresh in the same connection.
- All four analysis scripts execute. Assertions confirm separate same-named-series season averages (2 and 10, rather than a merged 6), distinct actor movie counts and a known positive Pearson correlation.
- An ambiguous duplicate valid primary key causes rollback; an empty input table prevents refresh; previous core values survive both failures.

Fixture values are test expectations, not observations about IMDb. Saved profiles in `docs/` were not regenerated and are not newly verified findings.

## Native PostgreSQL integration

`tests/run_import_integration.py` exercises the actual psql-based loader, seven generated TSVs, typed transformation, reporting views, reconciliation, repeat execution and all analysis scripts. It refuses an existing project database. A PostgreSQL 16 GitHub Actions service is configured in `.github/workflows/validate.yml`.

**Passed on 30 October 2026:** [native PostgreSQL 16 integration run](https://github.com/niharkreddy-hub/imdb-analysis-pipeline/actions/runs/40980222815), code commit `d000d430d17c7c771737ce87dc03eb166582663b`. Both the seven Python tests and the actual psql import/transform/reconciliation/repeat-run/analysis step succeeded. This is synthetic-data integration evidence, not a full IMDb snapshot run.

## Still unverified

- A complete dated/hashed IMDb snapshot through the new workflow on native PostgreSQL, including load duration, storage and query performance.
- Actual source rejection rates, source/parser causes of the historical 487 unexpected adult flags, and coverage lost through missing references.
- Concurrent-reader performance and operational scheduling. The project is a single-writer academic snapshot workflow.
- Clean installation of the legacy pandas profiling dependencies.
- Power BI connection/refresh, DAX execution, relationships, visuals, filters, SQL reconciliation, screenshot evidence and viewer access.

## Reproduce

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
npm ci
npm test
createdb imdb_test
python3 tests/run_import_integration.py --database imdb_test
```

The native test requires PostgreSQL client/server access. The optional Node dependency is for SQL smoke tests only; the actual data pipeline requires no Node runtime.
