// PostgreSQL compiled to WebAssembly, for SQL correctness checks without a server.
// This is not a full-data PostgreSQL performance or psql/COPY integration test.
import { PGlite } from '@electric-sql/pglite';
import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';

const db = new PGlite();
const sql = async path => readFile(new URL('../' + path, import.meta.url), 'utf8');
const run = async path => db.exec(await sql(path));
try {
  const version = (await db.query('SELECT version()')).rows[0].version;
  console.log(version);
  await db.exec('CREATE TEMP TABLE copy_probe (id TEXT, title TEXT, characters TEXT)');
  const raw = 'id\ttitle\tcharacters\ntt1\t"Quoted title"\t["A", "B"]\ntt2\tNA\t\\N\n';
  await db.exec(String.raw`COPY copy_probe FROM '/dev/blob' WITH (FORMAT csv, DELIMITER E'\t', HEADER true, NULL '\N', QUOTE E'\b', ENCODING 'UTF8')`, {blob: new Blob([raw])});
  assert.deepEqual((await db.query('SELECT * FROM copy_probe ORDER BY id')).rows, [
    {id:'tt1', title:'"Quoted title"', characters:'["A", "B"]'},
    {id:'tt2', title:'NA', characters:null}
  ]);
  console.log('PASS PostgreSQL COPY parser preserves quotes/JSON/NA and converts null sentinel');
  for (const path of ['sql/02_staging.sql', 'sql/01_schema.sql', 'tests/fixture.sql',
    'sql/03_transform.sql', 'sql/04_reporting_views.sql', 'sql/05_validate.sql', 'tests/assertions.sql']) {
    await run(path);
    console.log('PASS ' + path);
  }
  const before = (await db.query('SELECT table_name,row_count FROM etl.load_summary ORDER BY table_name')).rows;
  await run('sql/03_transform.sql');
  await run('sql/05_validate.sql');
  await run('tests/assertions.sql');
  assert.deepEqual((await db.query('SELECT table_name,row_count FROM etl.load_summary ORDER BY table_name')).rows, before);
  console.log('PASS repeated refresh: identical table counts and asserted values');
  for (const path of ['content', 'people', 'ratings', 'series']) {
    const results = await run('sql/analysis/' + path + '.sql');
    if (path === 'series') {
      const seasons = results.find(r => r.fields.some(f => f.name === 'avg_season_rating')).rows;
      const seasonOne = seasons.filter(r => r.season_number === 1);
      assert.equal(seasonOne.length, 2);
      assert.deepEqual(seasonOne.map(r => Number(r.avg_season_rating)).sort((a,b) => a-b), [2,10]);
    }
    if (path === 'people') {
      const actors = results.find(r => r.fields.some(f => f.name === 'movie_credits')).rows;
      assert.equal(Number(actors[0].movie_credits), 5);
      assert.equal(Number(actors[0].mean_eligible_movie_rating), 6);
    }
    if (path === 'ratings') {
      const correlations = results.find(r => r.fields.some(f => f.name === 'votes_rating_correlation')).rows;
      assert.ok(Math.abs(correlations.find(r => r.title_type === 'movie').votes_rating_correlation - 1) < 1e-10);
    }
    console.log('PASS analysis/' + path + '.sql');
  }
  // Duplicate valid primary keys are ambiguous: fail and preserve the prior core.
  await db.exec("INSERT INTO staging.title_basics SELECT * FROM staging.title_basics WHERE tconst='tt1'");
  await assert.rejects(run('sql/03_transform.sql'), /duplicate key/);
  await db.exec('ROLLBACK');
  await run('tests/assertions.sql');
  console.log('PASS duplicate key aborts refresh and restores previous core');
  await db.exec('TRUNCATE staging.title_akas');
  await assert.rejects(run('sql/03_transform.sql'), /All seven staging tables/);
  await db.exec('ROLLBACK');
  await run('tests/assertions.sql');
  console.log('PASS missing input aborts refresh and preserves previous core');
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
} finally {
  await db.close();
}
