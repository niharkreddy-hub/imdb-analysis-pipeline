-- =============================================================================
-- Ratings Analysis
-- =============================================================================
-- Queries analyzing IMDb user ratings: distributions, correlations,
-- and the relationship between popularity (votes) and quality (rating).
-- =============================================================================

SET search_path TO core, public;


-- -----------------------------------------------------------------------------
-- Q1: Overall rating distribution
-- How are ratings distributed across all rated titles?
-- -----------------------------------------------------------------------------
SELECT
    FLOOR(average_rating)::INT  AS rating_floor,
    COUNT(*)                    AS title_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
FROM title_rating
GROUP BY rating_floor
ORDER BY rating_floor;


-- -----------------------------------------------------------------------------
-- Q2: Vote count bucketing — do more-voted titles rate higher?
-- Tests the hypothesis that popular titles earn higher ratings.
-- -----------------------------------------------------------------------------
SELECT
    CASE
        WHEN num_votes < 100      THEN '1. Under 100'
        WHEN num_votes < 1000     THEN '2. 100-999'
        WHEN num_votes < 10000    THEN '3. 1K-9.9K'
        WHEN num_votes < 100000   THEN '4. 10K-99.9K'
        WHEN num_votes < 1000000  THEN '5. 100K-999K'
        ELSE                           '6. 1M+'
    END                                         AS vote_bucket,
    COUNT(*)                                    AS titles,
    ROUND(AVG(average_rating)::NUMERIC, 2)      AS avg_rating,
    ROUND(STDDEV(average_rating)::NUMERIC, 2)   AS rating_stddev,
    MIN(num_votes)                              AS min_votes,
    MAX(num_votes)                              AS max_votes
FROM title_rating
GROUP BY vote_bucket
ORDER BY vote_bucket;


-- -----------------------------------------------------------------------------
-- Q3: Top 25 highest-rated movies (min 50,000 votes)
-- The IMDb "best movies" list. High vote threshold ensures
-- these are genuinely popular, not obscure cult films.
-- -----------------------------------------------------------------------------
SELECT
    t.primary_title,
    t.start_year,
    tr.average_rating,
    tr.num_votes
FROM title t
JOIN title_rating tr ON tr.tconst = t.tconst
WHERE t.title_type = 'movie'
  AND tr.num_votes >= 50000
ORDER BY tr.average_rating DESC, tr.num_votes DESC
LIMIT 25;


-- -----------------------------------------------------------------------------
-- Q4: Most-voted titles of all time
-- Popularity ranking — what has IMDb users engaged the most?
-- -----------------------------------------------------------------------------
SELECT
    t.primary_title,
    t.title_type,
    t.start_year,
    tr.average_rating,
    tr.num_votes
FROM title t
JOIN title_rating tr ON tr.tconst = t.tconst
ORDER BY tr.num_votes DESC
LIMIT 20;


-- -----------------------------------------------------------------------------
-- Q5: Rating by title type
-- Do movies, TV series, or other formats rate differently?
-- -----------------------------------------------------------------------------
SELECT
    t.title_type,
    COUNT(*)                                    AS rated_titles,
    ROUND(AVG(tr.average_rating)::NUMERIC, 2)   AS avg_rating,
    ROUND(STDDEV(tr.average_rating)::NUMERIC, 2) AS stddev,
    MIN(tr.average_rating)                      AS min_rating,
    MAX(tr.average_rating)                      AS max_rating
FROM title t
JOIN title_rating tr ON tr.tconst = t.tconst
GROUP BY t.title_type
ORDER BY avg_rating DESC;


-- -----------------------------------------------------------------------------
-- Q6: Weighted average rating vs simple average
-- IMDb uses a weighted formula. How does it compare to a simple mean?
-- This query computes both for comparison.
-- -----------------------------------------------------------------------------
SELECT
    ROUND(AVG(average_rating)::NUMERIC, 4)              AS simple_avg,
    ROUND(
        SUM(average_rating * num_votes)::NUMERIC /
        NULLIF(SUM(num_votes), 0), 4
    )                                                   AS weighted_avg,
    SUM(num_votes)                                      AS total_votes,
    COUNT(*)                                            AS total_rated_titles
FROM title_rating;