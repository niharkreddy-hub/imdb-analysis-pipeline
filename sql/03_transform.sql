-- Transform one complete staged snapshot into the 13 core tables.
-- PostgreSQL 16+. Run with psql -X -v ON_ERROR_STOP=1 -f sql/03_transform.sql.
-- Rebuilds core and the latest ETL audit atomically; staging is never modified.
-- Use a dedicated project database. Review etl.rejects after every successful run.
BEGIN;
-- Hold one stable staged snapshot while deriving every core table.
LOCK TABLE staging.title_basics, staging.name_basics, staging.title_ratings,
    staging.title_crew, staging.title_episode, staging.title_principals,
    staging.title_akas IN SHARE MODE;
CREATE SCHEMA IF NOT EXISTS etl;
CREATE TABLE IF NOT EXISTS etl.rejects (
    source_table TEXT NOT NULL,
    source_key TEXT,
    reason TEXT NOT NULL,
    raw_row JSONB NOT NULL
);
CREATE TABLE IF NOT EXISTS etl.load_summary (
    table_name TEXT PRIMARY KEY,
    row_count BIGINT NOT NULL,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- The raw TSV importer preserves quotes and converts the exact \\N sentinel.
-- These helpers also accept staging populated with literal \\N values.
CREATE OR REPLACE FUNCTION etl.clean(value TEXT) RETURNS TEXT
LANGUAGE SQL IMMUTABLE PARALLEL SAFE AS $$
    SELECT NULLIF(NULLIF(value, '\N'), '')
$$;
CREATE OR REPLACE FUNCTION etl.valid_int(value TEXT, lo INTEGER, hi INTEGER)
RETURNS BOOLEAN LANGUAGE SQL IMMUTABLE PARALLEL SAFE AS $$
    SELECT CASE
        WHEN etl.clean(value) IS NULL THEN TRUE
        WHEN value ~ '^[0-9]+$' AND pg_input_is_valid(value, 'integer')
            THEN value::INTEGER BETWEEN lo AND hi
        ELSE FALSE
    END
$$;
CREATE OR REPLACE FUNCTION etl.valid_characters(value TEXT) RETURNS BOOLEAN
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $$
DECLARE parsed JSONB;
BEGIN
    IF etl.clean(value) IS NULL THEN RETURN TRUE; END IF;
    IF NOT pg_input_is_valid(value, 'jsonb') THEN RETURN FALSE; END IF;
    parsed := value::JSONB;
    IF jsonb_typeof(parsed) <> 'array' THEN RETURN FALSE; END IF;
    RETURN NOT EXISTS (SELECT 1 FROM jsonb_array_elements(parsed) AS x(v)
                       WHERE jsonb_typeof(v) <> 'string');
END $$;

-- A missing input must not erase a previously usable database.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM staging.title_basics)
       OR NOT EXISTS (SELECT 1 FROM staging.name_basics)
       OR NOT EXISTS (SELECT 1 FROM staging.title_ratings)
       OR NOT EXISTS (SELECT 1 FROM staging.title_crew)
       OR NOT EXISTS (SELECT 1 FROM staging.title_episode)
       OR NOT EXISTS (SELECT 1 FROM staging.title_principals)
       OR NOT EXISTS (SELECT 1 FROM staging.title_akas) THEN
        RAISE EXCEPTION 'All seven staging tables must contain data; no core tables were changed.';
    END IF;
END $$;

TRUNCATE core.title_genre, core.title_director, core.title_writer,
    core.title_principal, core.person_profession, core.person_known_for,
    core.title_rating, core.title_episode, core.title_aka, core.title,
    core.person, core.genre, core.profession RESTART IDENTITY;
TRUNCATE etl.rejects, etl.load_summary;

