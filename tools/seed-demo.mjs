// Fills the project with demo students, communities, posts, events, chats and
// reels so the app has something to show. Safe to re-run: it removes the
// previous demo data (every account on @demo.quadapp.dev) first.
//
//   npm run db:seed-demo
//
// Demo accounts all use the password in DEMO_PASSWORD below.

import { createClient } from '@supabase/supabase-js';
import { connect } from './db.mjs';

const DEMO_PASSWORD = 'QuadDemo@2026';
const DOMAIN = 'demo.quadapp.dev';

const people = [
  { key: 'aarav', name: 'Aarav Mehta', college: 'iit-madras', dept: 'Computer Science', year: 3, verified: true,
    bio: 'Building things that ship. Flutter, Rust and too much filter coffee.',
    interests: ['app-dev', 'open-source', 'startups', 'ai-ml'], skills: ['Flutter', 'Rust', 'Postgres', 'Figma'] },
  { key: 'diya', name: 'Diya Nair', college: 'iit-madras', dept: 'Engineering Design', year: 2, verified: true,
    bio: 'Product design + photography. Running Shutterbugs this sem.',
    interests: ['design', 'photography', 'startups'], skills: ['Figma', 'UI design', 'Lightroom'] },
  { key: 'kabir', name: 'Kabir Singh', college: 'nit-trichy', dept: 'Electronics', year: 4, verified: false,
    bio: 'Placement season survivor. Happy to review resumes.',
    interests: ['placements', 'competitive-programming', 'robotics'], skills: ['C++', 'DSA', 'Embedded C'] },
  { key: 'meera', name: 'Meera Iyer', college: 'iit-madras', dept: 'Data Science', year: 3, verified: false,
    bio: 'ML research intern. Reading papers so you don\'t have to.',
    interests: ['ai-ml', 'data-science', 'research'], skills: ['PyTorch', 'Python', 'SQL'] },
  { key: 'rohan', name: 'Rohan Das', college: 'bits-pilani', dept: 'Mechanical', year: 1, verified: false,
    bio: 'Fresher. Football, films and finding my people.',
    interests: ['sports', 'film', 'gaming'], skills: ['Blender', 'Video editing'] },
  { key: 'ananya', name: 'Ananya Rao', college: 'vit-vellore', dept: 'Information Technology', year: 2, verified: false,
    bio: 'Web dev and hackathons. 6 hackathons, 2 wins, 0 sleep.',
    interests: ['web-dev', 'cloud', 'startups', 'open-source'], skills: ['React', 'Node.js', 'AWS'] },
];

const admin = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SECRET_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const db = await connect();
const q = async (sql, params = []) => (await db.query(sql, params)).rows;
const one = async (sql, params = []) => (await q(sql, params))[0];

