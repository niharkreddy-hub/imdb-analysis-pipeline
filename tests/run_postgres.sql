-- Only run in a NEW, EMPTY test database. Uses synthetic fixtures.
\set ON_ERROR_STOP on
\ir ../sql/02_staging.sql
\ir ../sql/01_schema.sql
\ir fixture.sql
\ir ../sql/03_transform.sql
\ir ../sql/04_reporting_views.sql
\ir ../sql/05_validate.sql
\ir assertions.sql
-- Verify repeat refresh in the same connection.
\ir ../sql/03_transform.sql
\ir ../sql/05_validate.sql
\ir assertions.sql
\ir ../sql/analysis/content.sql
\ir ../sql/analysis/people.sql
\ir ../sql/analysis/ratings.sql
\ir ../sql/analysis/series.sql