CREATE TEMP VIEW v_title AS
SELECT s.*, CASE
    WHEN COALESCE(tconst ~ '^tt[0-9]{1,10}$', FALSE) = FALSE THEN 'invalid_title_id'
    WHEN etl.clean(primary_title) IS NULL THEN 'missing_primary_title'
    WHEN COALESCE(title_type IN ('movie','short','tvEpisode','tvSeries','tvMovie','tvMiniSeries','tvSpecial','tvShort','video','videoGame','tvPilot'), FALSE) = FALSE THEN 'unknown_title_type'
    WHEN COALESCE(is_adult IN ('0','1'), FALSE) = FALSE THEN 'invalid_is_adult'
    WHEN NOT etl.valid_int(start_year, 0, 9999) OR NOT etl.valid_int(end_year, 0, 9999) THEN 'invalid_year'
    WHEN NOT etl.valid_int(runtime_minutes, 0, 2147483647) THEN 'invalid_runtime'
    ELSE NULL END AS reject_reason
FROM staging.title_basics s;
INSERT INTO etl.rejects
SELECT 'title_basics', tconst, reject_reason, to_jsonb(v) - 'reject_reason'
FROM v_title v WHERE reject_reason IS NOT NULL;
INSERT INTO core.title
SELECT tconst, title_type, primary_title, etl.clean(original_title), is_adult = '1',
       etl.clean(start_year)::SMALLINT, etl.clean(end_year)::SMALLINT,
       etl.clean(runtime_minutes)::INTEGER
FROM v_title WHERE reject_reason IS NULL;

CREATE TEMP VIEW v_person AS
SELECT s.*, CASE
    WHEN COALESCE(nconst ~ '^nm[0-9]{1,10}$', FALSE) = FALSE THEN 'invalid_person_id'
    WHEN etl.clean(primary_name) IS NULL THEN 'missing_primary_name'
    WHEN NOT etl.valid_int(birth_year, 0, 9999) OR NOT etl.valid_int(death_year, 0, 9999) THEN 'invalid_year'
    ELSE NULL END AS reject_reason
FROM staging.name_basics s;
INSERT INTO etl.rejects
SELECT 'name_basics', nconst, reject_reason, to_jsonb(v) - 'reject_reason'
FROM v_person v WHERE reject_reason IS NOT NULL;
INSERT INTO core.person
SELECT nconst, primary_name, etl.clean(birth_year)::SMALLINT, etl.clean(death_year)::SMALLINT
FROM v_person WHERE reject_reason IS NULL;
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM core.title) OR NOT EXISTS (SELECT 1 FROM core.person) THEN
        RAISE EXCEPTION 'No valid titles or people; refresh rolled back.';
    END IF;
END $$;
ANALYZE core.title;
ANALYZE core.person;
CREATE TEMP VIEW v_genre_tokens AS
SELECT s.tconst, btrim(x.token) AS token
FROM staging.title_basics s JOIN core.title p USING (tconst)
CROSS JOIN LATERAL unnest(string_to_array(etl.clean(s.genres), ',')) x(token);
INSERT INTO etl.rejects
SELECT 'title_basics.genres', tconst, 'invalid_genre_token', to_jsonb(v)
FROM v_genre_tokens v WHERE etl.clean(token) IS NULL OR length(token) > 50;
INSERT INTO core.genre (genre_name)
SELECT DISTINCT token FROM v_genre_tokens
WHERE etl.clean(token) IS NOT NULL AND length(token) <= 50 ORDER BY token;
INSERT INTO core.title_genre
SELECT DISTINCT v.tconst, l.genre_id
FROM v_genre_tokens v JOIN core.genre l ON l.genre_name = v.token;
CREATE TEMP VIEW v_profession_tokens AS
SELECT s.nconst, btrim(x.token) AS token
FROM staging.name_basics s JOIN core.person p USING (nconst)
CROSS JOIN LATERAL unnest(string_to_array(etl.clean(s.primary_profession), ',')) x(token);
INSERT INTO etl.rejects
SELECT 'name_basics.primary_profession', nconst, 'invalid_profession_token', to_jsonb(v)
FROM v_profession_tokens v WHERE etl.clean(token) IS NULL OR length(token) > 50;
INSERT INTO core.profession (profession_name)
SELECT DISTINCT token FROM v_profession_tokens
WHERE etl.clean(token) IS NOT NULL AND length(token) <= 50 ORDER BY token;
INSERT INTO core.person_profession
SELECT DISTINCT v.nconst, l.profession_id
FROM v_profession_tokens v JOIN core.profession l ON l.profession_name = v.token;

