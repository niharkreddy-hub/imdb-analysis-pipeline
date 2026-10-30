DO $$
BEGIN
    IF (SELECT COUNT(*) FROM core.title) <> 13 THEN RAISE EXCEPTION 'title cleaning failed'; END IF;
    IF (SELECT COUNT(*) FROM reporting.titles) <> 13 OR (SELECT COUNT(average_rating) FROM reporting.titles) <> 12 THEN RAISE EXCEPTION 'unrated title coverage failed'; END IF;
    IF (SELECT COUNT(*) FROM core.person) <> 3 THEN RAISE EXCEPTION 'person cleaning failed'; END IF;
    IF (SELECT COUNT(*) FROM core.title_genre WHERE tconst='tt1') <> 2 THEN RAISE EXCEPTION 'genre deduplication failed'; END IF;
    IF (SELECT COUNT(*) FROM core.title_director) <> 5 THEN RAISE EXCEPTION 'director normalization failed'; END IF;
    IF (SELECT COUNT(*) FROM core.title_writer) <> 5 THEN RAISE EXCEPTION 'writer normalization failed'; END IF;
    IF (SELECT COUNT(*) FROM core.person_profession) <> 4 THEN RAISE EXCEPTION 'profession normalization failed'; END IF;
    IF (SELECT COUNT(*) FROM core.person_known_for) <> 4 THEN RAISE EXCEPTION 'known-for resolution failed'; END IF;
    IF (SELECT COUNT(*) FROM core.title_rating) <> 12 THEN RAISE EXCEPTION 'rating checks failed'; END IF;
    IF (SELECT COUNT(*) FROM core.title_episode) <> 5 THEN RAISE EXCEPTION 'episode checks failed'; END IF;
    IF (SELECT COUNT(*) FROM core.title_principal) <> 7 THEN RAISE EXCEPTION 'principal JSON checks failed'; END IF;
    IF (SELECT COUNT(*) FROM reporting.actor_titles WHERE nconst='nm1') <> 5 THEN RAISE EXCEPTION 'actor grain failed'; END IF;
    IF (SELECT COUNT(*) FROM reporting.season_ratings WHERE season_number=1) <> 2 THEN RAISE EXCEPTION 'same-name series merged'; END IF;
    IF (SELECT mean_episode_rating FROM reporting.season_ratings WHERE series_id='tt100' AND season_number=1) <> 10 THEN RAISE EXCEPTION 'season mean incorrect'; END IF;
    IF EXISTS (SELECT 1 FROM reporting.season_ratings WHERE season_number=0) THEN RAISE EXCEPTION 'special included in regular seasons'; END IF;
    IF (SELECT COUNT(*) FROM reporting.aka_types) <> 2 THEN RAISE EXCEPTION 'aka separator failed'; END IF;
    IF (SELECT region FROM core.title_aka WHERE tconst='tt2') <> 'NA' THEN RAISE EXCEPTION 'literal NA lost'; END IF;
    IF (SELECT is_original_title FROM core.title_aka WHERE tconst='tt2') IS NOT NULL THEN RAISE EXCEPTION 'null sentinel failed'; END IF;
    IF (SELECT characters->>0 FROM core.title_principal WHERE tconst='tt1' AND ordering=7) <> 'Quote: "hello"' THEN RAISE EXCEPTION 'JSON quote preservation failed'; END IF;
    IF NOT EXISTS (SELECT 1 FROM etl.rejects WHERE source_table='title_crew.directors' AND reason='missing_or_invalid_person') THEN RAISE EXCEPTION 'missing reference not audited'; END IF;
END $$;
