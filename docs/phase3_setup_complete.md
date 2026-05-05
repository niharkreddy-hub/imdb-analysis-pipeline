# Phase 3 — Database Setup

Completed setup tasks:

- PostgreSQL 16 installed via Homebrew
- Service started via `brew services start postgresql@16`
- Database `imdb` created
- `staging` schema created with 7 tables (from sql/02_staging.sql)
- `core` schema created with 13 tables and all constraints (from sql/01_schema.sql)
- DBeaver Community Edition installed for GUI browsing

Database connection: `psql imdb` from terminal, or DBeaver localhost:5432.
