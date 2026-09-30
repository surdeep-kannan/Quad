-- Read models for the app: views with the viewer's own state joined in, the
-- ranked home and reels feeds, suggestions, search and college rankings.
--
-- Every view is security_invoker, so the RLS rules of the underlying tables
-- decide what each student can see.

-- ---------------------------------------------------------------------------
-- Views
-- ---------------------------------------------------------------------------

create or replace view public.profile_summaries
with (security_invoker = on) as
select
  p.id,
  p.username,
  p.full_name,
  p.avatar_url,
  p.bio,
  p.college_id,
  p.department,
  p.year_of_study,
  p.skills,
  p.interests,
  p.is_verified,
  p.followers_count,
  p.following_count,
  p.posts_count,
  p.onboarded,
  p.last_seen_at,
  p.created_at,
  case when c.id is null then null else
    jsonb_build_object('id', c.id, 'name', c.name, 'short_name', c.short_name, 'slug', c.slug, 'city', c.city)
  end as college,
  exists (select 1 from public.follows f where f.follower_id = auth.uid() and f.following_id = p.id) as is_following,
  exists (select 1 from public.follows f where f.follower_id = p.id and f.following_id = auth.uid()) as follows_me,
  exists (select 1 from public.blocks b where b.blocker_id = auth.uid() and b.blocked_id = p.id) as is_blocked
from public.profiles p
left join public.colleges c on c.id = p.college_id;

create or replace view public.community_details
with (security_invoker = on) as
select
  c.id,
  c.slug,
  c.name,
  c.tagline,
  c.description,
  c.category,
  c.college_id,
  c.avatar_url,
  c.banner_url,
  c.color,
  c.visibility,
  c.rules,
  c.tags,
  c.created_by,
  c.members_count,
  c.posts_count,
  c.created_at,
  case when col.id is null then null else
    jsonb_build_object('id', col.id, 'name', col.name, 'short_name', col.short_name)
  end as college,
  m.role as my_role,
  m.status as my_status
from public.communities c
left join public.colleges col on col.id = c.college_id
left join public.community_members m on m.community_id = c.id and m.user_id = auth.uid();

create or replace view public.post_details
with (security_invoker = on) as
select
  p.id,
  p.author_id,
  p.community_id,
  p.type,
  p.title,
  p.body,
  p.media,
  p.tags,
  p.event_id,
  p.poll_ends_at,
  p.is_pinned,
  p.is_locked,
  p.is_removed,
  p.removed_reason,
  p.reaction_counts,
  p.likes_count,
  p.comments_count,
  p.shares_count,
  p.saves_count,
  p.views_count,
  p.created_at,
  p.edited_at,
  jsonb_build_object(
    'id', a.id, 'username', a.username, 'full_name', a.full_name, 'avatar_url', a.avatar_url,
    'is_verified', a.is_verified, 'college_id', a.college_id, 'department', a.department
  ) as author,
  case when c.id is null then null else
    jsonb_build_object(
      'id', c.id, 'slug', c.slug, 'name', c.name, 'avatar_url', c.avatar_url,
      'color', c.color, 'category', c.category, 'college_id', c.college_id
    )
  end as community,
  r.kind as my_reaction,
  (s.user_id is not null) as is_saved,
  (f.user_id is not null) as is_following,
  v.option_id as my_vote,
  case when p.type = 'poll' then (
    select coalesce(
      jsonb_agg(jsonb_build_object('id', o.id, 'label', o.label, 'votes', o.votes_count) order by o.position),
      '[]'::jsonb
    )
    from public.poll_options o
    where o.post_id = p.id
  ) end as poll_options,
  case when p.event_id is not null then (
    select jsonb_build_object(
      'id', e.id, 'title', e.title, 'starts_at', e.starts_at, 'ends_at', e.ends_at, 'mode', e.mode,
      'venue', e.venue, 'poster_url', e.poster_url, 'poster_theme', e.poster_theme, 'category', e.category,
      'registrations_count', e.registrations_count, 'capacity', e.capacity, 'is_cancelled', e.is_cancelled
    )
    from public.events e
    where e.id = p.event_id
  ) end as event
