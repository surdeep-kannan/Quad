// Shared Postgres connection for the tools. Uses SUPABASE_DB_URL when set,
// otherwise finds the project's connection pooler from SUPABASE_URL and
// SUPABASE_DB_PASSWORD.

import pg from 'pg';

const REGIONS = [
  'ap-south-1', 'ap-southeast-1', 'ap-southeast-2', 'ap-northeast-1', 'ap-northeast-2',
  'us-east-1', 'us-east-2', 'us-west-1', 'us-west-2', 'ca-central-1', 'sa-east-1',
  'eu-central-1', 'eu-central-2', 'eu-west-1', 'eu-west-2', 'eu-west-3', 'eu-north-1',
];

function projectRef() {
  const url = process.env.SUPABASE_URL ?? '';
  const match = url.match(/^https:\/\/([a-z0-9]+)\.supabase\.co/);
  if (!match) throw new Error('Set SUPABASE_URL in .env (https://<ref>.supabase.co)');
  return match[1];
}

async function tryConnect(config) {
  const client = new pg.Client({ ...config, ssl: { rejectUnauthorized: false }, connectionTimeoutMillis: 8000 });
  try {
    await client.connect();
    return client;
  } catch (error) {
    await client.end().catch(() => {});
    return { error };
  }
}

export async function connect() {
  if (process.env.SUPABASE_DB_URL) {
    const client = await tryConnect({ connectionString: process.env.SUPABASE_DB_URL });
    if (client.error) throw client.error;
    return client;
  }

  const ref = projectRef();
  const password = process.env.SUPABASE_DB_PASSWORD;
  if (!password) throw new Error('Set SUPABASE_DB_PASSWORD in .env');

  // Direct connection (IPv6 on most networks), then the session poolers.
  const candidates = [
    { host: `db.${ref}.supabase.co`, port: 5432, user: 'postgres' },
    ...['aws-0', 'aws-1'].flatMap((prefix) =>
      REGIONS.map((region) => ({ host: `${prefix}-${region}.pooler.supabase.com`, port: 5432, user: `postgres.${ref}` })),
    ),
  ];

  let lastError;
  for (const candidate of candidates) {
    const client = await tryConnect({ ...candidate, password, database: 'postgres' });
    if (!client.error) {
      console.log(`Connected via ${candidate.host}`);
      return client;
    }
    lastError = client.error;
    const message = String(client.error.message);
    // Wrong password is final; other errors mean "try the next host".
    if (message.includes('password authentication failed')) throw client.error;
  }
  throw new Error(`Couldn't reach the database. Set SUPABASE_DB_URL in .env. Last error: ${lastError?.message}`);
}
