-- =============================================================================
-- IMDb Analysis Project — Staging to Core Transforms
-- =============================================================================
-- This script transforms raw text data in `staging` into typed, constrained
-- data in `core`. Run AFTER all 7 staging tables have been bulk-loaded.
--
-- Order of operations matches the FK dependency tree:
--   1. Lookup tables (genre, profession)
--   2. Strong entities (title, person)
--   3. Dependents (title_rating, title_episode, title_aka)
--   4. Junctions (title_genre, title_director, title_writer, title_principal,
--                 person_profession, person_known_for)
--
-- Every block ends with a verification query commented out for reference.
-- =============================================================================

SET search_path TO core, staging, public;
-- =============================================================================
-- 1. core.genre — populate from distinct genres in staging.title_basics
-- =============================================================================
-- The 28 distinct genres confirmed during Phase 1 quirks investigation.

INSERT INTO core.genre (genre_name)
SELECT DISTINCT TRIM(unnest(string_to_array(genres, ',')))
FROM staging.title_basics
WHERE genres IS NOT NULL
  AND genres <> '\N'
  AND genres <> ''
ORDER BY 1;

-- Verify: SELECT COUNT(*) FROM core.genre;  -- expect 28
-- Verify: SELECT * FROM core.genre ORDER BY genre_id;