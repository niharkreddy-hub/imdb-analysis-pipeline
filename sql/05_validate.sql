-- Run after transformation. A failed reconciliation raises an error.
-- Rejected rows remain an explicit review task even when all checks pass.
DO $$
DECLARE pair RECORD; raw_count BIGINT; loaded_count BIGINT; rejected_count BIGINT;
BEGIN
    FOR pair IN SELECT * FROM (VALUES
        ('title_basics', 'title'), ('name_basics', 'person'),
        ('title_ratings', 'title_rating'), ('title_episode', 'title_episode'),
        ('title_akas', 'title_aka'), ('title_principals', 'title_principal')
    ) AS x(source_name, target_name) LOOP
        EXECUTE format('SELECT COUNT(*) FROM staging.%I', pair.source_name) INTO raw_count;
        EXECUTE format('SELECT COUNT(*) FROM core.%I', pair.target_name) INTO loaded_count;
        SELECT COUNT(*) INTO rejected_count FROM etl.rejects WHERE source_table=pair.source_name;
        IF raw_count <> loaded_count + rejected_count THEN
            RAISE EXCEPTION 'Reconciliation failed for %: source %, loaded %, rejected %',
                pair.source_name, raw_count, loaded_count, rejected_count;
        END IF;
    END LOOP;
    IF EXISTS (SELECT 1 FROM pg_constraint c JOIN pg_namespace n ON n.oid=c.connamespace
               WHERE n.nspname='core' AND NOT c.convalidated) THEN
        RAISE EXCEPTION 'Unvalidated core constraint';
    END IF;
END $$;

SELECT table_name, row_count, loaded_at FROM etl.load_summary ORDER BY table_name;
SELECT source_table, reason, COUNT(*) AS rejected_rows_or_tokens
FROM etl.rejects GROUP BY source_table, reason ORDER BY source_table, reason;
-- Token rejections and source-row rejections have different units; do not sum as lost titles.
