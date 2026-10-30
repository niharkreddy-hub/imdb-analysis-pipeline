-- =============================================================================
-- Ratings Analysis
-- =============================================================================
-- Queries analyzing IMDb user ratings: distributions, correlations,
-- and the relationship between popularity (votes) and audience rating.
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
-- Describes an association; this query is not a statistical hypothesis test.
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
-- A project ranking using a declared 50K-vote threshold, not IMDb Top 250.
-- The threshold limits low-vote titles; it does not eliminate selection bias.
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
-- Compares a mean across title ratings with a vote-weighted mean across titles.
-- This does not reproduce IMDb’s internal per-title weighting algorithm.
-- -----------------------------------------------------------------------------
SELECT
    ROUND(AVG(average_rating)::NUMERIC, 4)              AS simple_avg,
    ROUND(
        SUM(average_rating * num_votes)::NUMERIC /
        NULLIF(SUM(num_votes), 0), 4
    )                                                   AS vote_weighted_title_rating,
    SUM(num_votes)                                      AS total_votes,
    COUNT(*)                                            AS total_rated_titles
FROM title_rating;

-- Q7: Lowest-rated movies using the same 50K-vote threshold as Q3.
SELECT t.tconst, t.primary_title, t.start_year, r.average_rating, r.num_votes
FROM title t JOIN title_rating r USING (tconst)
WHERE t.title_type = 'movie' AND r.num_votes >= 50000
ORDER BY r.average_rating, r.num_votes DESC, t.tconst
LIMIT 25;

-- Q8: Pearson correlation, stratified by title type.
-- Each title is one observation. Includes raw votes and ln(votes) for skew.
-- Null correlation means too few observations or zero variance. No causal claim.
SELECT t.title_type, COUNT(*) AS rated_titles,
       CORR(r.num_votes::DOUBLE PRECISION, r.average_rating::DOUBLE PRECISION) AS votes_rating_correlation,
       CORR(LN(r.num_votes::DOUBLE PRECISION), r.average_rating::DOUBLE PRECISION) AS log_votes_rating_correlation
FROM title t JOIN title_rating r USING (tconst)
WHERE r.num_votes > 0
GROUP BY t.title_type
ORDER BY rated_titles DESC;