from public.posts p
join public.profiles a on a.id = p.author_id
left join public.communities c on c.id = p.community_id
left join public.post_reactions r on r.post_id = p.id and r.user_id = auth.uid()
left join public.saved_posts s on s.post_id = p.id and s.user_id = auth.uid()
left join public.post_follows f on f.post_id = p.id and f.user_id = auth.uid()
left join public.poll_votes v on v.post_id = p.id and v.user_id = auth.uid();

create or replace view public.comment_details
with (security_invoker = on) as
select
  cm.id,
  cm.post_id,
  cm.parent_id,
  cm.depth,
  case when cm.is_deleted or cm.is_removed then null else cm.author_id end as author_id,
  case when cm.is_deleted or cm.is_removed then null else cm.body end as body,
  cm.is_deleted,
  cm.is_removed,
  cm.likes_count,
  cm.replies_count,
  cm.created_at,
  cm.edited_at,
  case when cm.is_deleted or cm.is_removed then null else
    jsonb_build_object(
      'id', a.id, 'username', a.username, 'full_name', a.full_name,
      'avatar_url', a.avatar_url, 'is_verified', a.is_verified
    )
  end as author,
  exists (select 1 from public.comment_likes l where l.comment_id = cm.id and l.user_id = auth.uid()) as liked_by_me
from public.comments cm
join public.profiles a on a.id = cm.author_id;

create or replace view public.event_details
with (security_invoker = on) as
select
  e.id,
  e.organizer_id,
  e.community_id,
  e.college_id,
  e.title,
  e.description,
  e.category,
  e.poster_url,
  e.poster_theme,
  e.starts_at,
  e.ends_at,
  e.mode,
  e.venue,
  e.address,
  e.capacity,
  e.registration_deadline,
  e.registrations_count,
  e.waitlist_count,
  e.visibility,
  e.tags,
  e.is_cancelled,
  e.created_at,
  e.updated_at,
  jsonb_build_object(
    'id', o.id, 'username', o.username, 'full_name', o.full_name,
    'avatar_url', o.avatar_url, 'is_verified', o.is_verified
  ) as organizer,
  case when c.id is null then null else
    jsonb_build_object('id', c.id, 'slug', c.slug, 'name', c.name, 'avatar_url', c.avatar_url, 'color', c.color)
  end as community,
  case when col.id is null then null else
    jsonb_build_object('id', col.id, 'name', col.name, 'short_name', col.short_name, 'city', col.city)
  end as college,
  r.status as my_status,
  (
    select coalesce(jsonb_agg(x.person order by x.created_at), '[]'::jsonb)
    from (
      select
        jsonb_build_object('id', p.id, 'username', p.username, 'full_name', p.full_name, 'avatar_url', p.avatar_url) as person,
        er.created_at
      from public.event_registrations er
      join public.profiles p on p.id = er.user_id
      where er.event_id = e.id and er.status in ('going', 'attended')
      order by er.created_at
      limit 5
    ) x
  ) as attendees_preview
from public.events e
join public.profiles o on o.id = e.organizer_id
left join public.communities c on c.id = e.community_id
left join public.colleges col on col.id = e.college_id
left join public.event_registrations r on r.event_id = e.id and r.user_id = auth.uid();

create or replace view public.room_details
with (security_invoker = on) as
select
  r.id,
  r.community_id,
  r.conversation_id,
  r.name,
  r.topic,
  r.kind,
  r.position,
  r.is_locked,
  r.created_at,
  cv.last_message_at,
  cv.last_message_preview,
  cm.last_read_at,
  (cm.user_id is not null) as is_member
from public.rooms r
left join public.conversations cv on cv.id = r.conversation_id
left join public.conversation_members cm on cm.conversation_id = r.conversation_id and cm.user_id = auth.uid();

create or replace view public.notification_details
with (security_invoker = on) as
select
  n.id,
  n.user_id,
  n.type,
  n.post_id,
  n.comment_id,
  n.community_id,
  n.event_id,
  n.conversation_id,
  n.room_id,
  n.data,
  n.read_at,
  n.created_at,
  case when a.id is null then null else
    jsonb_build_object('id', a.id, 'username', a.username, 'full_name', a.full_name, 'avatar_url', a.avatar_url)
  end as actor,
  (
    select jsonb_build_object('id', p.id, 'type', p.type, 'title', p.title, 'body', left(p.body, 140), 'media', p.media -> 0)
    from public.posts p where p.id = n.post_id
  ) as post,
  (
    select jsonb_build_object('id', c.id, 'slug', c.slug, 'name', c.name, 'avatar_url', c.avatar_url, 'color', c.color)
    from public.communities c where c.id = n.community_id
  ) as community,
  (
    select jsonb_build_object('id', e.id, 'title', e.title, 'starts_at', e.starts_at)
    from public.events e where e.id = n.event_id
  ) as event