CREATE TEMP VIEW v_rating AS
SELECT s.*, CASE
    WHEN NOT EXISTS (SELECT 1 FROM core.title t WHERE t.tconst = s.tconst) THEN 'missing_title'
    WHEN CASE WHEN average_rating ~ '^[0-9]+(\.[0-9])?$' AND pg_input_is_valid(average_rating, 'numeric') THEN average_rating::NUMERIC NOT BETWEEN 1 AND 10 ELSE TRUE END THEN 'invalid_rating'
    WHEN etl.clean(num_votes) IS NULL OR NOT etl.valid_int(num_votes, 0, 2147483647) THEN 'invalid_votes'
    ELSE NULL END AS reject_reason
FROM staging.title_ratings s;
INSERT INTO etl.rejects
SELECT 'title_ratings', tconst, reject_reason, to_jsonb(v) - 'reject_reason'
FROM v_rating v WHERE reject_reason IS NOT NULL;
INSERT INTO core.title_rating
SELECT tconst, average_rating::NUMERIC(3,1), num_votes::INTEGER
FROM v_rating WHERE reject_reason IS NULL;

CREATE TEMP VIEW v_episode AS
SELECT s.*, CASE
    WHEN NOT EXISTS (SELECT 1 FROM core.title t WHERE t.tconst = s.tconst) THEN 'missing_episode_title'
    WHEN NOT EXISTS (SELECT 1 FROM core.title p WHERE p.tconst = s.parent_tconst) THEN 'missing_parent_title'
    WHEN tconst = parent_tconst THEN 'self_parent'
    WHEN NOT EXISTS (SELECT 1 FROM core.title t WHERE t.tconst=s.tconst AND t.title_type='tvEpisode') OR NOT EXISTS (SELECT 1 FROM core.title p WHERE p.tconst=s.parent_tconst AND p.title_type IN ('tvSeries','tvMiniSeries')) THEN 'invalid_episode_or_parent_type'
    WHEN NOT etl.valid_int(season_number, 0, 32767) OR NOT etl.valid_int(episode_number, 0, 32767) THEN 'invalid_episode_number'
    ELSE NULL END AS reject_reason
FROM staging.title_episode s;
INSERT INTO etl.rejects
SELECT 'title_episode', tconst, reject_reason, to_jsonb(v) - 'reject_reason'
FROM v_episode v WHERE reject_reason IS NOT NULL;
INSERT INTO core.title_episode
SELECT tconst, parent_tconst, etl.clean(season_number)::SMALLINT,
       etl.clean(episode_number)::SMALLINT
FROM v_episode WHERE reject_reason IS NULL;

CREATE TEMP VIEW v_aka AS
SELECT s.*, CASE
    WHEN NOT EXISTS (SELECT 1 FROM core.title t WHERE t.tconst=s.title_id) THEN 'missing_title'
    WHEN etl.clean(ordering) IS NULL OR NOT etl.valid_int(ordering, 1, 32767) THEN 'invalid_ordering'
    WHEN etl.clean(title) IS NULL THEN 'missing_title_text'
    WHEN length(etl.clean(region)) > 10 OR length(etl.clean(language)) > 10 THEN 'invalid_region_or_language'
    WHEN etl.clean(is_original_title) IS NOT NULL AND is_original_title NOT IN ('0','1') THEN 'invalid_is_original_title'
    ELSE NULL END AS reject_reason
