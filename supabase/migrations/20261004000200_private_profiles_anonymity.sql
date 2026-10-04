-- Private profiles and anonymous posting.
--
-- Private profile: profile details, profile posts, achievements and follow
-- lists are visible only to people the student follows. Their reactions and
-- event registrations aren't listed publicly.
--
-- Anonymous content: posts and comments in communities and messages in
-- community rooms can be anonymous. They show a fresh random name every time
-- (e.g. "anonymous_quiet_otter_482"). Content from private profiles is always
-- anonymous; anyone else can choose it per post, comment or message.
--
-- The real author of anonymous content is hidden at the database level:
-- author_id columns aren't readable by students, views mask the author, and
-- anonymous room messages store no sender at all (the link lives in
-- message_authors, readable only by its author). Moderators can still remove
-- anonymous content; only platform admins can see who wrote it.

-- ---------------------------------------------------------------------------
-- Columns and tables
-- ---------------------------------------------------------------------------

alter table public.profiles add column is_private boolean not null default false;
grant update (is_private) on public.profiles to authenticated;

alter table public.posts add column is_anonymous boolean not null default false;
alter table public.posts add column anon_name text;
alter table public.comments add column is_anonymous boolean not null default false;
alter table public.comments add column anon_name text;
alter table public.messages add column is_anonymous boolean not null default false;
alter table public.messages add column anon_name text;

grant insert (is_anonymous) on public.posts to authenticated;
grant insert (is_anonymous) on public.comments to authenticated;
grant insert (is_anonymous) on public.messages to authenticated;

-- Who sent each anonymous room message. Only the sender can read their rows.
create table public.message_authors (
  message_id uuid primary key references public.messages (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade
);

create index message_authors_user_idx on public.message_authors (user_id);

alter table public.message_authors enable row level security;

create policy "See your own anonymous messages"
  on public.message_authors for select to authenticated
  using (user_id = (select auth.uid()));

revoke insert, update, delete on public.message_authors from anon, authenticated;

-- Hide the real author columns. Policies and security-definer functions can
-- still use them; students can't select them.
revoke select on public.posts from anon, authenticated;
grant select (
  id, community_id, type, title, body, media, tags, event_id, poll_ends_at, is_pinned, is_locked, is_removed,
  removed_reason, reaction_counts, likes_count, comments_count, shares_count, saves_count, views_count,
  reports_count, search, created_at, updated_at, edited_at, is_anonymous, anon_name
) on public.posts to authenticated;

revoke select on public.comments from anon, authenticated;
grant select (
  id, post_id, parent_id, depth, body, is_removed, is_deleted, likes_count, replies_count, created_at, edited_at,
  is_anonymous, anon_name
) on public.comments to authenticated;

revoke select on public.reports from anon, authenticated;
grant select (
  id, reporter_id, target_type, target_id, community_id, reason, details, snapshot, status, reviewed_by,
  reviewed_at, resolution_note, created_at
) on public.reports to authenticated;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create or replace function private.anonymous_name()
returns text
language sql
volatile
as $$
  select 'anonymous_'
    || (array['quiet', 'swift', 'brave', 'calm', 'bright', 'clever', 'gentle', 'bold', 'lucky', 'sunny',
              'witty', 'curious', 'mellow', 'cosmic', 'nimble', 'humble', 'misty', 'chill', 'zesty', 'stellar'])
       [1 + floor(random() * 20)::int]
    || '_'
    || (array['otter', 'falcon', 'panda', 'tiger', 'koala', 'heron', 'lynx', 'fox', 'owl', 'dolphin',
              'raven', 'gecko', 'bison', 'ibis', 'orca', 'yak', 'lemur', 'puffin', 'mantis', 'sparrow'])
       [1 + floor(random() * 20)::int]
    || '_'
    || (100 + floor(random() * 900))::int::text;
$$;

create or replace function private.is_private_user(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select p.is_private from public.profiles p where p.id = p_user), false);
$$;

