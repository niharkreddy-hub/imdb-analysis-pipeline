-- =============================================================================
-- Content Analysis
-- =============================================================================
-- Queries analyzing the distribution and characteristics of IMDb titles:
-- types, genres, runtimes, and production trends over time.
-- =============================================================================

SET search_path TO core, public;


-- -----------------------------------------------------------------------------
-- Q1: Distribution of title types
-- How is IMDb's catalog structured? What proportion is movies vs TV vs other?
-- -----------------------------------------------------------------------------
SELECT
    title_type,
    COUNT(*)                                            AS title_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM title
GROUP BY title_type
ORDER BY title_count DESC;


-- -----------------------------------------------------------------------------
-- Q2: Top 10 genres by title count
-- Which genres dominate IMDb's catalog?
-- -----------------------------------------------------------------------------
SELECT
    g.genre_name,
    COUNT(DISTINCT tg.tconst)                               AS title_count,
    ROUND(100.0 * COUNT(DISTINCT tg.tconst) /
          (SELECT COUNT(*) FROM title_genre), 2)            AS pct_of_genre_assignments
FROM title_genre tg
JOIN genre g USING (genre_id)
GROUP BY g.genre_name
ORDER BY title_count DESC
LIMIT 10;


-- -----------------------------------------------------------------------------
-- Q3: Genre popularity over decades
-- How has genre production shifted over time?
-- Filters to movies only with known start years.
-- -----------------------------------------------------------------------------
SELECT
    (t.start_year / 10) * 10                AS decade,
    g.genre_name,
    COUNT(*)                                AS title_count
FROM title t
JOIN title_genre tg ON tg.tconst = t.tconst
JOIN genre g ON g.genre_id = tg.genre_id
WHERE t.title_type = 'movie'
  AND t.start_year IS NOT NULL
  AND t.start_year >= 1920
  AND t.start_year < 2030
GROUP BY decade, g.genre_name
ORDER BY decade, title_count DESC;


-- -----------------------------------------------------------------------------
-- Q4: Runtime distribution for movies
-- What is the typical length of a movie?
-- Filters extreme outliers (>300 min) for meaningful distribution.
-- -----------------------------------------------------------------------------
SELECT
    CASE
        WHEN runtime_minutes < 30  THEN 'Under 30 min'
        WHEN runtime_minutes < 60  THEN '30-59 min'
        WHEN runtime_minutes < 90  THEN '60-89 min'
        WHEN runtime_minutes < 120 THEN '90-119 min'
        WHEN runtime_minutes < 150 THEN '120-149 min'
        WHEN runtime_minutes < 180 THEN '150-179 min'
        ELSE '180+ min'
    END                         AS runtime_bucket,
    COUNT(*)                    AS movie_count,
    ROUND(AVG(runtime_minutes)) AS avg_runtime
FROM title
WHERE title_type = 'movie'
  AND runtime_minutes IS NOT NULL
  AND runtime_minutes BETWEEN 1 AND 300
GROUP BY runtime_bucket
ORDER BY MIN(runtime_minutes);


-- -----------------------------------------------------------------------------
-- Q5: Annual movie title counts (fixed comparison period: 1994–2024)
-- How do IMDb movie title counts vary by start year? Catalog coverage is incomplete.
-- -----------------------------------------------------------------------------
SELECT
    start_year,
    COUNT(*) AS movie_title_count
FROM title
WHERE title_type = 'movie'
  AND start_year BETWEEN 1994 AND 2024
GROUP BY start_year
ORDER BY start_year;


-- -----------------------------------------------------------------------------
-- Q6: Average rating by genre (min 1000 rated titles per genre)
-- Which genres are rated highest by IMDb users?
-- Minimum threshold prevents small genres from dominating.
-- -----------------------------------------------------------------------------
SELECT
    g.genre_name,
    COUNT(DISTINCT tr.tconst)               AS rated_titles,
    ROUND(AVG(tr.average_rating)::NUMERIC, 2) AS avg_rating,
    ROUND(AVG(tr.num_votes)::NUMERIC)       AS avg_votes
FROM title_genre tg
JOIN genre g USING (genre_id)
JOIN title_rating tr ON tr.tconst = tg.tconst
GROUP BY g.genre_name
HAVING COUNT(DISTINCT tr.tconst) >= 1000
ORDER BY avg_rating DESC;