FROM staging.title_akas s;
INSERT INTO etl.rejects
SELECT 'title_akas', concat_ws(':', title_id, ordering), reject_reason, to_jsonb(v) - 'reject_reason'
FROM v_aka v WHERE reject_reason IS NOT NULL;
INSERT INTO core.title_aka
SELECT title_id, ordering::SMALLINT, title, etl.clean(region), etl.clean(language),
       etl.clean(types), etl.clean(attributes),
       CASE WHEN etl.clean(is_original_title) IS NULL THEN NULL ELSE is_original_title='1' END
FROM v_aka WHERE reject_reason IS NULL;

CREATE TEMP VIEW v_principal AS
SELECT s.*, CASE
    WHEN NOT EXISTS (SELECT 1 FROM core.title t WHERE t.tconst = s.tconst) THEN 'missing_title'
    WHEN NOT EXISTS (SELECT 1 FROM core.person p WHERE p.nconst = s.nconst) THEN 'missing_person'
    WHEN etl.clean(ordering) IS NULL OR NOT etl.valid_int(ordering, 1, 32767) THEN 'invalid_ordering'
    WHEN COALESCE(category IN ('actor','actress','archive_footage','archive_sound','casting_director','cinematographer','composer','director','editor','producer','production_designer','self','writer'), FALSE) = FALSE THEN 'unknown_category'
    WHEN NOT etl.valid_characters(characters) THEN 'invalid_characters_json'
    ELSE NULL END AS reject_reason