-- You can see a profile if it's public, it's yours, or its owner follows you.
create or replace function private.can_see_profile(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_user = auth.uid()
    or not private.is_private_user(p_user)
    or private.is_platform_admin()
    or exists (select 1 from public.follows f where f.follower_id = p_user and f.following_id = auth.uid());
$$;

create or replace function private.is_post_author(p_post uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.posts p where p.id = p_post and p.author_id = auth.uid());
$$;

-- The author shown on a post: the real person, or the anonymous name for
-- everyone except the author and platform admins.
create or replace function private.post_author(p_post uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p.is_anonymous and p.author_id is distinct from auth.uid() and not private.is_platform_admin() then
      jsonb_build_object('id', null, 'username', null, 'full_name', p.anon_name, 'avatar_url', null,
                         'is_verified', false, 'is_anonymous', true)
    else
      jsonb_build_object('id', a.id, 'username', a.username, 'full_name', a.full_name, 'avatar_url', a.avatar_url,
                         'is_verified', a.is_verified, 'college_id', a.college_id, 'department', a.department,
                         'is_anonymous', p.is_anonymous)
  end
  from public.posts p
  join public.profiles a on a.id = p.author_id
  where p.id = p_post;
$$;

create or replace function private.post_author_id(p_post uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p.is_anonymous and p.author_id is distinct from auth.uid() and not private.is_platform_admin() then null
    else p.author_id
  end
  from public.posts p where p.id = p_post;
$$;

create or replace function private.comment_author(p_comment uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when c.is_deleted or c.is_removed then null
    when c.is_anonymous and c.author_id is distinct from auth.uid() and not private.is_platform_admin() then
      jsonb_build_object('id', null, 'username', null, 'full_name', c.anon_name, 'avatar_url', null,
                         'is_verified', false, 'is_anonymous', true)
    else
      jsonb_build_object('id', a.id, 'username', a.username, 'full_name', a.full_name, 'avatar_url', a.avatar_url,
                         'is_verified', a.is_verified, 'is_anonymous', c.is_anonymous)
  end
  from public.comments c
  join public.profiles a on a.id = c.author_id
  where c.id = p_comment;
$$;

create or replace function private.comment_author_id(p_comment uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when c.is_deleted or c.is_removed then null
    when c.is_anonymous and c.author_id is distinct from auth.uid() and not private.is_platform_admin() then null
    else c.author_id
  end
  from public.comments c where c.id = p_comment;
$$;

create or replace function private.is_comment_author(p_comment uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.comments c where c.id = p_comment and c.author_id = auth.uid());
$$;

-- ---------------------------------------------------------------------------
-- Making content anonymous on insert
-- ---------------------------------------------------------------------------

-- Community posts from private profiles (or marked anonymous) get an alias.
-- Profile posts, announcements and event posts are never anonymous.
create or replace function private.anonymize_post()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.community_id is null or new.type in ('announcement', 'event') then
    new.is_anonymous := false;
    new.anon_name := null;
  elsif new.is_anonymous or private.is_private_user(new.author_id) then
    new.is_anonymous := true;
    new.anon_name := private.anonymous_name();
  else
    new.anon_name := null;
  end if;
  return new;
end;
$$;

create trigger posts_anonymize
  before insert on public.posts
  for each row execute function private.anonymize_post();

create or replace function private.anonymize_comment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.is_anonymous or private.is_private_user(new.author_id) then
    new.is_anonymous := true;
    new.anon_name := private.anonymous_name();
  else
    new.anon_name := null;
  end if;
  return new;
end;
$$;

create trigger comments_anonymize
  before insert on public.comments
  for each row execute function private.anonymize_comment();

-- Room messages from private profiles (or marked anonymous) drop the sender;
-- the link is stored in message_authors. Runs after the other insert
-- triggers (they check the sender first).
create or replace function private.anonymize_message()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type text;
begin
  select type into v_type from public.conversations where id = new.conversation_id;
  if v_type = 'room' and new.kind in ('text', 'image', 'file')
     and auth.uid() is not null
     and (new.is_anonymous or private.is_private_user(auth.uid())) then
    new.is_anonymous := true;
    new.anon_name := private.anonymous_name();
    new.sender_id := null;
  else
    new.is_anonymous := false;
    new.anon_name := null;
  end if;
  return new;
end;
$$;

create trigger messages_zz_anonymize
  before insert on public.messages
  for each row execute function private.anonymize_message();

create or replace function private.record_message_author()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.is_anonymous and auth.uid() is not null then
    insert into public.message_authors (message_id, user_id) values (new.id, auth.uid())
    on conflict do nothing;
    -- Your own message never counts as unread for you.
    update public.conversation_members
       set last_read_at = greatest(last_read_at, new.created_at)
     where conversation_id = new.conversation_id and user_id = auth.uid();
  end if;
  return null;
end;
$$;

create trigger messages_record_author
  after insert on public.messages
  for each row execute function private.record_message_author();

-- The message rate limit also counts anonymous messages (they have no sender_id).
create or replace function private.guard_spam()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_recent integer;
  v_links integer;
begin
  if v_uid is null then
    return new;
  end if;

  if tg_table_name = 'posts' then
    select count(*) into v_recent from public.posts
    where author_id = v_uid and created_at > now() - interval '10 minutes';
    if v_recent >= 10 then
      raise exception 'You''re posting too fast. Try again in a few minutes.' using errcode = 'P0001', hint = 'rate_limited';
    end if;
    if nullif(trim(coalesce(new.body, '')), '') is not null and exists (
      select 1 from public.posts
      where author_id = v_uid and body = new.body and created_at > now() - interval '1 hour'
    ) then
      raise exception 'You already posted this.' using errcode = 'P0001', hint = 'duplicate';
    end if;
  elsif tg_table_name = 'comments' then
    select count(*) into v_recent from public.comments
    where author_id = v_uid and created_at > now() - interval '1 minute';
    if v_recent >= 12 then
      raise exception 'You''re commenting too fast. Take a breather.' using errcode = 'P0001', hint = 'rate_limited';
    end if;
  elsif tg_table_name = 'messages' then
    select count(*) into v_recent from public.messages m
    where m.created_at > now() - interval '10 seconds'
      and (m.sender_id = v_uid or exists (select 1 from public.message_authors ma where ma.message_id = m.id and ma.user_id = v_uid));
    if v_recent >= 20 then
      raise exception 'Slow down a little.' using errcode = 'P0001', hint = 'rate_limited';
    end if;
  end if;

  select count(*) into v_links from regexp_matches(coalesce(new.body, ''), 'https?://', 'g');
  if v_links > 5 then
    raise exception 'Too many links in one go.' using errcode = 'P0001', hint = 'link_spam';
  end if;
  return new;
end;
$$;

-- Reports on anonymous content are flagged so moderators don't see who wrote it.
create or replace function private.flag_anonymous_report()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_anonymous boolean := false;
begin
  if new.target_type = 'post' then
    select is_anonymous into v_anonymous from public.posts where id = new.target_id;
  elsif new.target_type = 'comment' then
    select is_anonymous into v_anonymous from public.comments where id = new.target_id;
  elsif new.target_type = 'message' then
    select is_anonymous into v_anonymous from public.messages where id = new.target_id;
  end if;
  if coalesce(v_anonymous, false) then
    new.snapshot := new.snapshot || jsonb_build_object('anonymous', true);
  end if;
  return new;
end;
$$;

create trigger reports_flag_anonymous
  before insert on public.reports
  for each row execute function private.flag_anonymous_report();

-- ---------------------------------------------------------------------------
-- Policies
-- ---------------------------------------------------------------------------

-- Profile posts from private profiles are visible only to people they follow.
drop policy "Posts are visible to their audience" on public.posts;
create policy "Posts are visible to their audience"
  on public.posts for select to authenticated
  using (
    (not is_removed or author_id = (select auth.uid()) or (community_id is not null and private.is_community_mod(community_id)))
    and (community_id is null or private.can_view_community(community_id))
    and (community_id is not null or private.can_see_profile(author_id))
    and not private.is_blocked_between((select auth.uid()), author_id)
  );

drop policy "Authors add poll options" on public.poll_options;
create policy "Authors add poll options"
  on public.poll_options for insert to authenticated
  with check (private.is_post_author(post_id));

drop policy "Achievements are visible" on public.achievements;
create policy "Achievements are visible"
  on public.achievements for select to authenticated
  using (private.can_see_profile(user_id));

drop policy "Follows are visible" on public.follows;
create policy "Follows are visible"
  on public.follows for select to authenticated
  using (
    follower_id = (select auth.uid())
    or following_id = (select auth.uid())
    or (private.can_see_profile(follower_id) and private.can_see_profile(following_id))
  );

-- Private profiles' reactions count, but they aren't listed.
drop policy "Reactions are visible with the post" on public.post_reactions;
create policy "Reactions are visible with the post"
  on public.post_reactions for select to authenticated
  using (
    exists (select 1 from public.posts p where p.id = post_id)
    and (user_id = (select auth.uid()) or not private.is_private_user(user_id))
  );

-- Guest lists hide private profiles, except from the event's organizers.
drop policy "Registrations are visible with the event" on public.event_registrations;
create policy "Registrations are visible with the event"
  on public.event_registrations for select to authenticated
  using (
    user_id = (select auth.uid())
    or private.can_manage_event(event_id)
    or (private.can_view_event(event_id) and not private.is_private_user(user_id))
  );

-- Anonymous room messages have no sender_id.
drop policy "Members send messages" on public.messages;
create policy "Members send messages"
  on public.messages for insert to authenticated
  with check (
    (sender_id = (select auth.uid()) or (sender_id is null and is_anonymous and anon_name is not null))
    and kind in ('text', 'image', 'file', 'post', 'event')
    and private.is_conversation_member(conversation_id)
  );

drop policy "Edit or unsend your messages" on public.messages;
create policy "Edit or unsend your messages"
  on public.messages for update to authenticated
  using (
    deleted_at is null
    and (
      sender_id = (select auth.uid())
      or exists (select 1 from public.message_authors ma where ma.message_id = id and ma.user_id = (select auth.uid()))
    )
  )
  with check (
    sender_id = (select auth.uid())
    or exists (select 1 from public.message_authors ma where ma.message_id = id and ma.user_id = (select auth.uid()))
  );

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
  case when v.can_see then p.bio end as bio,
  case when v.can_see then p.college_id end as college_id,
  case when v.can_see then p.department end as department,
  case when v.can_see then p.year_of_study end as year_of_study,
  case when v.can_see then p.skills else '{}'::text[] end as skills,
  case when v.can_see then p.interests else '{}'::text[] end as interests,
  p.is_verified,
  case when v.can_see then p.followers_count else 0 end as followers_count,
  case when v.can_see then p.following_count else 0 end as following_count,
  case when v.can_see then p.posts_count else 0 end as posts_count,
  p.onboarded,
  case when v.can_see and not p.is_private then p.last_seen_at end as last_seen_at,
  p.created_at,
  case when c.id is null or not v.can_see then null else
    jsonb_build_object('id', c.id, 'name', c.name, 'short_name', c.short_name, 'slug', c.slug, 'city', c.city)
  end as college,
  exists (select 1 from public.follows f where f.follower_id = auth.uid() and f.following_id = p.id) as is_following,
  exists (select 1 from public.follows f where f.follower_id = p.id and f.following_id = auth.uid()) as follows_me,
  exists (select 1 from public.blocks b where b.blocker_id = auth.uid() and b.blocked_id = p.id) as is_blocked,
  p.is_private,
  v.can_see
from public.profiles p
cross join lateral (select private.can_see_profile(p.id) as can_see) v
left join public.colleges c on c.id = p.college_id;

create or replace view public.post_details
with (security_invoker = on) as
select
  p.id,
  private.post_author_id(p.id) as author_id,
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
  private.post_author(p.id) as author,
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
  ) end as event,
  p.is_anonymous,
  private.is_post_author(p.id) as is_mine
from public.posts p
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
  private.comment_author_id(cm.id) as author_id,
  case when cm.is_deleted or cm.is_removed then null else cm.body end as body,
  cm.is_deleted,
  cm.is_removed,
  cm.likes_count,
  cm.replies_count,
  cm.created_at,
  cm.edited_at,
  private.comment_author(cm.id) as author,
  exists (select 1 from public.comment_likes l where l.comment_id = cm.id and l.user_id = auth.uid()) as liked_by_me,
  cm.is_anonymous,
  private.is_comment_author(cm.id) as is_mine
from public.comments cm;

-- Moderators see who was reported, unless the content was anonymous.
create or replace function private.report_target_user(p_report uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when coalesce((r.snapshot ->> 'anonymous')::boolean, false) and not private.is_platform_admin() then null
    when tu.id is null then null
    else jsonb_build_object('id', tu.id, 'username', tu.username, 'full_name', tu.full_name, 'avatar_url', tu.avatar_url)
  end
  from public.reports r
  left join public.profiles tu on tu.id = r.target_user_id
  where r.id = p_report;
$$;

drop view public.report_details;
create view public.report_details
with (security_invoker = on) as
select
  r.id,
  r.target_type,
  r.target_id,
  r.community_id,
  r.reason,
  r.details,
  r.snapshot,
  r.status,
  r.reviewed_at,
  r.resolution_note,
  r.created_at,
  case when rp.id is null then null else
    jsonb_build_object('id', rp.id, 'username', rp.username, 'full_name', rp.full_name, 'avatar_url', rp.avatar_url)
  end as reporter,
  private.report_target_user(r.id) as target_user,
  (select count(*)::integer from public.reports o where o.target_type = r.target_type and o.target_id = r.target_id) as reports_on_target
from public.reports r
-- A left join: a report must reach moderators even if the reporter blocked them.
left join public.profiles rp on rp.id = r.reporter_id;

-- ---------------------------------------------------------------------------
-- Notifications from anonymous content don't name the actor
-- ---------------------------------------------------------------------------

drop function private.notify(uuid, uuid, text, uuid, uuid, uuid, uuid, uuid, uuid, jsonb);

create function private.notify(
  p_user uuid,
  p_actor uuid,
  p_type text,
  p_post uuid default null,
  p_comment uuid default null,
  p_community uuid default null,
  p_event uuid default null,
  p_conversation uuid default null,
  p_room uuid default null,
  p_data jsonb default '{}'::jsonb,
  p_anonymous boolean default false
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_user is null or p_user = p_actor then
    return;
  end if;
  if p_actor is not null and private.is_blocked_between(p_user, p_actor) then
    return;
  end if;

  insert into public.notifications (user_id, actor_id, type, post_id, comment_id, community_id, event_id, conversation_id, room_id, data)
  values (
    p_user,
    case when p_anonymous then null else p_actor end,
    p_type, p_post, p_comment, p_community, p_event, p_conversation, p_room,
    coalesce(p_data, '{}'::jsonb)
  );
end;
$$;

create or replace function private.notify_on_reaction()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_author uuid;
begin
  select author_id into v_author from public.posts where id = new.post_id;

  if exists (
    select 1 from public.notifications n
    where n.user_id = v_author and n.post_id = new.post_id and n.type = 'post_reaction'
      and n.created_at > now() - interval '1 day'
      and (n.actor_id = new.user_id or (n.actor_id is null and n.data ->> 'reactor' = md5(new.user_id::text)))
  ) then
    return null;
  end if;

  perform private.notify(
    p_user := v_author, p_actor := new.user_id, p_type := 'post_reaction',
    p_post := new.post_id,
    p_data := jsonb_build_object('kind', new.kind, 'reactor', md5(new.user_id::text)),
    p_anonymous := private.is_private_user(new.user_id)
  );
  return null;
end;
$$;

create or replace function private.notify_on_comment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_post public.posts%rowtype;
  v_parent_author uuid;
  v_data jsonb := jsonb_build_object('snippet', private.snippet(new.body))
    || case when new.is_anonymous then jsonb_build_object('alias', new.anon_name) else '{}'::jsonb end;
  v_mentioned uuid;
begin
  select * into v_post from public.posts where id = new.post_id;

  if new.parent_id is not null then
    select author_id into v_parent_author from public.comments where id = new.parent_id;
    perform private.notify(
      p_user := v_parent_author, p_actor := new.author_id, p_type := 'comment_reply',
      p_post := new.post_id, p_comment := new.id, p_community := v_post.community_id, p_data := v_data,
      p_anonymous := new.is_anonymous
    );
  end if;

  if v_post.author_id is distinct from v_parent_author then
    perform private.notify(
      p_user := v_post.author_id, p_actor := new.author_id, p_type := 'post_comment',
      p_post := new.post_id, p_comment := new.id, p_community := v_post.community_id, p_data := v_data,
      p_anonymous := new.is_anonymous
    );
  end if;

  for v_mentioned in select * from private.mentioned_profiles(new.body) loop
    if v_mentioned is distinct from v_post.author_id and v_mentioned is distinct from v_parent_author then
      perform private.notify(
        p_user := v_mentioned, p_actor := new.author_id, p_type := 'mention',
        p_post := new.post_id, p_comment := new.id, p_community := v_post.community_id, p_data := v_data,
        p_anonymous := new.is_anonymous
      );
    end if;
  end loop;

  insert into public.notifications (user_id, actor_id, type, post_id, comment_id, community_id, data)
  select f.user_id, case when new.is_anonymous then null else new.author_id end, 'thread_activity',
         new.post_id, new.id, v_post.community_id, v_data
  from public.post_follows f
  where f.post_id = new.post_id
    and f.user_id <> new.author_id
    and f.user_id is distinct from v_post.author_id
    and f.user_id is distinct from v_parent_author
    and f.user_id not in (select * from private.mentioned_profiles(new.body))
    and not private.is_blocked_between(f.user_id, new.author_id);

  return null;
end;
$$;

create or replace function private.notify_on_post()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_mentioned uuid;
  v_data jsonb := jsonb_build_object('snippet', private.snippet(coalesce(new.title, new.body)))
    || case when new.is_anonymous then jsonb_build_object('alias', new.anon_name) else '{}'::jsonb end;
begin
  for v_mentioned in select * from private.mentioned_profiles(concat_ws(' ', new.title, new.body)) loop
    perform private.notify(
      p_user := v_mentioned, p_actor := new.author_id, p_type := 'mention',
      p_post := new.id, p_community := new.community_id, p_data := v_data,
      p_anonymous := new.is_anonymous
    );
  end loop;

  if new.type = 'announcement' and new.community_id is not null then
    insert into public.notifications (user_id, actor_id, type, post_id, community_id, data)
    select m.user_id, new.author_id, 'announcement', new.id, new.community_id, v_data
    from public.community_members m
    where m.community_id = new.community_id
      and m.status = 'active'
      and m.user_id <> new.author_id
      and not private.is_blocked_between(m.user_id, new.author_id);
  end if;
  return null;
end;
$$;

revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated, service_role;
