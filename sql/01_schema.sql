-- =============================================================================
-- IMDb Analysis Project — Core Schema
-- =============================================================================
-- This script creates the analytical `core` schema with 13 tables.
-- Run after 02_staging.sql.
--
-- Order of operations:
--   1. CREATE SCHEMA
--   2. Lookup tables (genre, profession)
--   3. Strong entities (title, person)
--   4. Dependent tables (title_rating, title_episode, title_aka)
--   5. Junction tables (6 of them)
--   6. Indexes
--
-- After this script runs, all tables exist but are empty.
-- Data is loaded by subsequent scripts in Phase 4.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS core;
SET search_path TO core, public;


-- =============================================================================
-- 1. LOOKUP TABLES
-- =============================================================================

-- Genre: 28 canonical IMDb genres, populated during data load.
CREATE TABLE core.genre (
    genre_id    SERIAL       PRIMARY KEY,
    genre_name  VARCHAR(50)  NOT NULL UNIQUE
);

COMMENT ON TABLE core.genre IS
    'Lookup table for the 28 canonical IMDb genres. Populated from title.basics.genres during the data load.';


-- Profession: ~30 atomic professions, populated during data load.
CREATE TABLE core.profession (
    profession_id    SERIAL       PRIMARY KEY,
    profession_name  VARCHAR(50)  NOT NULL UNIQUE
);

COMMENT ON TABLE core.profession IS
    'Lookup table for atomic professions. Populated from name.basics.primaryProfession during the data load.';


-- =============================================================================
-- 2. STRONG ENTITIES
-- =============================================================================

-- Title: every movie, series, episode, video game, etc.
-- Invalid required fields are quarantined in etl.rejects during transformation.
CREATE TABLE core.title (
    tconst           VARCHAR(12)  PRIMARY KEY,
    title_type       VARCHAR(20)  NOT NULL,
    primary_title    TEXT         NOT NULL,
    original_title   TEXT,
    is_adult         BOOLEAN      NOT NULL,
    start_year       SMALLINT,
    end_year         SMALLINT,
    runtime_minutes  INTEGER,

    CONSTRAINT chk_title_type CHECK (title_type IN (
        'movie', 'short', 'tvEpisode', 'tvSeries', 'tvMovie',
        'tvMiniSeries', 'tvSpecial', 'tvShort', 'video',
        'videoGame', 'tvPilot'
    )),
    CONSTRAINT chk_runtime_nonneg CHECK (runtime_minutes IS NULL OR runtime_minutes >= 0)
);

COMMENT ON TABLE core.title IS
    'All IMDb titles. Format of tconst: tt followed by digits. Invalid rows are retained in the ETL rejection audit.';


-- Person: every IMDb person record.
-- Contains source person records only; missing references are audited, not fabricated.
CREATE TABLE core.person (
    nconst        VARCHAR(12)  PRIMARY KEY,
    primary_name  TEXT         NOT NULL,
    birth_year    SMALLINT,
    death_year    SMALLINT
);

COMMENT ON TABLE core.person IS
    'All IMDb persons. Format of nconst: nm followed by digits. Unresolved references from credits are retained in etl.rejects.';


-- =============================================================================
-- 3. DEPENDENT TABLES (FK to title)
-- =============================================================================

-- Rating: one-to-one with title (only ~13% of titles have ratings)
CREATE TABLE core.title_rating (
    tconst          VARCHAR(12)   PRIMARY KEY,
    average_rating  NUMERIC(3,1)  NOT NULL,
    num_votes       INTEGER       NOT NULL,

    CONSTRAINT fk_rating_title FOREIGN KEY (tconst)
        REFERENCES core.title(tconst) ON DELETE CASCADE,
    CONSTRAINT chk_rating_range CHECK (average_rating BETWEEN 1.0 AND 10.0),
    CONSTRAINT chk_votes_nonneg CHECK (num_votes >= 0)
);

COMMENT ON TABLE core.title_rating IS
    'Aggregate user rating per title. One-to-one with title; only rated titles appear here.';


