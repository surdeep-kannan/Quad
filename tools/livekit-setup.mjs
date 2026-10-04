// Stores the LiveKit URL, API key and API secret from the root .env in
// Supabase Vault, where `public.call_token()` reads them to sign call tokens.
// Run again after rotating the LiveKit key.
//
//   npm run livekit:setup

import { connect } from './db.mjs';

const secrets = {
  livekit_url: process.env.LIVEKIT_URL,
  livekit_api_key: process.env.LIVEKIT_API_KEY,
  livekit_api_secret: process.env.LIVEKIT_API_SECRET,
};

const missing = Object.entries(secrets).filter(([, value]) => !value).map(([name]) => name.toUpperCase());
if (missing.length) {
  console.error(`Missing in .env: ${missing.join(', ')}`);
  process.exit(1);
}

const client = await connect();
try {
  for (const [name, value] of Object.entries(secrets)) {
    const existing = await client.query('select id from vault.secrets where name = $1', [name]);
    if (existing.rows.length) {
      await client.query('select vault.update_secret($1, $2)', [existing.rows[0].id, value]);
      console.log(`updated ${name}`);
    } else {
      await client.query('select vault.create_secret($1, $2, $3)', [value, name, 'Used by public.call_token()']);
      console.log(`stored ${name}`);
    }
  }
} finally {
  await client.end();
}
