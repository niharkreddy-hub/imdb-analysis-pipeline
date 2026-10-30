-- =============================================================================
-- People Analysis
-- =============================================================================
-- Queries analyzing directors, writers, and actors:
-- prolific creators, highest-rated work, career patterns.
-- Note: Requires core.title_principal to be fully loaded.
-- Queries marked [NO PRINCIPAL] work without title_principal.
-- =============================================================================

SET search_path TO core, public;


-- -----------------------------------------------------------------------------
-- Q1: Most prolific directors (min 10 titles) [NO PRINCIPAL]
-- Who has directed the most titles in IMDb?
-- Minimum threshold removes one-off directors.
-- -----------------------------------------------------------------------------
SELECT
    p.primary_name,
    COUNT(DISTINCT td.tconst)                   AS titles_directed,
    MIN(t.start_year)                           AS first_title,
    MAX(t.start_year)                           AS latest_title
FROM title_director td
JOIN person p ON p.nconst = td.nconst
JOIN title t ON t.tconst = td.tconst
WHERE p.primary_name != '[UNKNOWN]'
GROUP BY p.nconst, p.primary_name
HAVING COUNT(DISTINCT td.tconst) >= 10
ORDER BY titles_directed DESC
LIMIT 25;


-- -----------------------------------------------------------------------------
-- Q2: Highest-rated directors (min 5 rated movies, min 10K votes each) [NO PRINCIPAL]
-- Ranks mean ratings among eligible movies; audience ratings are not objective quality.
-- Double threshold: enough titles to be meaningful, enough votes per title
-- to reduce instability from very small vote counts; selection bias remains.
-- -----------------------------------------------------------------------------
SELECT
    p.primary_name,
    COUNT(DISTINCT td.tconst)                       AS movies_directed,
    ROUND(AVG(tr.average_rating)::NUMERIC, 2)       AS avg_rating,
    ROUND(STDDEV(tr.average_rating)::NUMERIC, 2)    AS rating_consistency,
    SUM(tr.num_votes)                               AS total_votes
FROM title_director td
JOIN person p ON p.nconst = td.nconst
JOIN title t ON t.tconst = td.tconst
JOIN title_rating tr ON tr.tconst = td.tconst
WHERE t.title_type = 'movie'
  AND tr.num_votes >= 10000
  AND p.primary_name != '[UNKNOWN]'
GROUP BY p.nconst, p.primary_name
HAVING COUNT(DISTINCT td.tconst) >= 5
ORDER BY avg_rating DESC, total_votes DESC
LIMIT 25;


-- -----------------------------------------------------------------------------
-- Q3: Most prolific writers (min 10 titles) [NO PRINCIPAL]
-- -----------------------------------------------------------------------------
SELECT
    p.primary_name,
    COUNT(DISTINCT tw.tconst)               AS titles_written,
    MIN(t.start_year)                       AS first_title,
    MAX(t.start_year)                       AS latest_title
FROM title_writer tw
JOIN person p ON p.nconst = tw.nconst
JOIN title t ON t.tconst = tw.tconst
WHERE p.primary_name != '[UNKNOWN]'
GROUP BY p.nconst, p.primary_name
HAVING COUNT(DISTINCT tw.tconst) >= 10
ORDER BY titles_written DESC
LIMIT 25;


-- -----------------------------------------------------------------------------
-- Q4: Person appearing as both director and writer [NO PRINCIPAL]
-- People with both roles across their credits; not necessarily on the same title.
-- -----------------------------------------------------------------------------
-- Aggregate each role first to avoid multiplying director and writer credits.
WITH directors AS (
    SELECT nconst, COUNT(*) AS directed FROM title_director GROUP BY nconst
), writers AS (
    SELECT nconst, COUNT(*) AS written FROM title_writer GROUP BY nconst
)
SELECT p.nconst, p.primary_name, d.directed, w.written,
       d.directed + w.written AS total_role_credits
FROM directors d JOIN writers w USING (nconst) JOIN person p USING (nconst)
WHERE d.directed >= 5 AND w.written >= 5
ORDER BY total_role_credits DESC, p.nconst
LIMIT 20;


-- -----------------------------------------------------------------------------
-- Q5: Profession distribution
-- What is the breakdown of professions across all IMDb persons?
-- -----------------------------------------------------------------------------
SELECT
    pr.profession_name,
    COUNT(DISTINCT pp.nconst)                           AS person_count,
    ROUND(100.0 * COUNT(DISTINCT pp.nconst) /
          SUM(COUNT(DISTINCT pp.nconst)) OVER (), 2)    AS pct_of_profession_assignments
FROM person_profession pp
JOIN profession pr ON pr.profession_id = pp.profession_id
GROUP BY pr.profession_name
ORDER BY person_count DESC;

-- Q6: Actors/actresses by distinct movie credits and mean eligible rating.
-- IMDb principals are selected credits, not a complete cast list.
-- One movie per person even if that person has multiple principal entries.
WITH actor_titles AS (
    SELECT DISTINCT nconst, tconst FROM title_principal
    WHERE category IN ('actor', 'actress')
)
SELECT p.nconst, p.primary_name, COUNT(*) AS movie_credits,
       COUNT(r.tconst) FILTER (WHERE r.num_votes >= 1000) AS eligible_rated_movies,
       ROUND(AVG(r.average_rating) FILTER (WHERE r.num_votes >= 1000), 2) AS mean_eligible_movie_rating
FROM actor_titles a JOIN person p USING (nconst)
JOIN title t USING (tconst) LEFT JOIN title_rating r USING (tconst)
WHERE t.title_type = 'movie'
GROUP BY p.nconst, p.primary_name
HAVING COUNT(*) >= 5
ORDER BY movie_credits DESC, p.nconst
LIMIT 25;