from public.notifications n
left join public.profiles a on a.id = n.actor_id;

create or replace view public.report_details
with (security_invoker = on) as
select
  r.id,
  r.target_type,
  r.target_id,
  r.community_id,
  r.target_user_id,
  r.reason,
  r.details,
  r.snapshot,
  r.status,
  r.reviewed_at,
  r.resolution_note,
  r.created_at,
  jsonb_build_object('id', rp.id, 'username', rp.username, 'full_name', rp.full_name, 'avatar_url', rp.avatar_url) as reporter,
  case when tu.id is null then null else
    jsonb_build_object('id', tu.id, 'username', tu.username, 'full_name', tu.full_name, 'avatar_url', tu.avatar_url)
  end as target_user,
  (select count(*)::integer from public.reports o where o.target_type = r.target_type and o.target_id = r.target_id) as reports_on_target
from public.reports r
join public.profiles rp on rp.id = r.reporter_id
left join public.profiles tu on tu.id = r.target_user_id;

-- ---------------------------------------------------------------------------
-- Feeds
-- ---------------------------------------------------------------------------

-- The home feed.
--   for_you   ranks recent posts by engagement, freshness and affinity: posts
--             from joined communities, followed people, the student's college
--             and tags that match their interests are boosted.
--   following posts from followed people and joined communities, newest first.
--   campus    posts from the student's college, newest first.
create or replace function public.home_feed(p_mode text default 'for_you', p_limit integer default 20, p_offset integer default 0)
returns setof public.post_details
language sql
stable
security invoker
set search_path = ''
as $$
  with me as (
    select p.id, p.college_id, p.interests from public.profiles p where p.id = auth.uid()
  ),
  joined as (
    select m.community_id from public.community_members m where m.user_id = auth.uid() and m.status = 'active'
  ),
  followed as (
    select f.following_id from public.follows f where f.follower_id = auth.uid()
  )
  select d.*
  from public.post_details d
  cross join me
  where d.type <> 'reel'
    and not d.is_removed
    and case p_mode
      when 'following' then
        d.author_id = me.id
        or d.author_id in (select following_id from followed)
        or d.community_id in (select community_id from joined)
      when 'campus' then
        me.college_id is not null
        and ((d.author ->> 'college_id')::uuid = me.college_id or (d.community ->> 'college_id')::uuid = me.college_id)
      else d.created_at > now() - interval '60 days'
    end
  order by
    case when p_mode = 'for_you' then
      (
        1.0
        + case when d.community_id in (select community_id from joined) then 1.0 else 0 end
        + case when d.author_id in (select following_id from followed) then 1.2 else 0 end
        + case when me.college_id is not null and (d.author ->> 'college_id')::uuid = me.college_id then 0.5 else 0 end
        + 0.3 * least(3, cardinality(array(select unnest(d.tags) intersect select unnest(me.interests))))
        + case when d.type = 'announcement' and d.community_id in (select community_id from joined) then 0.8 else 0 end
      )
      * (1.0 + ln(1.0 + d.likes_count + 2 * d.comments_count + d.shares_count))
      / power(extract(epoch from (now() - d.created_at)) / 3600.0 + 2.0, 1.3)
    else extract(epoch from d.created_at)
    end desc,
    d.created_at desc
  limit least(greatest(p_limit, 1), 50)
  offset greatest(p_offset, 0);
$$;

create or replace function public.community_feed(
  p_community uuid,
  p_sort text default 'hot',
  p_limit integer default 20,
  p_offset integer default 0
)
returns setof public.post_details
language sql
stable
security invoker
set search_path = ''
as $$
  select d.*
  from public.post_details d
  where d.community_id = p_community
    and d.type <> 'reel'
  order by
    d.is_pinned desc,
    case p_sort
      when 'top' then (d.likes_count + 2 * d.comments_count)::numeric
      when 'hot' then (1.0 + ln(1.0 + d.likes_count + 2 * d.comments_count))
                      / power(extract(epoch from (now() - d.created_at)) / 3600.0 + 2.0, 1.2)
      else extract(epoch from d.created_at)
    end desc,
    d.created_at desc
  limit least(greatest(p_limit, 1), 50)
  offset greatest(p_offset, 0);
