// Runs every migration against an in-memory Postgres (PGlite) with minimal
// stand-ins for Supabase's auth, storage and realtime schemas, then exercises
// the schema as real signed-in students to check RLS, triggers and RPCs.
//
//   npm run db:check
//
// Nothing here touches a remote database.

import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { PGlite } from '@electric-sql/pglite';
import { pg_trgm } from '@electric-sql/pglite/contrib/pg_trgm';

const root = fileURLToPath(new URL('..', import.meta.url));
const migrationsDir = join(root, 'supabase', 'migrations');

const SUPABASE_STUBS = `
  create role anon nologin;
  create role authenticated nologin;
  create role service_role nologin bypassrls;
  create role supabase_auth_admin nologin;

  create schema auth;
  create table auth.users (
    id uuid primary key default gen_random_uuid(),
    email text,
    raw_user_meta_data jsonb default '{}'::jsonb,
    created_at timestamptz default now()
  );
  create function auth.uid() returns uuid language sql stable as $$
    select nullif(coalesce(
      nullif(current_setting('request.jwt.claim.sub', true), ''),
      (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
    ), '')::uuid
  $$;
  create function auth.role() returns text language sql stable as $$
    select nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'
  $$;

  create schema storage;
  create table storage.buckets (
    id text primary key, name text not null, owner uuid, public boolean default false,
    file_size_limit bigint, allowed_mime_types text[],
    created_at timestamptz default now(), updated_at timestamptz default now()
  );
  create table storage.objects (
    id uuid primary key default gen_random_uuid(), bucket_id text references storage.buckets (id),
    name text, owner uuid, metadata jsonb, created_at timestamptz default now()
  );
  alter table storage.objects enable row level security;
  create function storage.foldername(name text) returns text[] language plpgsql immutable as $$
    declare parts text[];
    begin
      parts := string_to_array(name, '/');
      return parts[1 : array_length(parts, 1) - 1];
    end
  $$;

  create schema realtime;
  create table realtime.messages (
    id bigserial primary key, topic text not null, extension text not null default 'broadcast',
    payload jsonb, event text, private boolean default true, inserted_at timestamptz default now()
  );
  alter table realtime.messages enable row level security;
  create function realtime.topic() returns text language sql stable as $$
    select nullif(current_setting('realtime.topic', true), '')
  $$;

  create schema extensions;
  grant usage on schema public, auth, storage, realtime, extensions to anon, authenticated, service_role;
  grant all on storage.objects to anon, authenticated, service_role;
  grant select, insert on realtime.messages to authenticated;
  alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
  alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
  alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
`;

let passed = 0;
const failures = [];

function check(name, condition, detail = '') {
  if (condition) {
    passed += 1;
  } else {
    failures.push(`${name}${detail ? ` (${detail})` : ''}`);
  }
}

async function main() {
  const db = new PGlite({ extensions: { pg_trgm } });
  await db.exec(SUPABASE_STUBS);
  try {
    await db.exec('create publication supabase_realtime;');
  } catch {
    // Not supported by this PGlite build; the migration skips it.
  }

  const files = readdirSync(migrationsDir).filter((f) => f.endsWith('.sql')).sort();
  for (const file of files) {
    try {
      await db.exec(readFileSync(join(migrationsDir, file), 'utf8'));
      console.log(`  applied ${file}`);
    } catch (error) {
      console.error(`\nFAILED in ${file}:\n  ${error.message}`);
      if (error.position) {
        const sql = readFileSync(join(migrationsDir, file), 'utf8');
        const pos = Number(error.position);
        console.error(`  near: ...${sql.slice(Math.max(0, pos - 160), pos + 80)}...`);
      }
      process.exit(1);
    }
  }
  await db.exec(readFileSync(join(root, 'supabase', 'seed.sql'), 'utf8'));
  console.log('  applied seed.sql\n');

  await runScenarios(db);

  console.log(`\n${passed} checks passed, ${failures.length} failed`);
  if (failures.length) {
    for (const failure of failures) console.log(`  ✗ ${failure}`);
    process.exit(1);
  }
}

// Runs `fn` as the given user (or as the database owner when user is null).
async function as(db, user, fn) {
  await db.exec('reset role');
  if (user) {
    await db.query(`select set_config('request.jwt.claims', $1, false)`, [
      JSON.stringify({ sub: user, role: 'authenticated' }),
    ]);
    await db.exec('set role authenticated');
  } else {
    await db.query(`select set_config('request.jwt.claims', '', false)`);
  }
  try {
    return await fn();
  } finally {
    await db.exec('reset role');
  }
}