FROM staging.title_principals s;
INSERT INTO etl.rejects
SELECT 'title_principals', concat_ws(':', tconst, ordering), reject_reason, to_jsonb(v) - 'reject_reason'
FROM v_principal v WHERE reject_reason IS NOT NULL;
INSERT INTO core.title_principal
SELECT tconst, ordering::SMALLINT, nconst, category, etl.clean(job), etl.clean(characters)::JSONB
FROM v_principal WHERE reject_reason IS NULL;
INSERT INTO etl.rejects
SELECT 'title_crew', s.tconst, 'missing_title', to_jsonb(s)
FROM staging.title_crew s
WHERE NOT EXISTS (SELECT 1 FROM core.title t WHERE t.tconst=s.tconst);
CREATE TEMP VIEW v_director AS
SELECT s.tconst, btrim(x.token) AS nconst
FROM staging.title_crew s JOIN core.title t USING (tconst)
CROSS JOIN LATERAL unnest(string_to_array(etl.clean(s.directors), ',')) x(token);
INSERT INTO etl.rejects
SELECT 'title_crew.directors', concat_ws(':',v.tconst,v.nconst), 'missing_or_invalid_person', to_jsonb(v)
FROM v_director v WHERE NOT EXISTS (SELECT 1 FROM core.person p WHERE p.nconst=v.nconst);
INSERT INTO core.title_director
SELECT DISTINCT v.tconst, v.nconst FROM v_director v JOIN core.person p USING (nconst);
CREATE TEMP VIEW v_writer AS
SELECT s.tconst, btrim(x.token) AS nconst
FROM staging.title_crew s JOIN core.title t USING (tconst)
CROSS JOIN LATERAL unnest(string_to_array(etl.clean(s.writers), ',')) x(token);
INSERT INTO etl.rejects
SELECT 'title_crew.writers', concat_ws(':',v.tconst,v.nconst), 'missing_or_invalid_person', to_jsonb(v)
FROM v_writer v WHERE NOT EXISTS (SELECT 1 FROM core.person p WHERE p.nconst=v.nconst);
INSERT INTO core.title_writer
SELECT DISTINCT v.tconst, v.nconst FROM v_writer v JOIN core.person p USING (nconst);
CREATE TEMP VIEW v_known_for AS
SELECT s.nconst, btrim(x.token) AS tconst
FROM staging.name_basics s JOIN core.person p USING (nconst)
CROSS JOIN LATERAL unnest(string_to_array(etl.clean(s.known_for_titles), ',')) x(token);
INSERT INTO etl.rejects
SELECT 'name_basics.known_for_titles', concat_ws(':',v.nconst,v.tconst), 'missing_or_invalid_title', to_jsonb(v)
FROM v_known_for v WHERE NOT EXISTS (SELECT 1 FROM core.title t WHERE t.tconst=v.tconst);
INSERT INTO core.person_known_for
SELECT DISTINCT v.nconst, v.tconst FROM v_known_for v JOIN core.title t USING (tconst);
INSERT INTO etl.load_summary(table_name, row_count) SELECT 'staging.title_basics', COUNT(*) FROM staging.title_basics;
INSERT INTO etl.load_summary(table_name, row_count) SELECT 'staging.name_basics', COUNT(*) FROM staging.name_basics;
INSERT INTO etl.load_summary(table_name, row_count) SELECT 'staging.title_crew', COUNT(*) FROM staging.title_crew;
INSERT INTO etl.load_summary(table_name, row_count) SELECT 'staging.title_episode', COUNT(*) FROM staging.title_episode;
INSERT INTO etl.load_summary(table_name, row_count) SELECT 'staging.title_ratings', COUNT(*) FROM staging.title_ratings;
INSERT INTO etl.load_summary(table_name, row_count) SELECT 'staging.title_principals', COUNT(*) FROM staging.title_principals;
INSERT INTO etl.load_summary(table_name, row_count) SELECT 'staging.title_akas', COUNT(*) FROM staging.title_akas;
INSERT INTO etl.load_summary(table_name, row_count) SELECT 'core.title', COUNT(*) FROM core.title;
INSERT INTO etl.load_summary(table_name, row_count) SELECT 'core.person', COUNT(*) FROM core.person;
INSERT INTO etl.load_summary(table_name, row_count) SELECT 'core.genre', COUNT(*) FROM core.genre;
INSERT INTO etl.load_summary(table_name, row_count) SELECT 'core.profession', COUNT(*) FROM core.profession;
INSERT INTO etl.load_summary(table_name, row_count) SELECT 'core.title_rating', COUNT(*) FROM core.title_rating;
INSERT INTO etl.load_summary(table_name, row_count) SELECT 'core.title_episode', COUNT(*) FROM core.title_episode;
INSERT INTO etl.load_summary(table_name, row_count) SELECT 'core.title_aka', COUNT(*) FROM core.title_aka;
INSERT INTO etl.load_summary(table_name, row_count) SELECT 'core.title_genre', COUNT(*) FROM core.title_genre;
INSERT INTO etl.load_summary(table_name, row_count) SELECT 'core.title_director', COUNT(*) FROM core.title_director;
INSERT INTO etl.load_summary(table_name, row_count) SELECT 'core.title_writer', COUNT(*) FROM core.title_writer;
INSERT INTO etl.load_summary(table_name, row_count) SELECT 'core.title_principal', COUNT(*) FROM core.title_principal;
INSERT INTO etl.load_summary(table_name, row_count) SELECT 'core.person_profession', COUNT(*) FROM core.person_profession;
INSERT INTO etl.load_summary(table_name, row_count) SELECT 'core.person_known_for', COUNT(*) FROM core.person_known_for;
INSERT INTO etl.load_summary(table_name, row_count) SELECT 'etl.rejects', COUNT(*) FROM etl.rejects;
DROP VIEW v_title, v_person, v_genre_tokens, v_profession_tokens, v_rating, v_episode, v_aka, v_principal, v_director, v_writer, v_known_for;
COMMIT;
ANALYZE core.title;
ANALYZE core.person;
ANALYZE core.title_rating;
ANALYZE core.title_episode;
ANALYZE core.title_principal;