$$;

create or replace function public.reels_feed(p_limit integer default 10, p_offset integer default 0)
returns setof public.post_details
language sql
stable
security invoker
set search_path = ''
as $$
  select d.*
  from public.post_details d
  where d.type = 'reel' and not d.is_removed
  order by
    (1.0 + ln(1.0 + d.likes_count + 2 * d.comments_count + d.shares_count + 0.1 * d.views_count))
      / power(extract(epoch from (now() - d.created_at)) / 3600.0 + 2.0, 0.8) desc,
    d.created_at desc
  limit least(greatest(p_limit, 1), 30)
  offset greatest(p_offset, 0);
$$;

create or replace function public.suggested_communities(p_limit integer default 10)
returns setof public.community_details
language sql
stable
security invoker
set search_path = ''
as $$
  select cd.*
  from public.community_details cd
  cross join (select p.college_id, p.interests from public.profiles p where p.id = auth.uid()) me
  where cd.my_status is null
  order by
    (case when me.college_id is not null and cd.college_id = me.college_id then 2 else 0 end)
      + cardinality(array(select unnest(cd.tags) intersect select unnest(me.interests))) desc,
    cd.members_count desc
  limit least(greatest(p_limit, 1), 30);
$$;

create or replace function public.suggested_people(p_limit integer default 10)
returns setof public.profile_summaries
language sql
stable
security invoker
set search_path = ''
as $$
  select ps.*
  from public.profile_summaries ps
  cross join (select p.id, p.college_id, p.interests from public.profiles p where p.id = auth.uid()) me
  where ps.id <> me.id
    and ps.onboarded
    and not ps.is_following
    and not ps.is_blocked
  order by
    (case when me.college_id is not null and ps.college_id = me.college_id then 2 else 0 end)
      + cardinality(array(select unnest(ps.interests) intersect select unnest(me.interests)))
      + (
        select count(*)::integer
        from public.follows f1
        join public.follows f2 on f2.follower_id = f1.following_id
        where f1.follower_id = me.id and f2.following_id = ps.id
      ) desc,
    ps.followers_count desc
  limit least(greatest(p_limit, 1), 30);
$$;

-- ---------------------------------------------------------------------------
-- Search
-- ---------------------------------------------------------------------------

create or replace function public.search_profiles(p_query text, p_limit integer default 20)
returns setof public.profile_summaries
language sql
stable
security invoker
set search_path = ''
as $$
  select ps.*
  from public.profile_summaries ps
  where char_length(trim(coalesce(p_query, ''))) > 0
    and (
      ps.username ilike private.contains_pattern(p_query)
      or ps.full_name ilike private.contains_pattern(p_query)
      or extensions.similarity(ps.full_name, trim(p_query)) > 0.3
    )
  order by
    (ps.username ilike private.prefix_pattern(p_query) or ps.full_name ilike private.prefix_pattern(p_query)) desc,
    extensions.similarity(ps.full_name, trim(p_query)) desc,
    ps.followers_count desc
  limit least(greatest(p_limit, 1), 50);
$$;

create or replace function public.search_communities(p_query text, p_limit integer default 20)
returns setof public.community_details
language sql
stable
security invoker
set search_path = ''
as $$
  select cd.*
  from public.community_details cd
  where char_length(trim(coalesce(p_query, ''))) > 0
    and (
      cd.name ilike private.contains_pattern(p_query)
      or cd.tagline ilike private.contains_pattern(p_query)
      or cd.slug ilike private.contains_pattern(p_query)
      or extensions.similarity(cd.name, trim(p_query)) > 0.3
      or lower(trim(p_query)) = any (cd.tags)
    )
  order by
    (cd.name ilike private.prefix_pattern(p_query)) desc,
    extensions.similarity(cd.name, trim(p_query)) desc,
    cd.members_count desc
  limit least(greatest(p_limit, 1), 50);
$$;