async function rows(db, sql, params = []) {
  return (await db.query(sql, params)).rows;
}

async function one(db, sql, params = []) {
  return (await rows(db, sql, params))[0];
}

async function fails(db, sql, params = []) {
  try {
    await db.query(sql, params);
    return null;
  } catch (error) {
    return error.message;
  }
}

async function runScenarios(db) {
  // Users -------------------------------------------------------------------
  const users = {};
  for (const [key, name] of [['aarav', 'Aarav Mehta'], ['diya', 'Diya Nair'], ['kabir', 'Kabir Singh']]) {
    const row = await one(
      db,
      `insert into auth.users (email, raw_user_meta_data) values ($1, $2) returning id`,
      [`${key}@example.com`, JSON.stringify({ full_name: name })],
    );
    users[key] = row.id;
  }
  const { aarav, diya, kabir } = users;

  const profiles = await rows(db, 'select username, full_name from public.profiles order by full_name');
  check('profiles are created for new auth users', profiles.length === 3);
  check('usernames come from the email', profiles.some((p) => p.username === 'aarav'));

  const college = await one(db, `select id from public.colleges where slug = 'iit-madras'`);
  check('seed loaded colleges', Boolean(college));

  // Profiles ---------------------------------------------------------------
  await as(db, aarav, async () => {
    await db.query(
      `update public.profiles set college_id = $1, department = 'Computer Science', year_of_study = 3,
       interests = '{ai-ml,web-dev}', skills = '{flutter,python}', onboarded = true where id = $2`,
      [college.id, aarav],
    );
    check('students can make themselves admin: blocked',
      Boolean(await fails(db, `update public.profiles set role = 'admin' where id = $1`, [aarav])));
    const other = await db.query(`update public.profiles set bio = 'hacked' where id = $1`, [diya]);
    check('students cannot edit other profiles', other.affectedRows === 0);
    const available = await one(db, `select public.is_username_available('diya') as ok`);
    check('taken usernames are reported', available.ok === false);
  });

  await as(db, diya, async () => {
    await db.query(
      `update public.profiles set college_id = $1, interests = '{ai-ml,design}', onboarded = true where id = $2`,
      [college.id, diya],
    );
    await db.query(`insert into public.follows (follower_id, following_id) values ($1, $2)`, [diya, aarav]);
  });
  await as(db, kabir, async () => {
    await db.query(`update public.profiles set onboarded = true where id = $1`, [kabir]);
  });

  const aaravCounts = await one(db, `select followers_count from public.profiles where id = $1`, [aarav]);
  check('follow counters update', aaravCounts.followers_count === 1);

  // Communities ------------------------------------------------------------
  let communityId;
  await as(db, aarav, async () => {
    const created = await one(
      db,
      `insert into public.communities (slug, name, tagline, category, college_id, tags, created_by)
       values ('ml-club', 'ML Club', 'Models, papers and pizza', 'club', $1, '{ai-ml}', $2) returning id`,
      [college.id, aarav],
    );
    communityId = created.id;
    const membership = await one(db, `select my_role from public.community_details where id = $1`, [communityId]);
    check('creator becomes owner', membership?.my_role === 'owner');
  });

  const owner = await one(db,
    `select role, status from public.community_members where community_id = $1 and user_id = $2`, [communityId, aarav]);
  check('owner membership exists', owner && owner.role === 'owner' && owner.status === 'active');
  const general = await one(db, `select id, conversation_id from public.rooms where community_id = $1`, [communityId]);
  check('default #general room is created', Boolean(general));

  await as(db, diya, async () => {
    const status = await one(db, `select public.join_community($1) as status`, [communityId]);
    check('joining a public community is instant', status.status === 'active');
    const roomMember = await one(db, `select public.room_details.is_member from public.room_details where id = $1`, [general.id]);
    check('joining adds you to the community rooms', roomMember && roomMember.is_member === true);
    check('members cannot give themselves roles',
      Boolean(await fails(db,
        `select public.set_member_roles($1, $2, array[(select id from public.community_roles where community_id = $1 and name = 'Admin')])`,
        [communityId, diya])));
  });

  const count = await one(db, `select members_count from public.communities where id = $1`, [communityId]);
  check('member count tracks joins', count.members_count === 2);

  // Private community ------------------------------------------------------
  let privateId;
  await as(db, kabir, async () => {
    const created = await one(
      db,
      `insert into public.communities (slug, name, visibility, created_by) values ('secret-lab', 'Secret Lab', 'private', $1) returning id`,
      [kabir],
    );
    privateId = created.id;
    await db.query(`select public.create_post('text', $1, null, 'members only notes')`, [privateId]);
  });
  await as(db, diya, async () => {
    const status = await one(db, `select public.join_community($1) as status`, [privateId]);
    check('joining a private community creates a request', status.status === 'pending');
    const visible = await rows(db, `select id from public.posts where community_id = $1`, [privateId]);
    check('pending members cannot read private posts', visible.length === 0);
  });
  const joinRequest = await one(db,
    `select count(*)::int as n from public.notifications where user_id = $1 and type = 'community_join_request'`, [kabir]);
  check('moderators are notified of join requests', joinRequest.n === 1);
  await as(db, kabir, async () => {
    await db.query(`select public.set_member_status($1, $2, 'active')`, [privateId, diya]);
  });
  await as(db, diya, async () => {
    const visible = await rows(db, `select id from public.posts where community_id = $1`, [privateId]);
    check('approved members read private posts', visible.length === 1);
  });

  // Posts, polls, reactions, comments --------------------------------------
  let textPost;
  let pollPost;
  await as(db, aarav, async () => {
    textPost = (await one(db,
      `select public.create_post('question', $1, 'Best resources for transformers?', 'Looking for papers @diya', '[]'::jsonb, '{ai-ml}') as id`,
      [communityId])).id;
    pollPost = (await one(db,
      `select public.create_post('poll', $1, 'Next meetup day?', null, '[]'::jsonb, '{}', null, array['Friday','Saturday','  ']) as id`,
      [communityId])).id;
    const options = await rows(db, `select label from public.poll_options where post_id = $1 order by position`, [pollPost]);
    check('blank poll options are dropped', options.length === 2);
    check('announcements need moderator rights: owner allowed',
      !(await fails(db, `select public.create_post('announcement', $1, 'Welcome!', 'Read the rules')`, [communityId])));
  });

  const mention = await one(db,
    `select count(*)::int as n from public.notifications where user_id = $1 and type = 'mention'`, [diya]);
  check('mentions notify the mentioned student', mention.n === 1);
  const announcement = await one(db,
    `select count(*)::int as n from public.notifications where user_id = $1 and type = 'announcement'`, [diya]);
  check('announcements notify members', announcement.n === 1);

  await as(db, diya, async () => {
    check('members cannot post announcements',
      Boolean(await fails(db, `select public.create_post('announcement', $1, 'Fake', 'x')`, [communityId])));
    check('students cannot post as someone else',
      Boolean(await fails(db, `insert into public.posts (author_id, type, body) values ($1, 'text', 'x')`, [aarav])));

    await db.query(`insert into public.post_reactions (post_id, kind) values ($1, 'fire')`, [textPost]);
    const options = await rows(db, `select id from public.poll_options where post_id = $1 order by position`, [pollPost]);
    await db.query(`select public.vote_poll($1, $2)`, [pollPost, options[0].id]);
    await db.query(`select public.vote_poll($1, $2)`, [pollPost, options[1].id]);
    const detail = await one(db, `select my_vote, poll_options from public.post_details where id = $1`, [pollPost]);
    check('changing a vote moves it', detail.my_vote === options[1].id
      && detail.poll_options.find((o) => o.id === options[0].id).votes === 0
      && detail.poll_options.find((o) => o.id === options[1].id).votes === 1);

    const comment = await one(db,
      `insert into public.comments (post_id, body) values ($1, 'Start with The Illustrated Transformer') returning id`, [textPost]);
    const reply = await one(db,
      `insert into public.comments (post_id, parent_id, body) values ($1, $2, 'and Karpathy''s videos') returning id, depth`,
      [textPost, comment.id]);
    check('replies are nested one level deeper', reply.depth === 1);
    await db.query(`insert into public.saved_posts (post_id) values ($1)`, [textPost]);
  });

  const reacted = await one(db, `select likes_count, reaction_counts, comments_count, saves_count from public.posts where id = $1`, [textPost]);
  check('reaction counters update', reacted.likes_count === 1 && reacted.reaction_counts.fire === 1);
  check('comment counters update', reacted.comments_count === 2);
  check('save counters update', reacted.saves_count === 1);

  const aaravNotifications = await rows(db,
    `select type from public.notifications where user_id = $1 order by created_at`, [aarav]);
  const types = aaravNotifications.map((n) => n.type);
  check('authors are notified of reactions and comments',
    types.includes('post_reaction') && types.includes('post_comment') && types.includes('follow'), types.join(','));

  await as(db, kabir, async () => {
    const saved = await rows(db, `select * from public.saved_posts`);
    check('saved posts are private', saved.length === 0);
  });

  // Feeds and search -------------------------------------------------------
  await as(db, diya, async () => {
    const forYou = await rows(db, `select id, type from public.home_feed('for_you', 20, 0)`);
    check('for you feed returns posts', forYou.length >= 3, `got ${forYou.length}`);
    const following = await rows(db, `select id from public.home_feed('following', 20, 0)`);
    check('following feed includes joined communities', following.some((p) => p.id === textPost));
    const campus = await rows(db, `select id from public.home_feed('campus', 20, 0)`);
    check('campus feed includes same-college posts', campus.some((p) => p.id === textPost));
    const feed = await rows(db, `select id from public.community_feed($1, 'hot', 20, 0)`, [communityId]);
    check('community feed works', feed.length >= 3);
    const people = await rows(db, `select username from public.search_profiles('aar')`);
    check('people search', people.some((p) => p.username === 'aarav'));
    const communities = await rows(db, `select slug from public.search_communities('ml')`);
    check('community search', communities.some((c) => c.slug === 'ml-club'));
    const posts = await rows(db, `select id from public.search_posts('transformers')`);
    check('post search', posts.some((p) => p.id === textPost));
    const colleges = await rows(db, `select slug from public.search_colleges('madras')`);
    check('college search', colleges.some((c) => c.slug === 'iit-madras'));
    const rooms = await rows(db, `select name from public.search_rooms('general')`);
    check('room search', rooms.length >= 1);
    const suggestedPeople = await rows(db, `select id from public.suggested_people(10)`);
    check('suggested people excludes people you follow', !suggestedPeople.some((p) => p.id === aarav));
    await rows(db, `select id from public.suggested_communities(10)`);
    await rows(db, `select id from public.reels_feed(10, 0)`);
  });

  // Events -----------------------------------------------------------------
  let eventId;
  await as(db, aarav, async () => {
    eventId = (await one(db,
      `insert into public.events (title, category, starts_at, mode, meeting_url, capacity, community_id)
       values ('Paper reading night', 'meetup', now() + interval '2 days', 'online', 'https://meet.example.com/x', 1, $1)
       returning id`, [communityId])).id;
  });
  await as(db, diya, async () => {
    const status = await one(db, `select public.register_for_event($1) as s`, [eventId]);
    check('first registration gets a seat', status.s === 'going');
    const link = await one(db, `select public.event_meeting_link($1) as url`, [eventId]);
    check('registered attendees get the meeting link', link.url === 'https://meet.example.com/x');
    check('meeting links are not directly selectable',
      Boolean(await fails(db, `select meeting_url from public.events where id = $1`, [eventId])));
  });
  await as(db, kabir, async () => {
    const status = await one(db, `select public.register_for_event($1) as s`, [eventId]);
    check('full events waitlist new registrations', status.s === 'waitlist');
    const link = await one(db, `select public.event_meeting_link($1) as url`, [eventId]);
    check('waitlisted people do not get the link', link.url === null);
  });
  await as(db, diya, async () => {
    await db.query(`select public.cancel_event_registration($1)`, [eventId]);
  });
  const promoted = await one(db,
    `select status from public.event_registrations where event_id = $1 and user_id = $2`, [eventId, kabir]);
  check('cancellations promote the waitlist', promoted.status === 'going');
  const promotedNote = await one(db,
    `select count(*)::int as n from public.notifications where user_id = $1 and type = 'event_waitlist_promoted'`, [kabir]);
  check('promoted attendees are notified', promotedNote.n === 1);
  await as(db, kabir, async () => {
    const details = await one(db, `select my_status, registrations_count, attendees_preview from public.event_details where id = $1`, [eventId]);
    check('event details show your status', details.my_status === 'going' && details.registrations_count === 1);
    check('students cannot register others',
      Boolean(await fails(db, `insert into public.event_registrations (event_id, user_id) values ($1, $2)`, [eventId, diya])));
  });
  await as(db, aarav, async () => {
    await db.query(`insert into public.event_updates (event_id, body) values ($1, 'Link goes live at 7')`, [eventId]);
    await db.query(`select public.create_post('event', $1, null, 'Join us', '[]'::jsonb, '{}', $2)`, [communityId, eventId]);
  });
  const update = await one(db,
    `select count(*)::int as n from public.notifications where user_id = $1 and type = 'event_update'`, [kabir]);
  check('event updates notify attendees', update.n === 1);

  // Chat -------------------------------------------------------------------
  let directId;
  await as(db, aarav, async () => {
    directId = (await one(db, `select public.get_or_create_direct_conversation($1) as id`, [diya])).id;
    const again = (await one(db, `select public.get_or_create_direct_conversation($1) as id`, [diya])).id;
    check('direct conversations are reused', directId === again);
    await db.query(`insert into public.messages (conversation_id, body) values ($1, 'hey, coming tonight?')`, [directId]);
    check('messages cannot be sent as system',
      Boolean(await fails(db, `insert into public.messages (conversation_id, kind, body) values ($1, 'system', 'x')`, [directId])));
  });
  await as(db, diya, async () => {
    const list = await rows(db, `select id, type, unread_count, other_user from public.my_conversations()`);
    const direct = list.find((c) => c.id === directId);
    check('chat list shows unread counts', direct && direct.unread_count === 1);
    check('direct chats include the other person', direct && direct.other_user.full_name === 'Aarav Mehta');
    const message = await one(db, `select id from public.messages where conversation_id = $1`, [directId]);
    const added = await one(db, `select public.toggle_message_reaction($1, '👍') as added`, [message.id]);
    check('message reactions toggle on', added.added === true);
    const mirrored = await one(db, `select reactions from public.messages where id = $1`, [message.id]);
    check('reactions are mirrored onto the message', Array.isArray(mirrored.reactions['👍']));
    const found = await rows(db, `select id from public.search_messages('tonight')`);
    check('message search', found.length === 1);
    await db.query(`update public.conversation_members set last_read_at = now() where conversation_id = $1 and user_id = $2`, [directId, diya]);
    const after = await rows(db, `select unread_count from public.my_conversations() where id = $1`, [directId]);
    check('reading clears unread', after[0].unread_count === 0);
  });
  await as(db, kabir, async () => {
    const peek = await rows(db, `select id from public.messages where conversation_id = $1`, [directId]);
    check('outsiders cannot read direct messages', peek.length === 0);
    check('outsiders cannot post into conversations',
      Boolean(await fails(db, `insert into public.messages (conversation_id, body) values ($1, 'hi')`, [directId])));
  });

  let groupId;
  await as(db, aarav, async () => {
    groupId = (await one(db, `select public.create_group_conversation('Hackathon squad', array[$1, $2]::uuid[]) as id`, [diya, kabir])).id;
    const members = await one(db, `select count(*)::int as n from public.conversation_members where conversation_id = $1`, [groupId]);
    check('groups include everyone added', members.n === 3);
  });
  await as(db, kabir, async () => {
    await db.query(`select public.remove_conversation_member($1, $2)`, [groupId, kabir]);
    const left = await rows(db, `select id from public.my_conversations() where id = $1`, [groupId]);
    check('leaving a group removes it from your list', left.length === 0);
  });

  // Realtime channel authorization ---------------------------------------
  await as(db, diya, async () => {
    await db.query(`select set_config('realtime.topic', $1, false)`, [`chat:${directId}`]);
    const allowed = await one(db, `select private.can_use_topic(realtime.topic()) as ok`);
    check('members can join their chat channel', allowed.ok === true);
  });
  await as(db, kabir, async () => {
    await db.query(`select set_config('realtime.topic', $1, false)`, [`chat:${directId}`]);
    const allowed = await one(db, `select private.can_use_topic(realtime.topic()) as ok`);
    check('outsiders cannot join chat channels', allowed.ok === false);
  });

  // Calls ------------------------------------------------------------------
  await as(db, aarav, async () => {
    const call = (await one(db, `select public.start_call($1, 'video') as id`, [directId])).id;
    const again = (await one(db, `select public.start_call($1, 'video') as id`, [directId])).id;
    check('an active call is reused', call === again);
    await db.query(`select public.update_call($1, 'missed')`, [call]);
  });
  const missed = await one(db,
    `select count(*)::int as n from public.notifications where user_id = $1 and type = 'missed_call'`, [diya]);
  check('missed calls notify the other person', missed.n === 1);

  // Blocking ---------------------------------------------------------------
  await as(db, diya, async () => {
    await db.query(`insert into public.blocks (blocker_id, blocked_id) values ($1, $2)`, [diya, aarav]);
  });
  await as(db, aarav, async () => {
    check('blocked people cannot message you',
      Boolean(await fails(db, `insert into public.messages (conversation_id, body) values ($1, 'hello?')`, [directId])));
    const hidden = await rows(db, `select id from public.profiles where id = $1`, [diya]);
    check('people who blocked you are hidden', hidden.length === 0);
  });
  const follows = await one(db, `select count(*)::int as n from public.follows where follower_id = $1 and following_id = $2`, [diya, aarav]);
  check('blocking removes follows', follows.n === 0);

  // Moderation -------------------------------------------------------------
  await as(db, kabir, async () => {
    const joined = await one(db, `select public.join_community($1) as s`, [communityId]);
    check('kabir joins', joined.s === 'active');
    await db.query(`select public.submit_report('post', $1, 'spam', 'looks like spam')`, [textPost]);
    await db.query(`select public.submit_report('post', $1, 'spam', 'twice')`, [textPost]);
    const mine = await rows(db, `select id from public.reports`);
    check('duplicate reports are ignored', mine.length === 1);
  });
  await as(db, aarav, async () => {
    const queue = await rows(db, `select id, snapshot from public.report_details where community_id = $1 and status = 'open'`, [communityId]);
    check('moderators see their report queue', queue.length === 1 && queue[0].snapshot.title);
    await db.query(`select public.moderate_content('post', $1, 'pin')`, [pollPost]);
    await db.query(`select public.resolve_report($1, 'dismissed', 'Legit question')`, [queue[0].id]);
  });
  const reportUpdate = await one(db,
    `select count(*)::int as n from public.notifications where user_id = $1 and type = 'report_update'`, [kabir]);
  check('reporters hear back', reportUpdate.n === 1);
  await as(db, kabir, async () => {
    check('members cannot moderate',
      Boolean(await fails(db, `select public.moderate_content('post', $1, 'remove')`, [textPost])));
  });

  // Spam protection --------------------------------------------------------
  await as(db, kabir, async () => {
    let error = null;
    for (let i = 0; i < 12 && !error; i += 1) {
      error = await fails(db, `select public.create_post('text', null, null, $1)`, [`post number ${i}`]);
    }
    check('posting is rate limited', Boolean(error && error.includes('too fast')), error ?? 'no error');
  });
  await as(db, diya, async () => {
    await db.query(`select public.create_post('text', null, null, 'gm campus')`);
    const error = await fails(db, `select public.create_post('text', null, null, 'gm campus')`);
    check('duplicate posts are rejected', Boolean(error && error.includes('already posted')), error ?? 'no error');
  });

  // Rankings ---------------------------------------------------------------
  await as(db, diya, async () => {
    const board = await rows(db, `select name, score, rank, pillar_scores from public.college_leaderboard(null, 5, 0)`);
    check('leaderboard ranks colleges with students first', board[0] && board[0].name.includes('Madras') && board[0].rank === 1,
      JSON.stringify(board[0]));
    const pillars = await rows(db, `select key, weight from public.ranking_pillars`);
    const total = pillars.reduce((sum, p) => sum + Number(p.weight), 0);
    check('ranking weights add up to 1', Math.abs(total - 1) < 1e-9, String(total));
  });

  // Notifications ----------------------------------------------------------
  await as(db, aarav, async () => {
    const list = await rows(db, `select type, actor from public.notification_details order by created_at desc`);
    check('notification details load', list.length > 0);
    await db.query(`select public.mark_all_notifications_read()`);
    const unread = await one(db, `select count(*)::int as n from public.notifications where read_at is null`);
    check('mark all read', unread.n === 0);
  });

  // Custom roles and permissions ---------------------------------------------
  const defaults = await rows(db, `select name from public.community_roles where community_id = $1 order by position desc`, [communityId]);
  check('communities get Admin and Moderator roles', defaults.map((r) => r.name).join(',') === 'Admin,Moderator');

  let eventTeam;
  await as(db, aarav, async () => {
    eventTeam = (await one(db, `select public.create_community_role($1, 'Event team', 6, array['manage_events']) as id`, [communityId])).id;
    await db.query(`select public.set_member_roles($1, $2, array[$3::uuid])`, [communityId, kabir, eventTeam]);
  });
  await as(db, kabir, async () => {
    const perms = await one(db, `select my_permissions, my_rank from public.community_details where id = $1`, [communityId]);
    check('role permissions reach the member', perms.my_permissions.includes('manage_events') && !perms.my_permissions.includes('manage_rooms'));
    check('a role with manage_events can host community events',
      !(await fails(db, `insert into public.events (title, starts_at, community_id) values ('Role test', now() + interval '1 day', $1)`, [communityId])));
    check('a role without manage_rooms cannot create rooms',
      Boolean(await fails(db, `select public.create_room($1, 'nope')`, [communityId])));
    check('a role without manage_roles cannot create roles',
      Boolean(await fails(db, `select public.create_community_role($1, 'Hacker', 0, array['manage_roles'])`, [communityId])));
    check('members cannot remove the owner',
      Boolean(await fails(db, `select public.remove_member($1, $2)`, [communityId, aarav])));
  });

  // A moderator with manage_roles can only manage roles below their rank.
  let modRoleId;
  await as(db, aarav, async () => {
    modRoleId = (await one(db, `select id from public.community_roles where community_id = $1 and name = 'Moderator'`, [communityId])).id;
    await db.query(`select public.update_community_role($1, 'Moderator', 4, array['manage_posts','manage_roles','manage_members'], 50)`, [modRoleId]);
    await db.query(`select public.set_member_roles($1, $2, array[$3::uuid])`, [communityId, diya, modRoleId]);
    check('owners cannot change their own roles', Boolean(await fails(db, `select public.set_member_roles($1, $2, '{}')`, [communityId, aarav])));
  });
  await as(db, diya, async () => {
    check('moderators cannot edit roles at their rank',
      Boolean(await fails(db, `select public.update_community_role($1, 'Mods', 4, array['manage_posts'], 50)`, [modRoleId])));
    check('moderators cannot grant permissions they lack',
      Boolean(await fails(db, `select public.create_community_role($1, 'Bans', 1, array['ban_members'])`, [communityId])));
    const own = await one(db, `select public.create_community_role($1, 'Helpers', 3, array['manage_posts']) as id`, [communityId]);
    check('moderators can create lower roles', Boolean(own.id));
    check('moderators can assign lower roles to lower members',
      !(await fails(db, `select public.set_member_roles($1, $2, array[$3::uuid, $4::uuid])`, [communityId, kabir, eventTeam, own.id])));
    check('moderators cannot assign roles at their rank',
      Boolean(await fails(db, `select public.set_member_roles($1, $2, array[$3::uuid])`, [communityId, kabir, modRoleId])));
  });
  const kabirRoles = await rows(db, `select r.name from public.community_member_roles mr join public.community_roles r on r.id = mr.role_id where mr.user_id = $1 and mr.community_id = $2 order by r.name`, [kabir, communityId]);
  check('members can hold several roles', kabirRoles.map((r) => r.name).join(',') === 'Event team,Helpers');
  const roleNote = await one(db, `select count(*)::int as n from public.notifications where user_id = $1 and type = 'community_role'`, [kabir]);
  check('people are notified when given a role', roleNote.n >= 1);

  // Private profiles and anonymity ---------------------------------------------
  // Kabir hit the posting rate limit above; age those posts.
  await db.query(`update public.posts set created_at = now() - interval '2 hours' where author_id = $1`, [kabir]);
  await as(db, kabir, async () => {
    await db.query(`update public.profiles set is_private = true, bio = 'secret bio' where id = $1`, [kabir]);
  });
  let anonPost;
  await as(db, kabir, async () => {
    anonPost = (await one(db, `select public.create_post('text', $1, null, 'an honest question about placements')`, [communityId])).create_post;
    const mine = await one(db, `select author_id, author, is_mine, is_anonymous from public.post_details where id = $1`, [anonPost]);
    check('authors still see their anonymous posts as theirs', mine.is_mine && mine.author_id === kabir && mine.is_anonymous);
  });
  await as(db, aarav, async () => {
    const seen = await one(db, `select author_id, author, is_mine from public.post_details where id = $1`, [anonPost]);
    check('private profiles post anonymously in communities',
      seen.author_id === null && /^anonymous_[a-z]+_[a-z]+_\d{3}$/.test(seen.author.full_name) && !seen.is_mine, JSON.stringify(seen.author));
    check('the author column cannot be read directly',
      Boolean(await fails(db, `select author_id from public.posts where id = $1`, [anonPost])));
    const c1 = await one(db, `insert into public.comments (post_id, body, is_anonymous) values ($1, 'anon one', true) returning id`, [anonPost]);
    const c2 = await one(db, `insert into public.comments (post_id, body, is_anonymous) values ($1, 'anon two', true) returning id`, [anonPost]);
    globalThis.anonComments = [c1.id, c2.id];
    const chosen = (await one(db,
      `select public.create_post('text', $1, null, 'asking this one anonymously', '[]'::jsonb, '{}', null, null, null, true) as id`,
      [communityId])).id;
    const own = await one(db, `select is_anonymous, is_mine from public.post_details where id = $1`, [chosen]);
    check('public profiles can choose to post anonymously', own.is_anonymous && own.is_mine);
    const profilePost = (await one(db,
      `select public.create_post('text', null, null, 'profile posts are never anonymous', '[]'::jsonb, '{}', null, null, null, true) as id`)).id;
    const shown = await one(db, `select is_anonymous from public.post_details where id = $1`, [profilePost]);
    check('profile posts are never anonymous', shown.is_anonymous === false);
  });
  const aliases = await rows(db, `select anon_name from public.comments where id = any($1::uuid[])`, [globalThis.anonComments]);
  check('anonymous names change on every comment',
    aliases.length === 2 && aliases[0].anon_name && aliases[0].anon_name !== aliases[1].anon_name, JSON.stringify(aliases));
  await as(db, kabir, async () => {
    const seen = await rows(db, `select author_id, author from public.comment_details where id = any($1::uuid[])`, [globalThis.anonComments]);
    check('others see anonymous commenters only by alias', seen.length === 2 && seen.every((c) => c.author_id === null && c.author.is_anonymous));
  });
  const anonNote = await one(db,
    `select actor_id, data from public.notifications where user_id = $1 and type = 'post_comment' and post_id = $2 limit 1`, [kabir, anonPost]);
  check('notifications from anonymous comments hide the actor', anonNote && anonNote.actor_id === null && anonNote.data.alias);
  await as(db, aarav, async () => {
    const profile = await one(db, `select bio, can_see, is_private from public.profile_summaries where id = $1`, [kabir]);
    check('private profile details are hidden from people they do not follow', profile.bio === null && profile.can_see === false && profile.is_private);
  });
  await as(db, kabir, async () => {
    await db.query(`insert into public.follows (follower_id, following_id) values ($1, $2)`, [kabir, aarav]);
  });
  await as(db, aarav, async () => {
    const profile = await one(db, `select bio, can_see from public.profile_summaries where id = $1`, [kabir]);
    check('private profiles are visible to people they follow', profile.bio === 'secret bio' && profile.can_see);
  });

  // Anonymous room messages carry no sender at all.
  let anonMessage;
  await as(db, kabir, async () => {
    anonMessage = (await one(db,
      `insert into public.messages (conversation_id, sender_id, body) values ($1, $2, 'anonymous hello') returning id`,
      [general.conversation_id, kabir])).id;
  });
  const stored = await one(db, `select sender_id, anon_name, is_anonymous from public.messages where id = $1`, [anonMessage]);
  check('anonymous room messages store no sender', stored.sender_id === null && stored.is_anonymous && stored.anon_name);
  await as(db, aarav, async () => {
    const authors = await rows(db, `select * from public.message_authors where message_id = $1`, [anonMessage]);
    check('others cannot see who sent an anonymous message', authors.length === 0);
  });
  await as(db, kabir, async () => {
    const authors = await rows(db, `select * from public.message_authors where message_id = $1`, [anonMessage]);
    check('senders can find their anonymous messages', authors.length === 1);
    const unsent = await db.query(`update public.messages set deleted_at = now() where id = $1`, [anonMessage]);
    check('senders can unsend anonymous messages', unsent.affectedRows === 1);
  });

  // Reports on anonymous posts don't reveal the author to community moderators.
  await as(db, diya, async () => {
    await db.query(`select public.submit_report('post', $1, 'spam', 'anon report')`, [anonPost]);
  });
  await as(db, aarav, async () => {
    const report = await one(db, `select target_user, snapshot from public.report_details where target_id = $1`, [anonPost]);
    check('moderators do not see who wrote reported anonymous posts', report && report.target_user === null && report.snapshot.anonymous === true);
  });

  // Signed-out access ------------------------------------------------------
  await db.exec('reset role');
  await db.query(`select set_config('request.jwt.claims', '', false)`);
  await db.exec('set role anon');
  check('signed-out requests cannot call RPCs', Boolean(await fails(db, `select public.home_feed()`)));
  const anonPosts = await fails(db, `select id from public.posts`);
  check('signed-out requests see no posts', anonPosts !== null || (await rows(db, 'select id from public.posts')).length === 0);
  await db.exec('reset role');
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