-- Episode: hierarchy data for TV episodes
CREATE TABLE core.title_episode (
    tconst          VARCHAR(12)  PRIMARY KEY,
    parent_tconst   VARCHAR(12)  NOT NULL,
    season_number   SMALLINT,
    episode_number  SMALLINT,

    CONSTRAINT fk_episode_self FOREIGN KEY (tconst)
        REFERENCES core.title(tconst) ON DELETE CASCADE,
    CONSTRAINT fk_episode_parent FOREIGN KEY (parent_tconst)
        REFERENCES core.title(tconst) ON DELETE CASCADE
);

COMMENT ON TABLE core.title_episode IS
    'Episode-to-series relationship. Both tconst and parent_tconst reference core.title (self-referencing through this table).';


-- Aka: localized/alternate titles
CREATE TABLE core.title_aka (
    tconst             VARCHAR(12)  NOT NULL,
    ordering           SMALLINT     NOT NULL,
    title              TEXT         NOT NULL,
    region             VARCHAR(10),
    language           VARCHAR(10),
    types              TEXT,
    attributes         TEXT,
    is_original_title  BOOLEAN,

    PRIMARY KEY (tconst, ordering),
    CONSTRAINT fk_aka_title FOREIGN KEY (tconst)
        REFERENCES core.title(tconst) ON DELETE CASCADE
);

COMMENT ON TABLE core.title_aka IS
    'Localized and alternate titles. Composite PK on (tconst, ordering). Note: types column uses ASCII 0x02 as sub-delimiter, not comma.';


-- =============================================================================
-- 4. JUNCTION TABLES
-- =============================================================================

-- Title <-> Genre
CREATE TABLE core.title_genre (
    tconst    VARCHAR(12)  NOT NULL,
    genre_id  INTEGER      NOT NULL,

    PRIMARY KEY (tconst, genre_id),
    CONSTRAINT fk_tg_title FOREIGN KEY (tconst)
        REFERENCES core.title(tconst) ON DELETE CASCADE,
    CONSTRAINT fk_tg_genre FOREIGN KEY (genre_id)
        REFERENCES core.genre(genre_id) ON DELETE RESTRICT
);

COMMENT ON TABLE core.title_genre IS
    'M:N junction between title and genre. Populated by splitting title.basics.genres on comma during load.';


-- Title <-> Person (as director)
CREATE TABLE core.title_director (
    tconst   VARCHAR(12)  NOT NULL,
    nconst   VARCHAR(12)  NOT NULL,

    PRIMARY KEY (tconst, nconst),
    CONSTRAINT fk_td_title FOREIGN KEY (tconst)
        REFERENCES core.title(tconst) ON DELETE CASCADE,
    CONSTRAINT fk_td_person FOREIGN KEY (nconst)
        REFERENCES core.person(nconst) ON DELETE CASCADE
);

COMMENT ON TABLE core.title_director IS
    'M:N junction: which persons directed which titles. Populated by splitting title.crew.directors on comma during load.';


-- Title <-> Person (as writer)
CREATE TABLE core.title_writer (
    tconst   VARCHAR(12)  NOT NULL,
    nconst   VARCHAR(12)  NOT NULL,

    PRIMARY KEY (tconst, nconst),
    CONSTRAINT fk_tw_title FOREIGN KEY (tconst)
        REFERENCES core.title(tconst) ON DELETE CASCADE,
    CONSTRAINT fk_tw_person FOREIGN KEY (nconst)
        REFERENCES core.person(nconst) ON DELETE CASCADE
);

COMMENT ON TABLE core.title_writer IS
    'M:N junction: which persons wrote which titles. Populated by splitting title.crew.writers on comma during load.';


-- Title <-> Person (as principal cast/crew, with role attributes)
CREATE TABLE core.title_principal (
    tconst      VARCHAR(12)  NOT NULL,
    ordering    SMALLINT     NOT NULL,
    nconst      VARCHAR(12)  NOT NULL,
    category    VARCHAR(30)  NOT NULL,
    job         TEXT,
    characters  JSONB,

    PRIMARY KEY (tconst, ordering),
    CONSTRAINT fk_tp_title FOREIGN KEY (tconst)
        REFERENCES core.title(tconst) ON DELETE CASCADE,
    CONSTRAINT fk_tp_person FOREIGN KEY (nconst)
        REFERENCES core.person(nconst) ON DELETE CASCADE,
    CONSTRAINT chk_tp_category CHECK (category IN (
        'actor', 'actress', 'archive_footage', 'archive_sound',
        'casting_director', 'cinematographer', 'composer',
        'director', 'editor', 'producer', 'production_designer',
        'self', 'writer'
    ))
);