create or replace function public.search_events(p_query text, p_limit integer default 20)
returns setof public.event_details
language sql
stable
security invoker
set search_path = ''
as $$
  select ed.*
  from public.event_details ed
  where char_length(trim(coalesce(p_query, ''))) > 0
    and not ed.is_cancelled
    and (
      ed.title ilike private.contains_pattern(p_query)
      or ed.venue ilike private.contains_pattern(p_query)
      or ed.category = lower(trim(p_query))
      or extensions.similarity(ed.title, trim(p_query)) > 0.3
      or lower(trim(p_query)) = any (ed.tags)
    )
  order by
    (coalesce(ed.ends_at, ed.starts_at) >= now()) desc,
    abs(extract(epoch from (ed.starts_at - now()))) asc
  limit least(greatest(p_limit, 1), 50);
$$;

create or replace function public.search_posts(p_query text, p_type text default null, p_limit integer default 20)
returns setof public.post_details
language sql
stable
security invoker
set search_path = ''
as $$
  select d.*
  from public.post_details d
  join public.posts p on p.id = d.id
  where char_length(trim(coalesce(p_query, ''))) > 0
    and not d.is_removed
    and (p_type is null or d.type = p_type)
    and (
      p.search @@ websearch_to_tsquery('simple', p_query)
      or d.title ilike private.contains_pattern(p_query)
      or lower(trim(p_query)) = any (d.tags)
    )
  order by
    ts_rank(p.search, websearch_to_tsquery('simple', p_query)) desc,
    d.created_at desc
  limit least(greatest(p_limit, 1), 50);
$$;

create or replace function public.search_colleges(p_query text, p_limit integer default 20)
returns setof public.colleges
language sql
stable
security invoker
set search_path = ''
as $$
  select c.*
  from public.colleges c
  where char_length(trim(coalesce(p_query, ''))) > 0
    and (
      c.name ilike private.contains_pattern(p_query)
      or c.short_name ilike private.contains_pattern(p_query)
      or c.city ilike private.contains_pattern(p_query)
      or extensions.similarity(c.name, trim(p_query)) > 0.25
    )
  order by
    (c.short_name ilike private.prefix_pattern(p_query) or c.name ilike private.prefix_pattern(p_query)) desc,
    extensions.similarity(c.name, trim(p_query)) desc,
    c.is_verified desc,
    c.name
  limit least(greatest(p_limit, 1), 50);
$$;

