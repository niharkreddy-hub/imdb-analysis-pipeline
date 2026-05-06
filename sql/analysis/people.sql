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
-- Quality over quantity — directors with consistently excellent work.
-- Double threshold: enough titles to be meaningful, enough votes per title
-- to represent genuine audience reception.
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
-- The auteur directors — those who both write and direct their films.
-- -----------------------------------------------------------------------------
SELECT
    p.primary_name,
    COUNT(DISTINCT td.tconst)   AS directed,
    COUNT(DISTINCT tw.tconst)   AS written,
    COUNT(DISTINCT td.tconst) +
    COUNT(DISTINCT tw.tconst)   AS total_credits
FROM title_director td
JOIN title_writer tw ON tw.nconst = td.nconst
JOIN person p ON p.nconst = td.nconst
WHERE p.primary_name != '[UNKNOWN]'
GROUP BY p.nconst, p.primary_name
HAVING COUNT(DISTINCT td.tconst) >= 5
   AND COUNT(DISTINCT tw.tconst) >= 5
ORDER BY total_credits DESC
LIMIT 20;


-- -----------------------------------------------------------------------------
-- Q5: Profession distribution
-- What is the breakdown of professions across all IMDb persons?
-- -----------------------------------------------------------------------------
SELECT
    pr.profession_name,
    COUNT(DISTINCT pp.nconst)                           AS person_count,
    ROUND(100.0 * COUNT(DISTINCT pp.nconst) /
          SUM(COUNT(DISTINCT pp.nconst)) OVER (), 2)    AS pct
FROM person_profession pp
JOIN profession pr ON pr.profession_id = pp.profession_id
GROUP BY pr.profession_name
ORDER BY person_count DESC;