try {
  // Start clean -------------------------------------------------------------
  const old = await q(`select id from auth.users where email like $1`, [`%@${DOMAIN}`]);
  for (const { id } of old) await admin.auth.admin.deleteUser(id);
  if (old.length) console.log(`Removed ${old.length} old demo accounts`);

  // Accounts ------------------------------------------------------------------
  const ids = {};
  for (const p of people) {
    const { data, error } = await admin.auth.admin.createUser({
      email: `${p.key}@${DOMAIN}`,
      password: DEMO_PASSWORD,
      email_confirm: true,
      user_metadata: { full_name: p.name, username: p.key },
    });
    if (error) throw error;
    ids[p.key] = data.user.id;
    const college = await one(`select id from public.colleges where slug = $1`, [p.college]);
    await q(
      `update public.profiles set username = $2, college_id = $3, department = $4, year_of_study = $5, bio = $6,
         interests = $7, skills = $8, is_verified = $9, onboarded = true, last_seen_at = now() - interval '20 minutes'
       where id = $1`,
      [data.user.id, p.key, college.id, p.dept, p.year, p.bio, p.interests, p.skills, p.verified],
    );
  }
  console.log(`Created ${people.length} demo students`);

  const college = async (slug) => (await one(`select id from public.colleges where slug = $1`, [slug])).id;
  const iitm = await college('iit-madras');

  // Follows -------------------------------------------------------------------
  const follows = [
    ['diya', 'aarav'], ['aarav', 'diya'], ['meera', 'aarav'], ['kabir', 'aarav'], ['rohan', 'aarav'],
    ['aarav', 'meera'], ['ananya', 'aarav'], ['diya', 'meera'], ['rohan', 'kabir'], ['ananya', 'kabir'],
  ];
  for (const [a, b] of follows) {
    await q(`insert into public.follows (follower_id, following_id) values ($1, $2) on conflict do nothing`, [ids[a], ids[b]]);
  }

  // Communities ----------------------------------------------------------------
  const communityDefs = [
    { slug: 'iit-madras', name: 'IIT Madras', owner: 'aarav', category: 'college', college: iitm, color: 7,
      tagline: 'The unofficial campus square', tags: ['placements', 'startups'],
      description: 'Everything IIT Madras: notices, lost & found, mess reviews and events. Be kind, no spam.' },
    { slug: 'coding-club', name: 'Coding Club', owner: 'aarav', category: 'club', college: iitm, color: 4,
      tagline: 'Ship something every week', tags: ['app-dev', 'web-dev', 'open-source'],
      description: 'Weekly build nights, code reviews and open-source sprints. All levels welcome.' },
    { slug: 'hackathon-hub', name: 'Hackathon Hub', owner: 'ananya', category: 'hackathon', college: null, color: 0,
      tagline: 'Find a team. Win the weekend.', tags: ['startups', 'web-dev', 'ai-ml'],
      description: 'Upcoming hackathons across India, team-finding threads and winning project breakdowns.' },
    { slug: 'placement-prep', name: 'Placement Prep', owner: 'kabir', category: 'career', college: null, color: 11,
      tagline: 'Interview stories, resumes, referrals', tags: ['placements', 'competitive-programming'],
      description: 'Mock interviews, resume reviews and honest interview experiences from seniors.' },
    { slug: 'ml-and-ai', name: 'ML & AI', owner: 'meera', category: 'technical', college: null, color: 8,
      tagline: 'Papers, projects and GPU memes', tags: ['ai-ml', 'data-science', 'research'],
      description: 'Paper reading circles, project showcases and research opportunities.' },
    { slug: 'shutterbugs', name: 'Shutterbugs', owner: 'diya', category: 'hobby', college: iitm, color: 10,
      tagline: 'Campus through a lens', tags: ['photography', 'design', 'film'],
      description: 'Photo walks, edits and weekly themes. Phone photographers very welcome.' },
    { slug: 'campus-football', name: 'Campus Football', owner: 'rohan', category: 'sports', college: null, color: 3,
      tagline: '5-a-side every evening', tags: ['sports', 'fitness'],
      description: 'Pickup games, inter-hostel league updates and match highlights.' },
  ];
  const communities = {};
  for (const c of communityDefs) {
    const row = await one(
      `insert into public.communities (slug, name, tagline, description, category, college_id, color, tags, created_by, rules)
       values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) returning id`,
      [c.slug, c.name, c.tagline, c.description, c.category, c.college, c.color, c.tags, ids[c.owner],
        JSON.stringify([
          { title: 'Be kind', body: 'Critique ideas, not people.' },
          { title: 'No spam or self-promo dumps', body: 'Share your work with context.' },
          { title: 'Keep it relevant', body: `Posts should relate to ${c.name}.` },
        ])],
    );
    communities[c.slug] = row.id;
  }

  const memberships = {
    'iit-madras': ['diya', 'meera', 'kabir'],
    'coding-club': ['diya', 'meera', 'ananya', 'rohan'],
    'hackathon-hub': ['aarav', 'diya', 'kabir', 'meera'],
    'placement-prep': ['aarav', 'meera', 'rohan', 'ananya'],
    'ml-and-ai': ['aarav', 'kabir', 'ananya'],
    shutterbugs: ['aarav', 'meera', 'rohan'],
    'campus-football': ['aarav', 'kabir'],
  };
  for (const [slug, keys] of Object.entries(memberships)) {
    for (const key of keys) {
      await q(`insert into public.community_members (community_id, user_id) values ($1, $2) on conflict do nothing`,
        [communities[slug], ids[key]]);
    }
  }
  // Every community starts with Admin and Moderator roles.
  await q(`insert into public.community_member_roles (community_id, user_id, role_id)
           select $1, $2, id from public.community_roles where community_id = $1 and name = 'Moderator'`,
    [communities['coding-club'], ids.diya]);

  const rooms = [
    ['coding-club', 'coding-room', 'Pair up, debug, rubber-duck', 'coding'],
    ['coding-club', 'study-room', 'Quiet co-working. Cameras optional.', 'study'],
    ['placement-prep', 'placement-talk', 'Interview experiences and prep', 'placement'],
    ['hackathon-hub', 'find-a-team', 'Looking for teammates? Start here.', 'hackathon'],
    ['campus-football', 'gaming-room', 'FIFA nights and match chat', 'gaming'],
  ];
  const roomIds = {};
  for (const [slug, name, topic, kind] of rooms) {
    const row = await one(`select private.create_room_internal($1, $2, $3, $4, 1, null) as id`,
      [communities[slug], name, topic, kind]);
    roomIds[name] = row.id;
  }
  console.log(`Created ${communityDefs.length} communities with rooms`);

  // Events ----------------------------------------------------------------------
  const eventDefs = [
    { key: 'hack', organizer: 'ananya', community: 'hackathon-hub', college: iitm, category: 'hackathon',
      title: 'Build for Bharat Hackathon', days: 9, hours: 36, mode: 'hybrid', venue: 'CLT, IIT Madras', capacity: 300,
      theme: { style: 'bold', color: 0 }, tags: ['startups', 'ai-ml'],
      description: '36 hours to build something that matters for India. Tracks: fintech, edtech, climate and open innovation.\n\nMeals, mentors and swag included. Teams of 2-4. Freshers welcome.' },
    { key: 'flutter', organizer: 'aarav', community: 'coding-club', college: iitm, category: 'workshop',
      title: 'Flutter from zero to Play Store', days: 3, hours: 3, mode: 'online', venue: null, capacity: 80,
      theme: { style: 'grid', color: 6 }, tags: ['app-dev'],
      description: 'A hands-on workshop: build and publish a real app in one evening. Bring a laptop with Flutter installed.' },
    { key: 'mock', organizer: 'kabir', community: 'placement-prep', college: null, category: 'placement',
      title: 'Mock interview marathon', days: 5, hours: 4, mode: 'online', venue: null, capacity: 40,
      theme: { style: 'ticket', color: 11 }, tags: ['placements'],
      description: '1:1 mock interviews with seniors placed at product companies. DSA + system design rounds with feedback.' },
    { key: 'walk', organizer: 'diya', community: 'shutterbugs', college: iitm, category: 'club',
      title: 'Golden hour photo walk', days: 2, hours: 2, mode: 'in_person', venue: 'Gajendra Circle', capacity: 25,
      theme: { style: 'minimal', color: 10 }, tags: ['photography'],
      description: 'Meet at Gajendra Circle at 5:15. Phones and cameras both welcome. We will end with a quick edit session.' },
    { key: 'league', organizer: 'rohan', community: 'campus-football', college: null, category: 'sports',
      title: 'Inter-hostel 5-a-side league', days: 12, hours: 5, mode: 'in_person', venue: 'Main ground', capacity: null,
      theme: { style: 'bold', color: 3 }, tags: ['sports'],
      description: 'Register your hostel team. Group stage over two weekends, finals under lights.' },
    { key: 'papers', organizer: 'meera', community: 'ml-and-ai', college: null, category: 'meetup',
      title: 'Paper reading night: Attention', days: 1, hours: 2, mode: 'online', venue: null, capacity: 60,
      theme: { style: 'grid', color: 8 }, tags: ['ai-ml', 'research'],
      description: 'We read "Attention Is All You Need" together. No background needed, we go section by section.' },
  ];
  const events = {};
  for (const e of eventDefs) {
    const row = await one(
      `insert into public.events (organizer_id, community_id, college_id, title, description, category, poster_theme,
         starts_at, ends_at, mode, venue, meeting_url, capacity, tags)
       values ($1, $2, $3, $4, $5, $6, $7,
         date_trunc('day', now()) + make_interval(days => $8) + interval '12 hours 30 minutes',
         date_trunc('day', now()) + make_interval(days => $8) + interval '12 hours 30 minutes' + make_interval(hours => $9),
         $10, $11, $12, $13, $14)
       returning id`,
      [ids[e.organizer], communities[e.community], e.college, e.title, e.description, e.category, JSON.stringify(e.theme),
        e.days, e.hours, e.mode, e.venue, e.mode === 'in_person' ? null : 'https://meet.google.com/quad-demo', e.capacity, e.tags],
    );
    events[e.key] = row.id;
  }
  const registrations = {
    hack: ['aarav', 'diya', 'kabir', 'meera', 'rohan'],
    flutter: ['diya', 'rohan', 'ananya', 'meera'],
    mock: ['aarav', 'meera', 'rohan'],
    walk: ['aarav', 'meera', 'rohan'],
    league: ['aarav', 'kabir'],
    papers: ['aarav', 'kabir', 'ananya', 'diya'],
  };
  for (const [key, keys] of Object.entries(registrations)) {
    for (const person of keys) {
      await q(`insert into public.event_registrations (event_id, user_id, status) values ($1, $2, 'going') on conflict do nothing`,
        [events[key], ids[person]]);
    }
  }
  await q(`insert into public.event_updates (event_id, author_id, body) values ($1, $2, $3)`,
    [events.hack, ids.ananya, 'Problem statements drop 48 hours before kickoff. Mentor office hours list is up in #find-a-team.']);
  console.log(`Created ${eventDefs.length} events`);

  // Posts -----------------------------------------------------------------------
  const post = async ({ author, community, type = 'text', title = null, body = null, media = [], tags = [], event = null, hoursAgo = 1 }) => {
    const row = await one(
      `insert into public.posts (author_id, community_id, type, title, body, media, tags, event_id, created_at)
       values ($1, $2, $3, $4, $5, $6, $7, $8, now() - make_interval(mins => $9)) returning id`,
      [ids[author], community ? communities[community] : null, type, title, body, JSON.stringify(media), tags, event,
        Math.round(hoursAgo * 60)],
    );
    return row.id;
  };
  const image = (seed, w = 1200, h = 900) => ({ url: `https://picsum.photos/seed/${seed}/${w}/${h}`, type: 'image', width: w, height: h });

  const p = {};
  p.welcome = await post({ author: 'aarav', community: 'coding-club', type: 'announcement', hoursAgo: 30,
    title: 'Build night this Friday: bring a half-finished project',
    body: 'We have the seminar hall from 7 to 11. Pizza is sorted. Pair up with someone from a different branch and ship one feature before midnight.\n\nDrop what you are working on in the comments 👇', tags: ['app-dev', 'open-source'] });
  p.question = await post({ author: 'meera', community: 'ml-and-ai', type: 'question', hoursAgo: 5,
    title: 'Best way to learn transformers without drowning in math?',
    body: 'I get the intuition for attention but the papers lose me at the math. What worked for you? Courses, blogs, building one from scratch?', tags: ['ai-ml'] });
  p.poll = await post({ author: 'kabir', community: 'placement-prep', type: 'poll', hoursAgo: 8,
    title: 'Which round scares you the most?', tags: ['placements'] });
  const pollOptions = [];
  for (const [i, label] of ['Online assessment', 'DSA interview', 'System design', 'HR round'].entries()) {
    pollOptions.push((await one(`insert into public.poll_options (post_id, label, position) values ($1, $2, $3) returning id`,
      [p.poll, label, i])).id);
  }
  const votes = { aarav: 1, meera: 2, rohan: 0, ananya: 1, diya: 2 };
  for (const [key, option] of Object.entries(votes)) {
    await q(`insert into public.poll_votes (post_id, option_id, user_id) values ($1, $2, $3)`, [p.poll, pollOptions[option], ids[key]]);
    await q(`update public.poll_options set votes_count = votes_count + 1 where id = $1`, [pollOptions[option]]);
  }
  await q(`update public.posts set poll_ends_at = now() + interval '3 days' where id = $1`, [p.poll]);

  p.photos = await post({ author: 'diya', community: 'shutterbugs', type: 'image', hoursAgo: 3,
    body: 'Last evening from the library roof. The light lasted exactly nine minutes.',
    media: [image('quad-roof', 1200, 1500)], tags: ['photography'] });
  p.achievement = await post({ author: 'ananya', community: 'hackathon-hub', type: 'achievement', hoursAgo: 20,
    title: 'We won Smart Campus Hackathon 2026 🏆',
    body: 'Our team built an app that predicts mess crowd levels from Wi-Fi density. Huge thanks to everyone who tested it at 3am.',
    media: [image('quad-hack-win', 1200, 800)], tags: ['startups', 'web-dev'] });
  p.event = await post({ author: 'ananya', community: 'hackathon-hub', type: 'event', hoursAgo: 12,
    body: 'Registrations are open! Teams of 2-4, freshers welcome.', event: events.hack });
  p.campus = await post({ author: 'kabir', community: 'iit-madras', hoursAgo: 2,
    body: 'Found a blue water bottle with stickers near the Himalaya mess. DM me if it\'s yours.' });
  p.resume = await post({ author: 'kabir', community: 'placement-prep', hoursAgo: 40,
    title: 'My resume went from 0 to 7 shortlists. What changed:',
    body: '1. One page, no exceptions\n2. Every bullet has a number\n3. Projects before coursework\n4. Removed the "skills" wall of 40 logos\n\nHappy to review yours this weekend. Comment and I will DM.', tags: ['placements'] });
  p.gallery = await post({ author: 'diya', community: 'shutterbugs', type: 'image', hoursAgo: 50,
    body: 'This week\'s theme was "symmetry". Some favourites from the club 📸',
    media: [image('quad-sym-1', 1000, 1000), image('quad-sym-2', 1000, 1000), image('quad-sym-3', 1000, 1000)], tags: ['photography'] });
  p.personal = await post({ author: 'rohan', hoursAgo: 6,
    body: 'First week done. Survived ragging-free orientation, found the best maggi stall on campus and joined 3 clubs. Hi Quad 👋' });
  p.football = await post({ author: 'rohan', community: 'campus-football', hoursAgo: 26,
    body: 'Need 2 more for tonight\'s 7pm game. Bring water, the ground is dusty.', tags: ['sports'] });
  p.aarav = await post({ author: 'aarav', hoursAgo: 14,
    body: 'Shipped dark mode for our club app today. Took 2 hours to build and 2 days to pick the right grey.', tags: ['app-dev', 'design'] });

  // Reels (short sample clips; replace with real uploads)
  const reel = (file, author, caption, community, hoursAgo) =>
    post({ author, community, type: 'reel', body: caption, hoursAgo,
      media: [{ url: `https://storage.googleapis.com/gtv-videos-bucket/sample/${file}`, type: 'video', width: 1280, height: 720 }] });
  p.reel1 = await reel('ForBiggerBlazes.mp4', 'rohan', 'Match highlights from last night ⚽🔥 #sports', 'campus-football', 4);
  p.reel2 = await reel('ForBiggerJoyrides.mp4', 'diya', 'Weekend trip with the photo club #photography', 'shutterbugs', 9);
  p.reel3 = await reel('ForBiggerEscapes.mp4', 'ananya', '36 hours of hacking in 15 seconds #hackathon', 'hackathon-hub', 16);
  p.reel4 = await reel('ForBiggerFun.mp4', 'aarav', 'POV: the demo actually works on the first try', 'coding-club', 28);

  // Reactions, comments, saves
  const reactions = [
    ['welcome', ['diya', 'meera', 'ananya', 'rohan'], 'fire'], ['question', ['aarav', 'kabir'], 'like'],
    ['photos', ['aarav', 'meera', 'rohan', 'kabir', 'ananya'], 'like'], ['achievement', ['aarav', 'diya', 'kabir', 'meera'], 'clap'],
    ['resume', ['aarav', 'meera', 'rohan', 'ananya', 'diya'], 'idea'], ['gallery', ['aarav', 'rohan'], 'like'],
    ['personal', ['aarav', 'kabir', 'diya'], 'like'], ['aarav', ['diya', 'meera'], 'haha'], ['event', ['aarav', 'meera'], 'fire'],
    ['reel1', ['aarav', 'kabir', 'ananya'], 'fire'], ['reel2', ['aarav', 'meera'], 'like'], ['reel3', ['aarav', 'diya', 'kabir'], 'fire'],
    ['reel4', ['diya', 'meera', 'rohan'], 'haha'],
  ];
  for (const [postKey, keys, kind] of reactions) {
    for (const key of keys) {
      await q(`insert into public.post_reactions (post_id, user_id, kind) values ($1, $2, $3) on conflict do nothing`,
        [p[postKey], ids[key], kind]);
    }
  }
  const comment = async (postKey, author, body, parent = null) =>
    (await one(`insert into public.comments (post_id, author_id, body, parent_id) values ($1, $2, $3, $4) returning id`,
      [p[postKey], ids[author], body, parent])).id;
  const c1 = await comment('question', 'aarav', 'Build a tiny one from scratch. Karpathy\'s "Let\'s build GPT" video made it click for me.');
  await comment('question', 'meera', 'Ooh I have been avoiding that one because it is 2 hours. Worth it?', c1);
  await comment('question', 'aarav', 'Completely. Watch at 1.25x and code along.', c1);
  await comment('question', 'kabir', 'The Illustrated Transformer blog is the gentlest intro I know.');
  const c2 = await comment('welcome', 'diya', 'Bringing the half-done design system for the club app 😅');
  await comment('welcome', 'aarav', 'Perfect, we need it for the dark mode bugs.', c2);
  await comment('welcome', 'rohan', 'Is this open for freshers?');
  await comment('resume', 'rohan', 'Would love a review! Just made my first resume.');
  await comment('photos', 'meera', 'Those nine minutes were worth it. Stunning.');
  await comment('achievement', 'kabir', 'Congrats! Would love a write-up of the Wi-Fi density model.');
  await q(`insert into public.saved_posts (user_id, post_id) values ($1, $2), ($1, $3) on conflict do nothing`,
    [ids.aarav, p.resume, p.question]);
  console.log('Created posts, reels, comments and reactions');

  // Achievements ---------------------------------------------------------------
  const achievements = [
    ['ananya', 'Winner, Smart Campus Hackathon 2026', 'hackathon', 'IIT Madras', 20],
    ['ananya', 'AWS Certified Cloud Practitioner', 'certification', 'Amazon Web Services', 120],
    ['aarav', 'Google Summer of Code contributor', 'internship', 'Google', 200],
    ['aarav', 'Finalist, Build for Bharat 2025', 'hackathon', 'IIT Madras', 300],
    ['meera', 'Paper accepted at student research symposium', 'research', 'IIT Madras', 60],
    ['kabir', 'ICPC Regionals, top 100', 'competition', 'ICPC', 150],
    ['diya', 'Best photo, inter-IIT cultural meet', 'cultural', 'Inter-IIT', 90],
  ];
  for (const [key, title, category, issuer, daysAgo] of achievements) {
    await q(`insert into public.achievements (user_id, title, category, issuer, achieved_on) values ($1, $2, $3, $4, current_date - $5::int)`,
      [ids[key], title, category, issuer, daysAgo]);
  }

  // Chats ----------------------------------------------------------------------
  const direct = async (a, b) => {
    const key = [ids[a], ids[b]].sort().join(':');
    const row = await one(`insert into public.conversations (type, direct_key, created_by) values ('direct', $1, $2) returning id`,
      [key, ids[a]]);
    await q(`insert into public.conversation_members (conversation_id, user_id) values ($1, $2), ($1, $3)`, [row.id, ids[a], ids[b]]);
    return row.id;
  };
  const say = async (conversation, sender, body, minutesAgo) => {
    await q(`insert into public.messages (conversation_id, sender_id, body, created_at) values ($1, $2, $3, now() - make_interval(mins => $4))`,
      [conversation, ids[sender], body, minutesAgo]);
  };
  const ad = await direct('aarav', 'diya');
  await say(ad, 'diya', 'are you coming to build night?', 95);
  await say(ad, 'aarav', 'obviously. bringing the dark mode PR', 90);
  await say(ad, 'diya', 'ok I will bring the new icon set. can you review my Figma before?', 30);
  const am = await direct('aarav', 'meera');
  await say(am, 'meera', 'the paper reading night link is in the event page btw', 200);
  await say(am, 'aarav', 'registered! see you there', 180);
  const squad = (await one(`insert into public.conversations (type, title, created_by) values ('group', 'Hackathon squad 🚀', $1) returning id`,
    [ids.ananya])).id;
  for (const [key, role] of [['ananya', 'owner'], ['aarav', 'member'], ['diya', 'member'], ['meera', 'member']]) {
    await q(`insert into public.conversation_members (conversation_id, user_id, role) values ($1, $2, $3)`, [squad, ids[key], role]);
  }
  await say(squad, 'ananya', 'team, Build for Bharat registrations are open. we doing it?', 300);
  await say(squad, 'meera', 'yes!! I can do the ML side', 280);
  await say(squad, 'diya', 'design + pitch deck on me', 270);
  await say(squad, 'aarav', 'I will take the app. let us pick a track by Friday', 20);
  const general = (await one(`select conversation_id as id from public.rooms where community_id = $1 and name = 'general'`,
    [communities['coding-club']])).id;
  await say(general, 'diya', 'welcome to the new members! drop your github below 👋', 400);
  await say(general, 'rohan', 'hi! fresher here, mostly doing python so far', 380);
  const codingRoom = (await one(`select conversation_id as id from public.rooms where id = $1`, [roomIds['coding-room']])).id;
  await say(codingRoom, 'meera', 'anyone free to help with a flutter layout overflow?', 45);
  await say(codingRoom, 'aarav', 'wrap it in Expanded and send me a screenshot', 40);
  console.log('Created chats and room messages');

  await q(`select private.refresh_college_stats()`);
  await q(`notify pgrst, 'reload schema'`);

  console.log(`\nDone. Sign in as any demo student, e.g. aarav@${DOMAIN} / ${DEMO_PASSWORD}`);
  console.log(`Accounts: ${people.map((x) => `${x.key}@${DOMAIN}`).join(', ')}`);
} finally {
  await db.end();
}
