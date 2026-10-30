-- Reporting layer. Keep title-grain facts separate from many-to-many bridges.
CREATE SCHEMA IF NOT EXISTS reporting;

CREATE OR REPLACE VIEW reporting.titles AS
SELECT t.tconst, t.title_type, t.primary_title, t.original_title, t.is_adult,
       t.start_year, t.end_year, t.runtime_minutes,
       r.average_rating, r.num_votes,
       r.tconst IS NOT NULL AS is_rated,
       CASE WHEN r.num_votes > 0 THEN LN(r.num_votes::DOUBLE PRECISION) END AS log_votes,
       t.primary_title || ' [' || t.tconst || ']' AS title_label
FROM core.title t LEFT JOIN core.title_rating r USING (tconst);

CREATE OR REPLACE VIEW reporting.title_genres AS
SELECT tg.tconst, g.genre_name
FROM core.title_genre tg JOIN core.genre g USING (genre_id);

CREATE OR REPLACE VIEW reporting.people AS
SELECT nconst, primary_name, birth_year, death_year FROM core.person;

CREATE OR REPLACE VIEW reporting.actor_titles AS
SELECT DISTINCT nconst, tconst FROM core.title_principal
WHERE category IN ('actor', 'actress');

CREATE OR REPLACE VIEW reporting.episodes AS
SELECT e.tconst AS episode_id, e.parent_tconst AS series_id,
       parent.primary_title AS series_title,
       parent.primary_title || ' [' || parent.tconst || ']' AS series_label,
       parent.title_type AS series_type, parent.start_year AS series_start_year,
       ep.primary_title AS episode_title, e.season_number, e.episode_number,
       r.average_rating, r.num_votes
FROM core.title_episode e JOIN core.title ep ON ep.tconst=e.tconst
JOIN core.title parent ON parent.tconst=e.parent_tconst
LEFT JOIN core.title_rating r ON r.tconst=e.tconst;

-- Mean is across rated episodes, not across series and not vote weighted.
-- Excludes specials (season 0) and unknown seasons. Includes all observed seasons.
CREATE OR REPLACE VIEW reporting.season_ratings AS
SELECT series_id, series_title, series_label, series_type, series_start_year,
       season_number, COUNT(*) AS observed_episodes,
       COUNT(average_rating) AS rated_episodes,
       AVG(average_rating) AS mean_episode_rating,
       SUM(num_votes) AS episode_votes
FROM reporting.episodes
WHERE season_number > 0
GROUP BY series_id, series_title, series_label, series_type, series_start_year, season_number;

-- Alternate-title metadata stays lossless in core; expose atomic type tags here.
CREATE OR REPLACE VIEW reporting.aka_types AS
SELECT DISTINCT a.tconst, a.ordering, btrim(x.value) AS aka_type
FROM core.title_aka a
CROSS JOIN LATERAL unnest(string_to_array(a.types, chr(2))) x(value)
WHERE NULLIF(btrim(x.value), '') IS NOT NULL;