create or replace function public.search_rooms(p_query text, p_limit integer default 20)
returns table (
  id uuid,
  name text,
  topic text,
  kind text,
  conversation_id uuid,
  is_member boolean,
  community jsonb
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    r.id,
    r.name,
    r.topic,
    r.kind,
    r.conversation_id,
    r.is_member,
    jsonb_build_object('id', c.id, 'slug', c.slug, 'name', c.name, 'avatar_url', c.avatar_url, 'color', c.color) as community
  from public.room_details r
  join public.communities c on c.id = r.community_id
  where char_length(trim(coalesce(p_query, ''))) > 0
    and (
      r.name ilike private.contains_pattern(p_query)
      or r.topic ilike private.contains_pattern(p_query)
      or r.kind = lower(trim(p_query))
    )
  order by r.is_member desc, c.members_count desc
  limit least(greatest(p_limit, 1), 50);
$$;

-- ---------------------------------------------------------------------------
-- College rankings
-- ---------------------------------------------------------------------------

-- The ranking method, stored as data so the app can show exactly how scores
-- are calculated and the weights can be tuned in one place.
create table public.ranking_pillars (
  key text primary key,
  label text not null,
  weight numeric(4, 3) not null check (weight between 0 and 1),
  window_days integer,
  description text not null,
  position smallint not null default 0
);

insert into public.ranking_pillars (key, label, weight, window_days, description, position) values
  ('activity', 'Community activity', 0.25, 30,
    'Posts and comments written by the college''s students in the last 30 days.', 0),
  ('events', 'Events', 0.20, 180,
    'Events hosted by the college or its communities in the last 180 days, plus upcoming ones.', 1),
  ('clubs', 'Clubs', 0.15, null,
    'Club communities linked to the college.', 2),
  ('hackathons', 'Hackathons', 0.15, 365,
    'Hackathons hosted by the college, plus hackathon results students logged in the last year.', 3),
  ('achievements', 'Achievements', 0.15, 365,
    'Achievements students added to their profiles in the last year.', 4),
  ('engagement', 'Student engagement', 0.10, 30,
    'Share of the college''s students on Quad who posted or commented in the last 30 days.', 5)
on conflict (key) do nothing;

create table public.college_stats (
  college_id uuid primary key references public.colleges (id) on delete cascade,
  students integer not null default 0,
  active_students integer not null default 0,
  communities integer not null default 0,
  clubs integer not null default 0,
  events integer not null default 0,
  hackathons integer not null default 0,
  achievements integer not null default 0,
  activity integer not null default 0,
  engagement_rate numeric(6, 4) not null default 0,
  pillar_scores jsonb not null default '{}'::jsonb,
  score numeric(6, 2) not null default 0,
  rank integer,
  computed_at timestamptz not null default now()
);

alter table public.ranking_pillars enable row level security;
alter table public.college_stats enable row level security;

create policy "The ranking method is public"
  on public.ranking_pillars for select to authenticated
  using (true);

create policy "College stats are public"
  on public.college_stats for select to authenticated
  using (true);

revoke insert, update, delete on public.ranking_pillars from anon, authenticated;
revoke insert, update, delete on public.college_stats from anon, authenticated;

-- Recomputes every college's metrics and score.
--
-- Count-based pillars are log-scaled against the best college, so one very
-- large college doesn't flatten everyone else:
--     pillar = ln(1 + value) / ln(1 + best value)
-- Engagement is already a share between 0 and 1. The score is
--     100 * sum(weight * pillar)
-- Colleges with no students on Quad yet aren't ranked.
create or replace function private.refresh_college_stats()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  w_activity numeric := coalesce((select weight from public.ranking_pillars where key = 'activity'), 0);
  w_events numeric := coalesce((select weight from public.ranking_pillars where key = 'events'), 0);
  w_clubs numeric := coalesce((select weight from public.ranking_pillars where key = 'clubs'), 0);
  w_hackathons numeric := coalesce((select weight from public.ranking_pillars where key = 'hackathons'), 0);
  w_achievements numeric := coalesce((select weight from public.ranking_pillars where key = 'achievements'), 0);
  w_engagement numeric := coalesce((select weight from public.ranking_pillars where key = 'engagement'), 0);
begin
  with base as (
    select
      c.id as college_id,
      (select count(*) from public.profiles p where p.college_id = c.id)::integer as students,
      (
        select count(distinct x.author_id) from (
          select po.author_id from public.posts po join public.profiles p on p.id = po.author_id
          where p.college_id = c.id and po.created_at > now() - interval '30 days'
          union all
          select co.author_id from public.comments co join public.profiles p on p.id = co.author_id
          where p.college_id = c.id and co.created_at > now() - interval '30 days'
        ) x
      )::integer as active_students,
      (select count(*) from public.communities cm where cm.college_id = c.id)::integer as communities,
      (select count(*) from public.communities cm where cm.college_id = c.id and cm.category = 'club')::integer as clubs,
      (
        select count(*) from public.events e
        left join public.communities cm on cm.id = e.community_id
        where (e.college_id = c.id or cm.college_id = c.id)
          and not e.is_cancelled
          and e.starts_at > now() - interval '180 days'
      )::integer as events,
      (
        (
          select count(*) from public.events e
          left join public.communities cm on cm.id = e.community_id
          where (e.college_id = c.id or cm.college_id = c.id)
            and not e.is_cancelled
            and e.category = 'hackathon'
            and e.starts_at > now() - interval '365 days'
        ) + (
          select count(*) from public.achievements a join public.profiles p on p.id = a.user_id
          where p.college_id = c.id
            and a.category = 'hackathon'
            and coalesce(a.achieved_on, a.created_at::date) > current_date - 365
        )
      )::integer as hackathons,
      (
        select count(*) from public.achievements a join public.profiles p on p.id = a.user_id
        where p.college_id = c.id and coalesce(a.achieved_on, a.created_at::date) > current_date - 365
      )::integer as achievements,
      (
        (
          select count(*) from public.posts po join public.profiles p on p.id = po.author_id
          where p.college_id = c.id and po.created_at > now() - interval '30 days' and not po.is_removed
        ) + (
          select count(*) from public.comments co join public.profiles p on p.id = co.author_id
          where p.college_id = c.id and co.created_at > now() - interval '30 days'
        )
      )::integer as activity
    from public.colleges c
  ),
  best as (
    select
      greatest(max(activity), 1) as activity,
      greatest(max(events), 1) as events,
      greatest(max(clubs), 1) as clubs,
      greatest(max(hackathons), 1) as hackathons,
      greatest(max(achievements), 1) as achievements
    from base
  ),
  pillars as (
    select
      b.*,
      case when b.students > 0 then least(b.active_students::numeric / b.students, 1) else 0::numeric end as engagement_rate,
      ln((1 + b.activity)::numeric) / ln((1 + best.activity)::numeric) as p_activity,
      ln((1 + b.events)::numeric) / ln((1 + best.events)::numeric) as p_events,
      ln((1 + b.clubs)::numeric) / ln((1 + best.clubs)::numeric) as p_clubs,
      ln((1 + b.hackathons)::numeric) / ln((1 + best.hackathons)::numeric) as p_hackathons,
      ln((1 + b.achievements)::numeric) / ln((1 + best.achievements)::numeric) as p_achievements
    from base b cross join best
  ),
  scored as (
    select
      p.*,
      round(100 * (
        w_activity * p.p_activity
        + w_events * p.p_events
        + w_clubs * p.p_clubs
        + w_hackathons * p.p_hackathons
        + w_achievements * p.p_achievements
        + w_engagement * p.engagement_rate
      ), 2) as score
    from pillars p
  ),
  ranked as (
    select
      s.*,
      case when s.students > 0 then rank() over (partition by (s.students > 0) order by s.score desc) end as rank
    from scored s
  )
  insert into public.college_stats as cs (
    college_id, students, active_students, communities, clubs, events, hackathons, achievements, activity,
    engagement_rate, pillar_scores, score, rank, computed_at
  )
  select
    r.college_id, r.students, r.active_students, r.communities, r.clubs, r.events, r.hackathons, r.achievements,
    r.activity, round(r.engagement_rate, 4),
    jsonb_build_object(
      'activity', round(r.p_activity, 4),
      'events', round(r.p_events, 4),
      'clubs', round(r.p_clubs, 4),
      'hackathons', round(r.p_hackathons, 4),
      'achievements', round(r.p_achievements, 4),
      'engagement', round(r.engagement_rate, 4)
    ),
    r.score,
    r.rank,
    now()
  from ranked r
  on conflict (college_id) do update set
    students = excluded.students,
    active_students = excluded.active_students,
    communities = excluded.communities,
    clubs = excluded.clubs,
    events = excluded.events,
    hackathons = excluded.hackathons,
    achievements = excluded.achievements,
    activity = excluded.activity,
    engagement_rate = excluded.engagement_rate,
    pillar_scores = excluded.pillar_scores,
    score = excluded.score,
    rank = excluded.rank,
    computed_at = excluded.computed_at;
end;
$$;

create or replace view public.college_rankings
with (security_invoker = on) as
select
  c.id,
  c.name,
  c.short_name,
  c.slug,
  c.city,
  c.state,
  c.type,
  c.established,
  c.website,
  c.logo_url,
  c.cover_url,
  c.description,
  c.is_verified,
  coalesce(s.students, 0) as students,
  coalesce(s.active_students, 0) as active_students,
  coalesce(s.communities, 0) as communities,
  coalesce(s.clubs, 0) as clubs,
  coalesce(s.events, 0) as events,
  coalesce(s.hackathons, 0) as hackathons,
  coalesce(s.achievements, 0) as achievements,
  coalesce(s.activity, 0) as activity,
  coalesce(s.engagement_rate, 0) as engagement_rate,
  coalesce(s.pillar_scores, '{}'::jsonb) as pillar_scores,
  coalesce(s.score, 0) as score,
  s.rank,
  s.computed_at
from public.colleges c
left join public.college_stats s on s.college_id = c.id;

-- The leaderboard. Stats are recomputed when they're more than 30 minutes old
-- (pg_cron also refreshes them hourly where available).
create or replace function public.college_leaderboard(p_state text default null, p_limit integer default 50, p_offset integer default 0)
returns setof public.college_rankings
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Not signed in' using errcode = '28000';
  end if;

  if not exists (select 1 from public.college_stats where computed_at > now() - interval '30 minutes')
     and pg_try_advisory_xact_lock(hashtext('quad.college_stats')) then
    perform private.refresh_college_stats();
  end if;

  return query
    select cr.*
    from public.college_rankings cr
    where p_state is null or cr.state = p_state
    order by cr.rank nulls last, cr.score desc, cr.name
    limit least(greatest(p_limit, 1), 100)
    offset greatest(p_offset, 0);
end;
$$;
