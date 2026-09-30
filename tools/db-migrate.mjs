// Applies supabase/migrations/*.sql (each once, in order) and supabase/seed.sql
// to the Supabase project in ../.env. Applied versions are recorded in
// supabase_migrations.schema_migrations, the same table the Supabase CLI uses.
//
//   npm run db:migrate

import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { connect } from './db.mjs';

const root = fileURLToPath(new URL('..', import.meta.url));
const migrationsDir = join(root, 'supabase', 'migrations');

const client = await connect();
try {
  await client.query(`
    create schema if not exists supabase_migrations;
    create table if not exists supabase_migrations.schema_migrations (
      version text primary key,
      statements text[],
      name text
    );
  `);
  const applied = new Set(
    (await client.query('select version from supabase_migrations.schema_migrations')).rows.map((r) => r.version),
  );

  const files = readdirSync(migrationsDir).filter((f) => f.endsWith('.sql')).sort();
  for (const file of files) {
    const [version, ...rest] = file.replace(/\.sql$/, '').split('_');
    if (applied.has(version)) {
      console.log(`  skip    ${file}`);
      continue;
    }
    const sql = readFileSync(join(migrationsDir, file), 'utf8');
    await client.query('begin');
    try {
      await client.query(sql);
      await client.query(
        'insert into supabase_migrations.schema_migrations (version, statements, name) values ($1, $2, $3)',
        [version, [sql], rest.join('_')],
      );
      await client.query('commit');
      console.log(`  applied ${file}`);
    } catch (error) {
      await client.query('rollback');
      console.error(`\nFailed in ${file}: ${error.message}`);
      process.exitCode = 1;
      break;
    }
  }

  if (!process.exitCode) {
    await client.query(readFileSync(join(root, 'supabase', 'seed.sql'), 'utf8'));
    const { rows } = await client.query('select count(*)::int as n from public.colleges');
    console.log(`  seeded  colleges (${rows[0].n} total)`);
    // Ask the Data API to pick up the new schema right away.
    await client.query(`notify pgrst, 'reload schema'`);
  }
} finally {
  await client.end();
}