COMMENT ON TABLE core.title_principal IS
    'Associative entity: M:N between title and person, with role attributes (category, job, characters JSONB, ordering). Composite PK on (tconst, ordering).';


-- Person <-> Profession
CREATE TABLE core.person_profession (
    nconst         VARCHAR(12)  NOT NULL,
    profession_id  INTEGER      NOT NULL,

    PRIMARY KEY (nconst, profession_id),
    CONSTRAINT fk_pp_person FOREIGN KEY (nconst)
        REFERENCES core.person(nconst) ON DELETE CASCADE,
    CONSTRAINT fk_pp_profession FOREIGN KEY (profession_id)
        REFERENCES core.profession(profession_id) ON DELETE RESTRICT
);

COMMENT ON TABLE core.person_profession IS
    'M:N junction between person and profession. Populated by splitting name.basics.primaryProfession on comma during load.';


-- Person -> Title (knownForTitles)
CREATE TABLE core.person_known_for (
    nconst  VARCHAR(12)  NOT NULL,
    tconst  VARCHAR(12)  NOT NULL,

    PRIMARY KEY (nconst, tconst),
    CONSTRAINT fk_pk_person FOREIGN KEY (nconst)
        REFERENCES core.person(nconst) ON DELETE CASCADE,
    CONSTRAINT fk_pk_title FOREIGN KEY (tconst)
        REFERENCES core.title(tconst) ON DELETE CASCADE
);

COMMENT ON TABLE core.person_known_for IS
    'M:N junction: which titles each person is known for. Populated by splitting name.basics.knownForTitles on comma during load.';


-- =============================================================================
-- 5. INDEXES
-- =============================================================================
-- Note: Primary keys and unique constraints already create indexes automatically.
-- These are additional indexes to speed up common analytical queries in Phase 5.

-- Title: filter by type, year, runtime
CREATE INDEX idx_title_type        ON core.title(title_type);
CREATE INDEX idx_title_start_year  ON core.title(start_year);
CREATE INDEX idx_title_runtime     ON core.title(runtime_minutes);

-- Title rating: order by rating, by votes
CREATE INDEX idx_rating_avg        ON core.title_rating(average_rating);
CREATE INDEX idx_rating_votes      ON core.title_rating(num_votes);

-- Title episode: find all episodes of a series
CREATE INDEX idx_episode_parent    ON core.title_episode(parent_tconst);
CREATE INDEX idx_episode_season    ON core.title_episode(parent_tconst, season_number);

-- Title aka: filter by region/language
CREATE INDEX idx_aka_region        ON core.title_aka(region);
CREATE INDEX idx_aka_language      ON core.title_aka(language);

-- Person: search by name (note: trigram index would be better for fuzzy match)
CREATE INDEX idx_person_name       ON core.person(primary_name);

-- Junction reverse-lookup indexes (the FK from title side already has the title_xxx index;
-- these add the reverse direction for queries like "all titles by this person")
CREATE INDEX idx_director_nconst   ON core.title_director(nconst);
CREATE INDEX idx_writer_nconst     ON core.title_writer(nconst);
CREATE INDEX idx_principal_nconst  ON core.title_principal(nconst);
CREATE INDEX idx_principal_cat     ON core.title_principal(category);
CREATE INDEX idx_known_for_tconst  ON core.person_known_for(tconst);
CREATE INDEX idx_pp_profession     ON core.person_profession(profession_id);
CREATE INDEX idx_tg_genre          ON core.title_genre(genre_id);


-- =============================================================================
-- DONE
-- =============================================================================
-- Verification queries (run manually after script completes):
--
--   SELECT schemaname, tablename FROM pg_tables WHERE schemaname = 'core' ORDER BY tablename;
--   SELECT count(*) FROM core.title;     -- expect 0 until data load
--
-- =============================================================================
