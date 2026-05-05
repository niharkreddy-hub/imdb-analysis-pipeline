-- =============================================================================
-- IMDb Analysis Project — Staging Schema
-- =============================================================================
-- This script creates the `staging` schema with 7 tables — one per IMDb TSV file.
-- Every column is TEXT with no constraints. The schema accepts data exactly as
-- it appears in the raw TSVs, including the \N null sentinel.
--
-- Phase 4 will then transform staging data into the typed, constrained core schema.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS staging;
SET search_path TO staging, public;

-- One-to-one column mapping with title.basics.tsv
CREATE TABLE staging.title_basics (
    tconst            TEXT,
    title_type        TEXT,
    primary_title     TEXT,
    original_title    TEXT,
    is_adult          TEXT,
    start_year        TEXT,
    end_year          TEXT,
    runtime_minutes   TEXT,
    genres            TEXT
);

CREATE TABLE staging.title_ratings (
    tconst          TEXT,
    average_rating  TEXT,
    num_votes       TEXT
);

CREATE TABLE staging.title_crew (
    tconst     TEXT,
    directors  TEXT,
    writers    TEXT
);

CREATE TABLE staging.title_episode (
    tconst          TEXT,
    parent_tconst   TEXT,
    season_number   TEXT,
    episode_number  TEXT
);

CREATE TABLE staging.title_principals (
    tconst      TEXT,
    ordering    TEXT,
    nconst      TEXT,
    category    TEXT,
    job         TEXT,
    characters  TEXT
);

CREATE TABLE staging.title_akas (
    title_id            TEXT,    -- IMDb names this 'titleId' here; same as tconst elsewhere
    ordering            TEXT,
    title               TEXT,
    region              TEXT,
    language            TEXT,
    types               TEXT,
    attributes          TEXT,
    is_original_title   TEXT
);

CREATE TABLE staging.name_basics (
    nconst              TEXT,
    primary_name        TEXT,
    birth_year          TEXT,
    death_year          TEXT,
    primary_profession  TEXT,
    known_for_titles    TEXT
);

-- =============================================================================
-- DONE
-- =============================================================================
-- Verification queries (run manually after script completes):
--
--   SELECT schemaname, tablename FROM pg_tables WHERE schemaname = 'staging' ORDER BY tablename;
--
-- =============================================================================