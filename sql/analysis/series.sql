-- =============================================================================
-- Series Analysis
-- =============================================================================
-- Queries analyzing TV series: top-rated shows, season trends,
-- rating trajectories, and episode patterns.
-- =============================================================================

SET search_path TO core, public;


-- -----------------------------------------------------------------------------
-- Q1: Top 25 highest-rated TV series (min 10K votes)
-- The best TV shows according to IMDb users.
-- -----------------------------------------------------------------------------
SELECT
    t.primary_title,
    t.start_year,
    t.end_year,
    tr.average_rating,
    tr.num_votes
FROM title t
JOIN title_rating tr ON tr.tconst = t.tconst
WHERE t.title_type = 'tvSeries'
  AND tr.num_votes >= 10000
ORDER BY tr.average_rating DESC, tr.num_votes DESC
LIMIT 25;


-- -----------------------------------------------------------------------------
-- Q2: Series with most episodes (min 100 episodes)
-- The longest-running shows in IMDb.
-- -----------------------------------------------------------------------------
SELECT
    t.primary_title,
    t.start_year,
    t.end_year,
    COUNT(te.tconst)    AS total_episodes,
    COUNT(DISTINCT te.season_number) FILTER (WHERE te.season_number > 0) AS observed_regular_seasons
FROM title t
JOIN title_episode te ON te.parent_tconst = t.tconst
WHERE t.title_type IN ('tvSeries', 'tvMiniSeries')
GROUP BY t.tconst, t.primary_title, t.start_year, t.end_year
HAVING COUNT(te.tconst) >= 100
ORDER BY total_episodes DESC
LIMIT 25;


-- -----------------------------------------------------------------------------
-- Q3: Season-over-season rating trend for top series
-- How do ratings change across seasons?
-- Filters to well-known series with 50K+ votes on the series itself.
-- -----------------------------------------------------------------------------
WITH top_series AS (
    SELECT t.tconst, t.primary_title
    FROM title t
    JOIN title_rating tr ON tr.tconst = t.tconst
    WHERE t.title_type = 'tvSeries'
      AND tr.num_votes >= 50000
    ORDER BY tr.average_rating DESC, tr.num_votes DESC, t.tconst
    LIMIT 20
),
season_ratings AS (
    SELECT
        ts.tconst AS series_id,
        ts.primary_title,
        te.season_number,
        COUNT(te.tconst)                            AS rated_episodes,
        ROUND(AVG(tr.average_rating)::NUMERIC, 2)   AS avg_season_rating,
        SUM(tr.num_votes)                           AS season_votes
    FROM top_series ts
    JOIN title_episode te ON te.parent_tconst = ts.tconst
    JOIN title_rating tr ON tr.tconst = te.tconst
    WHERE te.season_number > 0
    GROUP BY ts.tconst, ts.primary_title, te.season_number
)
SELECT *
FROM season_ratings
ORDER BY primary_title, series_id, season_number;


-- -----------------------------------------------------------------------------
-- Q4: Top rated individual episodes across all series
-- The single best episodes in TV history according to IMDb voters.
-- Min 1000 votes to filter out niche episodes.
-- -----------------------------------------------------------------------------
SELECT
    parent.primary_title                        AS series,
    ep.primary_title                            AS episode,
    te.season_number,
    te.episode_number,
    tr.average_rating,
    tr.num_votes
FROM title_episode te
JOIN title ep ON ep.tconst = te.tconst
JOIN title parent ON parent.tconst = te.parent_tconst
JOIN title_rating tr ON tr.tconst = te.tconst
WHERE tr.num_votes >= 1000
ORDER BY tr.average_rating DESC, tr.num_votes DESC
LIMIT 25;


-- -----------------------------------------------------------------------------
-- Q5: Series rating decline/improvement metric
-- Which series improved or declined the most across their run?
-- Compares season 1 with the last observed rated regular season.
-- Episode ratings are equally weighted; this does not prove a completed series run.
-- Requires at least 3 observed rated regular seasons; season 0 is excluded.
-- -----------------------------------------------------------------------------
WITH season_avgs AS (
    SELECT
        te.parent_tconst,
        te.season_number,
        ROUND(AVG(tr.average_rating)::NUMERIC, 2) AS season_avg
    FROM title_episode te
    JOIN title_rating tr ON tr.tconst = te.tconst
    WHERE te.season_number > 0
    GROUP BY te.parent_tconst, te.season_number
),
series_trajectory AS (
    SELECT
        parent_tconst,
        COUNT(DISTINCT season_number)                               AS total_seasons,
        MAX(CASE WHEN season_number = 1 THEN season_avg END)       AS s1_rating,
        MAX(CASE WHEN season_number =
            (SELECT MAX(season_number) FROM season_avgs sa2
             WHERE sa2.parent_tconst = sa.parent_tconst)
            THEN season_avg END)                                    AS last_season_rating
    FROM season_avgs sa
    GROUP BY parent_tconst
    HAVING COUNT(DISTINCT season_number) >= 3
)
SELECT
    t.tconst AS series_id,
    t.primary_title,
    st.total_seasons,
    st.s1_rating,
    st.last_season_rating,
    ROUND((st.last_season_rating - st.s1_rating)::NUMERIC, 2) AS rating_change,
    CASE
        WHEN st.last_season_rating > st.s1_rating THEN 'Improved'
        WHEN st.last_season_rating < st.s1_rating THEN 'Declined'
        ELSE 'Stable'
    END AS trajectory
FROM series_trajectory st
JOIN title t ON t.tconst = st.parent_tconst
JOIN title_rating tr ON tr.tconst = st.parent_tconst
WHERE tr.num_votes >= 10000
  AND st.s1_rating IS NOT NULL
  AND st.last_season_rating IS NOT NULL
ORDER BY ABS(st.last_season_rating - st.s1_rating) DESC
LIMIT 30;
