-- Quad: full database setup (all migrations + college seed).
-- Paste into Supabase Dashboard > SQL Editor and run once on a fresh project.
-- Generated from supabase/migrations and supabase/seed.sql.

-- ===== 20260928000100_foundation.sql =====
-- Foundation: extensions, the private helper schema and shared utilities.
--
-- Functions in `private` are used by RLS policies and triggers. The schema is
-- not exposed through the Data API, so none of them can be called as RPCs.

create schema if not exists extensions;
create extension if not exists pg_trgm with schema extensions;

create schema if not exists private;
grant usage on schema private to anon, authenticated, service_role;

-- Keeps `updated_at` current. Attach with `before update of <columns>` so that
-- counter updates made by triggers don't bump it.
create or replace function private.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- Parses a uuid without raising. Used to read ids out of storage paths and
-- realtime topics, which are user-controlled strings.
create or replace function private.try_uuid(value text)
returns uuid
language sql
immutable
as $$
  select case
    when value ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then value::uuid
  end;
$$;

-- Escapes LIKE wildcards in user input and wraps it for a contains-match.
create or replace function private.contains_pattern(value text)
returns text
language sql
immutable
as $$
  select '%' || replace(replace(replace(trim(coalesce(value, '')), '\', '\\'), '%', '\%'), '_', '\_') || '%';
$$;

-- Same as contains_pattern, for a starts-with match.
create or replace function private.prefix_pattern(value text)
returns text
language sql
immutable
as $$
  select replace(replace(replace(trim(coalesce(value, '')), '\', '\\'), '%', '\%'), '_', '\_') || '%';
$$;

create or replace function private.slugify(value text)
returns text
language sql
immutable
as $$
  select trim(both '-' from regexp_replace(lower(coalesce(value, '')), '[^a-z0-9]+', '-', 'g'));
$$;


-- ===== 20260928000200_profiles_colleges.sql =====
-- Colleges, student profiles, follows, blocks and achievements.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table public.colleges (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 160),
  short_name text check (char_length(short_name) <= 40),
  slug text not null unique check (slug ~ '^[a-z0-9-]{2,80}$'),
  city text check (char_length(city) <= 80),
  state text check (char_length(state) <= 80),
  country text not null default 'India',
  type text check (type in ('public', 'private', 'deemed', 'autonomous', 'other')),
  established smallint check (established between 1700 and 2100),
  website text check (char_length(website) <= 300),
  logo_url text,
  cover_url text,
  description text check (char_length(description) <= 2000),
  is_verified boolean not null default false,
  created_by uuid default auth.uid() references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);

create index colleges_name_trgm_idx on public.colleges using gin (name extensions.gin_trgm_ops);
create index colleges_state_idx on public.colleges (state);

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text not null unique check (username ~ '^[a-z0-9_.]{3,24}$'),
  full_name text not null check (char_length(full_name) between 1 and 80),
  avatar_url text,
  bio text check (char_length(bio) <= 280),
  college_id uuid references public.colleges (id) on delete set null,
  department text check (char_length(department) <= 80),
  year_of_study smallint check (year_of_study between 1 and 7),
  skills text[] not null default '{}' check (cardinality(skills) <= 30),
  interests text[] not null default '{}' check (cardinality(interests) <= 30),
  is_verified boolean not null default false,
  role text not null default 'user' check (role in ('user', 'admin')),
  followers_count integer not null default 0,
  following_count integer not null default 0,
  posts_count integer not null default 0,
  onboarded boolean not null default false,
  last_seen_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index profiles_college_idx on public.profiles (college_id);
create index profiles_full_name_trgm_idx on public.profiles using gin (full_name extensions.gin_trgm_ops);
create index profiles_username_trgm_idx on public.profiles using gin (username extensions.gin_trgm_ops);
create index profiles_interests_idx on public.profiles using gin (interests);

create trigger profiles_touch_updated_at
  before update of username, full_name, avatar_url, bio, college_id, department, year_of_study, skills, interests
  on public.profiles
  for each row execute function private.touch_updated_at();

create table public.follows (
  follower_id uuid not null references public.profiles (id) on delete cascade,
  following_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, following_id),
  check (follower_id <> following_id)
);

create index follows_following_idx on public.follows (following_id, created_at desc);

create table public.blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

create index blocks_blocked_idx on public.blocks (blocked_id);

create table public.achievements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  title text not null check (char_length(title) between 2 and 120),
  description text check (char_length(description) <= 1000),
  category text not null default 'other' check (
    category in ('hackathon', 'competition', 'academic', 'sports', 'cultural', 'certification', 'internship', 'research', 'leadership', 'other')
  ),
  issuer text check (char_length(issuer) <= 120),
  achieved_on date,
  url text check (char_length(url) <= 500),
  created_at timestamptz not null default now()
);

create index achievements_user_idx on public.achievements (user_id, achieved_on desc nulls last);

-- ---------------------------------------------------------------------------
-- Helpers used by policies across the schema
-- ---------------------------------------------------------------------------

create or replace function private.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin');
$$;

-- True when either user has blocked the other.
create or replace function private.is_blocked_between(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.blocks bl
    where (bl.blocker_id = a and bl.blocked_id = b)
       or (bl.blocker_id = b and bl.blocked_id = a)
  );
$$;

-- True when `other` has blocked the signed-in user.
create or replace function private.is_blocked_by(other uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.blocks bl where bl.blocker_id = other and bl.blocked_id = auth.uid());
$$;

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------

-- Every auth user gets a profile. The username comes from sign-up metadata when
-- present, otherwise from the email, and is made unique with a numeric suffix.
create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text;
  v_base text;
  v_username text;
  v_suffix integer := 0;
begin
  v_name := coalesce(
    nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
    nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
    'Student'
  );
  v_base := lower(regexp_replace(
    coalesce(nullif(new.raw_user_meta_data ->> 'username', ''), split_part(coalesce(new.email, ''), '@', 1), ''),
    '[^a-zA-Z0-9_.]', '', 'g'
  ));
  if char_length(v_base) < 3 then
    v_base := v_base || 'student';
  end if;
  v_base := left(v_base, 20);
  v_username := v_base;

  while exists (select 1 from public.profiles where username = v_username) loop
    v_suffix := v_suffix + 1;
    v_username := v_base || v_suffix::text;
  end loop;

  insert into public.profiles (id, username, full_name)
  values (new.id, v_username, left(v_name, 80));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

create or replace function private.on_follow_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    update public.profiles set followers_count = followers_count + 1 where id = new.following_id;
    update public.profiles set following_count = following_count + 1 where id = new.follower_id;
  else
    update public.profiles set followers_count = greatest(followers_count - 1, 0) where id = old.following_id;
    update public.profiles set following_count = greatest(following_count - 1, 0) where id = old.follower_id;
  end if;
  return null;
end;
$$;

create trigger follows_counters
  after insert or delete on public.follows
  for each row execute function private.on_follow_change();

-- Blocking someone also removes follows in both directions.
create or replace function private.on_block_created()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.follows
  where (follower_id = new.blocker_id and following_id = new.blocked_id)
     or (follower_id = new.blocked_id and following_id = new.blocker_id);
  return null;
end;
$$;

create trigger blocks_cleanup
  after insert on public.blocks
  for each row execute function private.on_block_created();

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

alter table public.colleges enable row level security;
alter table public.profiles enable row level security;
alter table public.follows enable row level security;
alter table public.blocks enable row level security;
alter table public.achievements enable row level security;

create policy "Colleges are visible to students"
  on public.colleges for select to authenticated
  using (true);

create policy "Students can add a missing college"
  on public.colleges for insert to authenticated
  with check (created_by = (select auth.uid()) and is_verified = false);

create policy "Admins edit colleges"
  on public.colleges for update to authenticated
  using (private.is_platform_admin())
  with check (private.is_platform_admin());

create policy "Admins delete colleges"
  on public.colleges for delete to authenticated
  using (private.is_platform_admin());

create policy "Profiles are visible unless they blocked you"
  on public.profiles for select to authenticated
  using (not private.is_blocked_by(id));

create policy "Students edit their own profile"
  on public.profiles for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- Profiles are created by the auth trigger; students may only edit these
-- columns (role, verification and counters are off limits).
revoke insert, update, delete on public.profiles from anon, authenticated;
grant update (
  username, full_name, avatar_url, bio, college_id, department, year_of_study,
  skills, interests, onboarded, last_seen_at
) on public.profiles to authenticated;

create policy "Follows are visible"
  on public.follows for select to authenticated
  using (true);

create policy "Follow people"
  on public.follows for insert to authenticated
  with check (follower_id = (select auth.uid()) and not private.is_blocked_between(follower_id, following_id));

create policy "Unfollow people"
  on public.follows for delete to authenticated
  using (follower_id = (select auth.uid()));

create policy "See who you blocked"
  on public.blocks for select to authenticated
  using (blocker_id = (select auth.uid()));

create policy "Block people"
  on public.blocks for insert to authenticated
  with check (blocker_id = (select auth.uid()));

create policy "Unblock people"
  on public.blocks for delete to authenticated
  using (blocker_id = (select auth.uid()));

create policy "Achievements are visible"
  on public.achievements for select to authenticated
  using (true);

create policy "Add your achievements"
  on public.achievements for insert to authenticated
  with check (user_id = (select auth.uid()));

create policy "Edit your achievements"
  on public.achievements for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy "Delete your achievements"
  on public.achievements for delete to authenticated
  using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- RPCs
-- ---------------------------------------------------------------------------

create or replace function public.is_username_available(p_username text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_username ~ '^[a-z0-9_.]{3,24}$'
     and not exists (
       select 1 from public.profiles p
       where p.username = p_username and p.id is distinct from auth.uid()
     );
$$;


-- ===== 20260928000300_communities.sql =====
-- Communities and their members.
--
-- Community metadata is visible to every student so private communities can be
-- discovered and requested. Their content (posts, rooms, member lists) is only
-- visible to members; see private.can_view_community.

create table public.communities (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$'),
  name text not null check (char_length(name) between 3 and 60),
  tagline text check (char_length(tagline) <= 120),
  description text check (char_length(description) <= 2000),
  category text not null default 'other' check (
    category in ('college', 'department', 'technical', 'club', 'hackathon', 'sports', 'career', 'hobby', 'event', 'other')
  ),
  college_id uuid references public.colleges (id) on delete set null,
  avatar_url text,
  banner_url text,
  color smallint not null default 0 check (color between 0 and 11),
  visibility text not null default 'public' check (visibility in ('public', 'private')),
  rules jsonb not null default '[]'::jsonb check (jsonb_typeof(rules) = 'array'),
  tags text[] not null default '{}' check (cardinality(tags) <= 10),
  created_by uuid default auth.uid() references public.profiles (id) on delete set null,
  members_count integer not null default 0,
  posts_count integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index communities_category_idx on public.communities (category, members_count desc);
create index communities_college_idx on public.communities (college_id);
create index communities_members_idx on public.communities (members_count desc);
create index communities_name_trgm_idx on public.communities using gin (name extensions.gin_trgm_ops);
create index communities_tags_idx on public.communities using gin (tags);

create trigger communities_touch_updated_at
  before update of name, tagline, description, category, college_id, avatar_url, banner_url, color, visibility, rules, tags
  on public.communities
  for each row execute function private.touch_updated_at();

create table public.community_members (
  community_id uuid not null references public.communities (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'admin', 'moderator', 'member')),
  status text not null default 'active' check (status in ('active', 'pending', 'banned')),
  joined_at timestamptz not null default now(),
  primary key (community_id, user_id)
);

create index community_members_user_idx on public.community_members (user_id, status);
create index community_members_role_idx on public.community_members (community_id, role) where status = 'active';

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create or replace function private.community_role(p_community uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select m.role
  from public.community_members m
  where m.community_id = p_community and m.user_id = auth.uid() and m.status = 'active';
$$;

create or replace function private.is_community_member(p_community uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.community_members m
    where m.community_id = p_community and m.user_id = auth.uid() and m.status = 'active'
  );
$$;

-- Owners, admins and moderators (and platform admins).
create or replace function private.is_community_mod(p_community uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_platform_admin() or exists (
    select 1 from public.community_members m
    where m.community_id = p_community
      and m.user_id = auth.uid()
      and m.status = 'active'
      and m.role in ('owner', 'admin', 'moderator')
  );
$$;

-- Owners and admins (and platform admins).
create or replace function private.is_community_admin(p_community uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_platform_admin() or exists (
    select 1 from public.community_members m
    where m.community_id = p_community
      and m.user_id = auth.uid()
      and m.status = 'active'
      and m.role in ('owner', 'admin')
  );
$$;

create or replace function private.can_view_community(p_community uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.communities c
    where c.id = p_community
      and (c.visibility = 'public' or private.is_community_member(c.id) or private.is_platform_admin())
  );
$$;

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------

create or replace function private.on_community_created()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.created_by is not null then
    insert into public.community_members (community_id, user_id, role, status)
    values (new.id, new.created_by, 'owner', 'active')
    on conflict (community_id, user_id) do update set role = 'owner', status = 'active';
  end if;
  return null;
end;
$$;

create trigger communities_add_owner
  after insert on public.communities
  for each row execute function private.on_community_created();

create or replace function private.refresh_member_count()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_community uuid;
begin
  if tg_op = 'DELETE' then
    v_community := old.community_id;
  else
    v_community := new.community_id;
  end if;

  update public.communities c
     set members_count = (
       select count(*) from public.community_members m
       where m.community_id = v_community and m.status = 'active'
     )
   where c.id = v_community;
  return null;
end;
$$;

create trigger community_members_count
  after insert or update of status or delete on public.community_members
  for each row execute function private.refresh_member_count();

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

alter table public.communities enable row level security;
alter table public.community_members enable row level security;

create policy "Communities are discoverable"
  on public.communities for select to authenticated
  using (true);

create policy "Students create communities"
  on public.communities for insert to authenticated
  with check (created_by = (select auth.uid()));

create policy "Community admins edit their community"
  on public.communities for update to authenticated
  using (private.is_community_admin(id))
  with check (private.is_community_admin(id));

create policy "Owners delete their community"
  on public.communities for delete to authenticated
  using (private.community_role(id) = 'owner' or private.is_platform_admin());

revoke insert, update on public.communities from anon, authenticated;
grant insert (
  slug, name, tagline, description, category, college_id, avatar_url, banner_url, color, visibility, rules, tags, created_by
) on public.communities to authenticated;
grant update (
  name, tagline, description, category, college_id, avatar_url, banner_url, color, visibility, rules, tags
) on public.communities to authenticated;

-- Memberships change only through the RPCs below.
create policy "Members are visible with the community"
  on public.community_members for select to authenticated
  using (user_id = (select auth.uid()) or private.can_view_community(community_id));

revoke insert, update, delete on public.community_members from anon, authenticated;

-- ---------------------------------------------------------------------------
-- RPCs
-- ---------------------------------------------------------------------------

-- Joins a community. Public communities are joined immediately; private ones
-- create a pending request. Returns the resulting membership status.
create or replace function public.join_community(p_community uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_visibility text;
  v_status text;
begin
  if v_uid is null then
    raise exception 'Sign in to join communities' using errcode = '28000';
  end if;

  select visibility into v_visibility from public.communities where id = p_community;
  if v_visibility is null then
    raise exception 'Community not found' using errcode = 'P0002';
  end if;

  select status into v_status
  from public.community_members
  where community_id = p_community and user_id = v_uid;

  if v_status = 'banned' then
    raise exception 'You can''t join this community' using errcode = '42501';
  elsif v_status is not null then
    return v_status;
  end if;

  v_status := case when v_visibility = 'private' then 'pending' else 'active' end;
  insert into public.community_members (community_id, user_id, role, status)
  values (p_community, v_uid, 'member', v_status);
  return v_status;
end;
$$;

-- Leaves a community or withdraws a pending request.
create or replace function public.leave_community(p_community uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
begin
  if v_uid is null then
    raise exception 'Not signed in' using errcode = '28000';
  end if;

  select role into v_role
  from public.community_members
  where community_id = p_community and user_id = v_uid and status <> 'banned';

  if v_role = 'owner' then
    raise exception 'Transfer ownership before leaving your community' using errcode = 'P0001';
  end if;

  delete from public.community_members
  where community_id = p_community and user_id = v_uid and status <> 'banned';
end;
$$;

-- Owners and admins promote or demote members. Only the owner manages admins.
create or replace function public.set_member_role(p_community uuid, p_user uuid, p_role text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_my_role text := coalesce(private.community_role(p_community), '');
  v_is_admin boolean := private.is_platform_admin();
  v_target_role text;
begin
  if p_role not in ('admin', 'moderator', 'member') then
    raise exception 'Unknown role' using errcode = '22023';
  end if;
  if v_my_role not in ('owner', 'admin') and not v_is_admin then
    raise exception 'Only community admins can change roles' using errcode = '42501';
  end if;

  select role into v_target_role
  from public.community_members
  where community_id = p_community and user_id = p_user and status = 'active';

  if v_target_role is null then
    raise exception 'That person isn''t a member' using errcode = 'P0002';
  elsif v_target_role = 'owner' then
    raise exception 'The owner''s role can''t be changed' using errcode = '42501';
  elsif v_my_role = 'admin' and not v_is_admin and (v_target_role = 'admin' or p_role = 'admin') then
    raise exception 'Only the owner can manage admins' using errcode = '42501';
  end if;

  update public.community_members
     set role = p_role
   where community_id = p_community and user_id = p_user;
end;
$$;

-- Moderators approve requests, ban and unban. Staff can only be banned by
-- someone ranked above them.
create or replace function public.set_member_status(p_community uuid, p_user uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_my_role text := coalesce(private.community_role(p_community), '');
  v_is_admin boolean := private.is_platform_admin();
  v_target_role text;
  v_rank_me integer;
  v_rank_target integer;
begin
  if p_status not in ('active', 'banned') then
    raise exception 'Unknown status' using errcode = '22023';
  end if;
  if not private.is_community_mod(p_community) then
    raise exception 'Only moderators can do that' using errcode = '42501';
  end if;
  if p_user = auth.uid() then
    raise exception 'You can''t change your own membership' using errcode = '42501';
  end if;

  select role into v_target_role
  from public.community_members
  where community_id = p_community and user_id = p_user;

  v_rank_me := case v_my_role when 'owner' then 4 when 'admin' then 3 when 'moderator' then 2 else 1 end;
  v_rank_target := case v_target_role when 'owner' then 4 when 'admin' then 3 when 'moderator' then 2 else 1 end;
  if not v_is_admin and v_rank_target >= v_rank_me then
    raise exception 'You can''t moderate someone at your level' using errcode = '42501';
  end if;

  if v_target_role is null then
    if p_status = 'banned' then
      insert into public.community_members (community_id, user_id, role, status)
      values (p_community, p_user, 'member', 'banned');
    else
      raise exception 'That person isn''t in this community' using errcode = 'P0002';
    end if;
  else
    update public.community_members
       set status = p_status,
           role = case when p_status = 'banned' then 'member' else role end
     where community_id = p_community and user_id = p_user;
  end if;
end;
$$;

-- Removes a member (a kick; they can join again) or declines a request.
create or replace function public.remove_member(p_community uuid, p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_my_role text := coalesce(private.community_role(p_community), '');
  v_target_role text;
begin
  if not private.is_community_mod(p_community) then
    raise exception 'Only moderators can do that' using errcode = '42501';
  end if;

  select role into v_target_role
  from public.community_members
  where community_id = p_community and user_id = p_user;

  if v_target_role = 'owner'
     or (v_target_role in ('admin', 'moderator') and v_my_role not in ('owner', 'admin') and not private.is_platform_admin())
     or (v_target_role = 'admin' and v_my_role = 'admin') then
    raise exception 'You can''t remove this member' using errcode = '42501';
  end if;

  delete from public.community_members
  where community_id = p_community and user_id = p_user and status <> 'banned';
end;
$$;

-- Hands the community to another active member. The old owner becomes an admin.
create or replace function public.transfer_community_ownership(p_community uuid, p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if private.community_role(p_community) is distinct from 'owner' then
    raise exception 'Only the owner can transfer ownership' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.community_members
    where community_id = p_community and user_id = p_user and status = 'active'
  ) then
    raise exception 'The new owner must be an active member' using errcode = 'P0002';
  end if;

  update public.community_members set role = 'admin'
   where community_id = p_community and user_id = auth.uid();
  update public.community_members set role = 'owner'
   where community_id = p_community and user_id = p_user;
end;
$$;


-- ===== 20260928000400_events.sql =====
-- Events, registrations (with capacity and waitlist) and organizer updates.
--
-- The online meeting link is write-only for clients: it's never selectable
-- directly and is handed out by event_meeting_link() to people who registered.

create table public.events (
  id uuid primary key default gen_random_uuid(),
  organizer_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  community_id uuid references public.communities (id) on delete set null,
  college_id uuid references public.colleges (id) on delete set null,
  title text not null check (char_length(title) between 3 and 120),
  description text check (char_length(description) <= 5000),
  category text not null default 'other' check (
    category in ('hackathon', 'workshop', 'conference', 'club', 'cultural', 'sports', 'competition', 'webinar', 'placement', 'meetup', 'other')
  ),
  poster_url text,
  poster_theme jsonb,
  starts_at timestamptz not null,
  ends_at timestamptz,
  mode text not null default 'in_person' check (mode in ('in_person', 'online', 'hybrid')),
  venue text check (char_length(venue) <= 160),
  address text check (char_length(address) <= 300),
  meeting_url text check (char_length(meeting_url) <= 500),
  capacity integer check (capacity is null or capacity > 0),
  registration_deadline timestamptz,
  registrations_count integer not null default 0,
  waitlist_count integer not null default 0,
  visibility text not null default 'public' check (visibility in ('public', 'community')),
  tags text[] not null default '{}' check (cardinality(tags) <= 10),
  is_cancelled boolean not null default false,
  reminder_day_sent boolean not null default false,
  reminder_hour_sent boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at is null or ends_at >= starts_at),
  check (visibility = 'public' or community_id is not null)
);

create index events_starts_idx on public.events (starts_at);
create index events_community_idx on public.events (community_id, starts_at);
create index events_college_idx on public.events (college_id, starts_at);
create index events_category_idx on public.events (category, starts_at);
create index events_organizer_idx on public.events (organizer_id, starts_at desc);
create index events_title_trgm_idx on public.events using gin (title extensions.gin_trgm_ops);

create trigger events_touch_updated_at
  before update of title, description, category, poster_url, poster_theme, starts_at, ends_at, mode, venue, address,
    meeting_url, capacity, registration_deadline, visibility, tags, is_cancelled
  on public.events
  for each row execute function private.touch_updated_at();

create table public.event_registrations (
  event_id uuid not null references public.events (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'going' check (status in ('going', 'waitlist', 'cancelled', 'attended')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (event_id, user_id)
);

create index event_registrations_user_idx on public.event_registrations (user_id, status);
create index event_registrations_status_idx on public.event_registrations (event_id, status, created_at);

create table public.event_updates (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events (id) on delete cascade,
  author_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now()
);

create index event_updates_event_idx on public.event_updates (event_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create or replace function private.can_view_event(p_event uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.events e
    where e.id = p_event
      and (
        e.visibility = 'public'
        or e.organizer_id = auth.uid()
        or (e.community_id is not null and private.is_community_member(e.community_id))
        or private.is_platform_admin()
      )
  );
$$;

create or replace function private.can_manage_event(p_event uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.events e
    where e.id = p_event
      and (
        e.organizer_id = auth.uid()
        or (e.community_id is not null and private.is_community_mod(e.community_id))
        or private.is_platform_admin()
      )
  );
$$;

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------

create or replace function private.refresh_event_counts()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event uuid;
begin
  if tg_op = 'DELETE' then
    v_event := old.event_id;
  else
    v_event := new.event_id;
  end if;

  update public.events e
     set registrations_count = (
           select count(*) from public.event_registrations r
           where r.event_id = v_event and r.status in ('going', 'attended')
         ),
         waitlist_count = (
           select count(*) from public.event_registrations r
           where r.event_id = v_event and r.status = 'waitlist'
         )
   where e.id = v_event;
  return null;
end;
$$;

create trigger event_registrations_counts
  after insert or update of status or delete on public.event_registrations
  for each row execute function private.refresh_event_counts();

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

alter table public.events enable row level security;
alter table public.event_registrations enable row level security;
alter table public.event_updates enable row level security;

create policy "Events are visible to their audience"
  on public.events for select to authenticated
  using (
    visibility = 'public'
    or organizer_id = (select auth.uid())
    or (community_id is not null and private.is_community_member(community_id))
  );

-- Anyone can host an event of their own; attaching one to a community needs
-- moderator rights there.
create policy "Students create events"
  on public.events for insert to authenticated
  with check (
    organizer_id = (select auth.uid())
    and (community_id is null or private.is_community_mod(community_id))
  );

create policy "Organizers edit their events"
  on public.events for update to authenticated
  using (organizer_id = (select auth.uid()) or (community_id is not null and private.is_community_mod(community_id)))
  with check (organizer_id = (select auth.uid()) or (community_id is not null and private.is_community_mod(community_id)));

create policy "Organizers delete their events"
  on public.events for delete to authenticated
  using (
    organizer_id = (select auth.uid())
    or (community_id is not null and private.is_community_mod(community_id))
    or private.is_platform_admin()
  );

revoke select, insert, update on public.events from anon, authenticated;
grant select (
  id, organizer_id, community_id, college_id, title, description, category, poster_url, poster_theme, starts_at,
  ends_at, mode, venue, address, capacity, registration_deadline, registrations_count, waitlist_count, visibility,
  tags, is_cancelled, created_at, updated_at
) on public.events to authenticated;
grant insert (
  organizer_id, community_id, college_id, title, description, category, poster_url, poster_theme, starts_at, ends_at,
  mode, venue, address, meeting_url, capacity, registration_deadline, visibility, tags
) on public.events to authenticated;
grant update (
  community_id, college_id, title, description, category, poster_url, poster_theme, starts_at, ends_at, mode, venue,
  address, meeting_url, capacity, registration_deadline, visibility, tags, is_cancelled
) on public.events to authenticated;

-- Guest lists are visible to anyone who can see the event. Registrations
-- change only through the RPCs below.
create policy "Registrations are visible with the event"
  on public.event_registrations for select to authenticated
  using (user_id = (select auth.uid()) or private.can_view_event(event_id));

revoke insert, update, delete on public.event_registrations from anon, authenticated;

create policy "Updates are visible with the event"
  on public.event_updates for select to authenticated
  using (private.can_view_event(event_id));

create policy "Organizers post updates"
  on public.event_updates for insert to authenticated
  with check (author_id = (select auth.uid()) and private.can_manage_event(event_id));

create policy "Organizers delete updates"
  on public.event_updates for delete to authenticated
  using (author_id = (select auth.uid()) or private.can_manage_event(event_id));

-- ---------------------------------------------------------------------------
-- RPCs
-- ---------------------------------------------------------------------------

-- Registers the signed-in student. When the event is full they join the
-- waitlist instead. The event row is locked so the capacity can't be exceeded
-- by concurrent registrations. Returns the resulting status.
create or replace function public.register_for_event(p_event uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_event public.events%rowtype;
  v_existing text;
  v_status text;
begin
  if v_uid is null then
    raise exception 'Sign in to register' using errcode = '28000';
  end if;

  select * into v_event from public.events where id = p_event for update;
  if not found or not private.can_view_event(p_event) then
    raise exception 'Event not found' using errcode = 'P0002';
  end if;
  if v_event.is_cancelled then
    raise exception 'This event was cancelled' using errcode = 'P0001';
  end if;
  if coalesce(v_event.ends_at, v_event.starts_at) < now() then
    raise exception 'This event has already ended' using errcode = 'P0001';
  end if;
  if v_event.registration_deadline is not null and v_event.registration_deadline < now() then
    raise exception 'Registrations are closed' using errcode = 'P0001';
  end if;
  if private.is_blocked_between(v_uid, v_event.organizer_id) then
    raise exception 'You can''t register for this event' using errcode = '42501';
  end if;

  select status into v_existing
  from public.event_registrations
  where event_id = p_event and user_id = v_uid;

  if v_existing in ('going', 'waitlist', 'attended') then
    return v_existing;
  end if;

  if v_event.capacity is not null and v_event.registrations_count >= v_event.capacity then
    v_status := 'waitlist';
  else
    v_status := 'going';
  end if;

  insert into public.event_registrations (event_id, user_id, status)
  values (p_event, v_uid, v_status)
  on conflict (event_id, user_id) do update
    set status = excluded.status, created_at = now(), updated_at = now();
  return v_status;
end;
$$;

-- Cancels the signed-in student's registration. A freed seat goes to the
-- longest-waiting person on the waitlist.
create or replace function public.cancel_event_registration(p_event uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_previous text;
  v_next uuid;
begin
  if v_uid is null then
    raise exception 'Not signed in' using errcode = '28000';
  end if;

  perform 1 from public.events where id = p_event for update;

  select status into v_previous
  from public.event_registrations
  where event_id = p_event and user_id = v_uid;

  if v_previous is null or v_previous not in ('going', 'waitlist') then
    return;
  end if;

  update public.event_registrations
     set status = 'cancelled', updated_at = now()
   where event_id = p_event and user_id = v_uid;

  if v_previous = 'going' then
    select user_id into v_next
    from public.event_registrations
    where event_id = p_event and status = 'waitlist'
    order by created_at
    limit 1;

    if v_next is not null then
      update public.event_registrations
         set status = 'going', updated_at = now()
       where event_id = p_event and user_id = v_next;
    end if;
  end if;
end;
$$;

-- Organizers check people in, move them off the waitlist or remove them.
create or replace function public.set_registration_status(p_event uuid, p_user uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_status not in ('going', 'waitlist', 'attended', 'cancelled') then
    raise exception 'Unknown status' using errcode = '22023';
  end if;
  if not private.can_manage_event(p_event) then
    raise exception 'Only organizers can manage registrations' using errcode = '42501';
  end if;

  update public.event_registrations
     set status = p_status, updated_at = now()
   where event_id = p_event and user_id = p_user;

  if not found then
    raise exception 'Registration not found' using errcode = 'P0002';
  end if;
end;
$$;

-- The meeting link, for organizers and registered attendees only.
create or replace function public.event_meeting_link(p_event uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select e.meeting_url
  from public.events e
  where e.id = p_event
    and (
      private.can_manage_event(e.id)
      or exists (
        select 1 from public.event_registrations r
        where r.event_id = e.id and r.user_id = auth.uid() and r.status in ('going', 'attended')
      )
    );
$$;


-- ===== 20260928000500_posts.sql =====
-- Posts (text, media, questions, polls, announcements, events, achievements
-- and reels), reactions, comments, saves and discussion follows.

create table public.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  community_id uuid references public.communities (id) on delete cascade,
  type text not null default 'text' check (
    type in ('text', 'image', 'video', 'question', 'poll', 'announcement', 'event', 'achievement', 'reel')
  ),
  title text check (char_length(title) <= 300),
  body text check (char_length(body) <= 10000),
  media jsonb not null default '[]'::jsonb check (jsonb_typeof(media) = 'array' and jsonb_array_length(media) <= 10),
  tags text[] not null default '{}' check (cardinality(tags) <= 10),
  event_id uuid references public.events (id) on delete set null,
  poll_ends_at timestamptz,
  is_pinned boolean not null default false,
  is_locked boolean not null default false,
  is_removed boolean not null default false,
  removed_reason text,
  reaction_counts jsonb not null default '{}'::jsonb,
  likes_count integer not null default 0,
  comments_count integer not null default 0,
  shares_count integer not null default 0,
  saves_count integer not null default 0,
  views_count integer not null default 0,
  reports_count integer not null default 0,
  search tsvector generated always as (
    setweight(to_tsvector('simple', coalesce(title, '')), 'A') ||
    setweight(to_tsvector('simple', coalesce(body, '')), 'B')
  ) stored,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  edited_at timestamptz,
  check (title is not null or body is not null or jsonb_array_length(media) > 0 or event_id is not null)
);

create index posts_created_idx on public.posts (created_at desc) where not is_removed;
create index posts_community_idx on public.posts (community_id, created_at desc);
create index posts_author_idx on public.posts (author_id, created_at desc);
create index posts_type_idx on public.posts (type, created_at desc) where not is_removed;
create index posts_search_idx on public.posts using gin (search);
create index posts_tags_idx on public.posts using gin (tags);
create index posts_title_trgm_idx on public.posts using gin (title extensions.gin_trgm_ops);

create trigger posts_touch_updated_at
  before update of title, body, media, tags
  on public.posts
  for each row execute function private.touch_updated_at();

create table public.poll_options (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts (id) on delete cascade,
  label text not null check (char_length(label) between 1 and 80),
  position smallint not null default 0,
  votes_count integer not null default 0
);

create index poll_options_post_idx on public.poll_options (post_id, position);

create table public.poll_votes (
  post_id uuid not null references public.posts (id) on delete cascade,
  option_id uuid not null references public.poll_options (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create table public.post_reactions (
  post_id uuid not null references public.posts (id) on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  kind text not null default 'like' check (kind in ('like', 'fire', 'haha', 'idea', 'clap')),
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create index post_reactions_user_idx on public.post_reactions (user_id, created_at desc);

create table public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts (id) on delete cascade,
  author_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  parent_id uuid references public.comments (id) on delete cascade,
  depth smallint not null default 0,
  body text not null check (char_length(body) between 1 and 5000),
  is_removed boolean not null default false,
  is_deleted boolean not null default false,
  likes_count integer not null default 0,
  replies_count integer not null default 0,
  created_at timestamptz not null default now(),
  edited_at timestamptz
);

create index comments_post_idx on public.comments (post_id, created_at);
create index comments_parent_idx on public.comments (parent_id);
create index comments_author_idx on public.comments (author_id, created_at desc);

create table public.comment_likes (
  comment_id uuid not null references public.comments (id) on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (comment_id, user_id)
);

create table public.saved_posts (
  user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  post_id uuid not null references public.posts (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, post_id)
);

create index saved_posts_user_idx on public.saved_posts (user_id, created_at desc);

-- Following a post means getting notified about new comments on it.
create table public.post_follows (
  user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  post_id uuid not null references public.posts (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, post_id)
);

create index post_follows_post_idx on public.post_follows (post_id);

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create or replace function private.can_view_post(p_post uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.posts p
    where p.id = p_post
      and (not p.is_removed or p.author_id = auth.uid())
      and (p.community_id is null or private.can_view_community(p.community_id))
      and not private.is_blocked_between(auth.uid(), p.author_id)
  );
$$;

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------

create or replace function private.validate_post()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Trusted writes (service role, seeds) skip the product rules.
  if auth.uid() is null then
    return new;
  end if;

  if new.type = 'announcement' and (new.community_id is null or not private.is_community_mod(new.community_id)) then
    raise exception 'Only community moderators can post announcements' using errcode = '42501';
  end if;
  if new.type = 'event' and (new.event_id is null or not private.can_view_event(new.event_id)) then
    raise exception 'Pick an event to share' using errcode = '22023';
  end if;
  if new.type in ('reel', 'video')
     and not exists (select 1 from jsonb_array_elements(new.media) m where m ->> 'type' = 'video') then
    raise exception 'Add a video to post' using errcode = '22023';
  end if;
  if new.type in ('question', 'poll', 'announcement', 'achievement')
     and nullif(trim(coalesce(new.title, '')), '') is null then
    raise exception 'Add a title' using errcode = '22023';
  end if;
  if new.type = 'poll' and new.poll_ends_at is not null and new.poll_ends_at < now() then
    raise exception 'The poll end time must be in the future' using errcode = '22023';
  end if;
  return new;
end;
$$;

create trigger posts_validate
  before insert on public.posts
  for each row execute function private.validate_post();

create or replace function private.on_post_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    update public.profiles set posts_count = posts_count + 1 where id = new.author_id;
    if new.community_id is not null then
      update public.communities set posts_count = posts_count + 1 where id = new.community_id;
    end if;
    -- Authors follow their own discussions.
    insert into public.post_follows (user_id, post_id) values (new.author_id, new.id)
    on conflict do nothing;
  else
    update public.profiles set posts_count = greatest(posts_count - 1, 0) where id = old.author_id;
    if old.community_id is not null then
      update public.communities set posts_count = greatest(posts_count - 1, 0) where id = old.community_id;
    end if;
  end if;
  return null;
end;
$$;

create trigger posts_counters
  after insert or delete on public.posts
  for each row execute function private.on_post_change();

create or replace function private.on_post_reaction_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    update public.posts
       set likes_count = likes_count + 1,
           reaction_counts = jsonb_set(
             reaction_counts, array[new.kind], to_jsonb(coalesce((reaction_counts ->> new.kind)::integer, 0) + 1)
           )
     where id = new.post_id;
  elsif tg_op = 'DELETE' then
    update public.posts
       set likes_count = greatest(likes_count - 1, 0),
           reaction_counts = jsonb_set(
             reaction_counts, array[old.kind], to_jsonb(greatest(coalesce((reaction_counts ->> old.kind)::integer, 0) - 1, 0))
           )
     where id = old.post_id;
  elsif new.kind <> old.kind then
    update public.posts
       set reaction_counts = jsonb_set(
             jsonb_set(
               reaction_counts, array[old.kind], to_jsonb(greatest(coalesce((reaction_counts ->> old.kind)::integer, 0) - 1, 0))
             ),
             array[new.kind], to_jsonb(coalesce((reaction_counts ->> new.kind)::integer, 0) + 1)
           )
     where id = new.post_id;
  end if;
  return null;
end;
$$;

create trigger post_reactions_counters
  after insert or update of kind or delete on public.post_reactions
  for each row execute function private.on_post_reaction_change();

-- Validates replies and keeps threads at most six levels deep so they stay
-- readable on a phone.
create or replace function private.before_comment_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_post public.posts%rowtype;
  v_parent public.comments%rowtype;
begin
  select * into v_post from public.posts where id = new.post_id;
  if not found then
    raise exception 'Post not found' using errcode = 'P0002';
  end if;

  if auth.uid() is not null then
    if v_post.is_locked and not (v_post.community_id is not null and private.is_community_mod(v_post.community_id)) then
      raise exception 'Comments are turned off for this post' using errcode = 'P0001';
    end if;
    if private.is_blocked_between(auth.uid(), v_post.author_id) then
      raise exception 'You can''t comment on this post' using errcode = '42501';
    end if;
  end if;

  if new.parent_id is null then
    new.depth := 0;
  else
    select * into v_parent from public.comments where id = new.parent_id;
    if not found or v_parent.post_id <> new.post_id then
      raise exception 'The comment you''re replying to is gone' using errcode = 'P0002';
    end if;
    if v_parent.depth >= 5 then
      new.parent_id := v_parent.parent_id;
      new.depth := v_parent.depth;
    else
      new.depth := v_parent.depth + 1;
    end if;
  end if;
  return new;
end;
$$;

create trigger comments_before_insert
  before insert on public.comments
  for each row execute function private.before_comment_insert();

create or replace function private.on_comment_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    update public.posts set comments_count = comments_count + 1 where id = new.post_id;
    if new.parent_id is not null then
      update public.comments set replies_count = replies_count + 1 where id = new.parent_id;
    end if;
  else
    update public.posts set comments_count = greatest(comments_count - 1, 0) where id = old.post_id;
    if old.parent_id is not null then
      update public.comments set replies_count = greatest(replies_count - 1, 0) where id = old.parent_id;
    end if;
  end if;
  return null;
end;
$$;

create trigger comments_counters
  after insert or delete on public.comments
  for each row execute function private.on_comment_change();

create or replace function private.on_comment_like_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    update public.comments set likes_count = likes_count + 1 where id = new.comment_id;
  else
    update public.comments set likes_count = greatest(likes_count - 1, 0) where id = old.comment_id;
  end if;
  return null;
end;
$$;

create trigger comment_likes_counters
  after insert or delete on public.comment_likes
  for each row execute function private.on_comment_like_change();

create or replace function private.on_save_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    update public.posts set saves_count = saves_count + 1 where id = new.post_id;
  else
    update public.posts set saves_count = greatest(saves_count - 1, 0) where id = old.post_id;
  end if;
  return null;
end;
$$;

create trigger saved_posts_counters
  after insert or delete on public.saved_posts
  for each row execute function private.on_save_change();

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

alter table public.posts enable row level security;
alter table public.poll_options enable row level security;
alter table public.poll_votes enable row level security;
alter table public.post_reactions enable row level security;
alter table public.comments enable row level security;
alter table public.comment_likes enable row level security;
alter table public.saved_posts enable row level security;
alter table public.post_follows enable row level security;

create policy "Posts are visible to their audience"
  on public.posts for select to authenticated
  using (
    (not is_removed or author_id = (select auth.uid()) or (community_id is not null and private.is_community_mod(community_id)))
    and (community_id is null or private.can_view_community(community_id))
    and not private.is_blocked_between((select auth.uid()), author_id)
  );

create policy "Students post as themselves"
  on public.posts for insert to authenticated
  with check (
    author_id = (select auth.uid())
    and (community_id is null or private.is_community_member(community_id))
  );

create policy "Authors edit their posts"
  on public.posts for update to authenticated
  using (author_id = (select auth.uid()))
  with check (author_id = (select auth.uid()));

create policy "Authors and moderators delete posts"
  on public.posts for delete to authenticated
  using (
    author_id = (select auth.uid())
    or (community_id is not null and private.is_community_mod(community_id))
    or private.is_platform_admin()
  );

revoke insert, update on public.posts from anon, authenticated;
grant insert (id, author_id, community_id, type, title, body, media, tags, event_id, poll_ends_at)
  on public.posts to authenticated;
grant update (title, body, tags, edited_at) on public.posts to authenticated;

create policy "Poll options are visible with the post"
  on public.poll_options for select to authenticated
  using (exists (select 1 from public.posts p where p.id = post_id));

create policy "Authors add poll options"
  on public.poll_options for insert to authenticated
  with check (exists (select 1 from public.posts p where p.id = post_id and p.author_id = (select auth.uid())));

revoke update on public.poll_options from anon, authenticated;

-- Votes are secret; you only see your own. Voting goes through vote_poll().
create policy "See your own vote"
  on public.poll_votes for select to authenticated
  using (user_id = (select auth.uid()));

revoke insert, update, delete on public.poll_votes from anon, authenticated;

create policy "Reactions are visible with the post"
  on public.post_reactions for select to authenticated
  using (exists (select 1 from public.posts p where p.id = post_id));

create policy "React to posts you can see"
  on public.post_reactions for insert to authenticated
  with check (user_id = (select auth.uid()) and exists (select 1 from public.posts p where p.id = post_id));

create policy "Change your reaction"
  on public.post_reactions for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy "Remove your reaction"
  on public.post_reactions for delete to authenticated
  using (user_id = (select auth.uid()));

create policy "Comments are visible with the post"
  on public.comments for select to authenticated
  using (
    exists (select 1 from public.posts p where p.id = post_id)
    and not private.is_blocked_between((select auth.uid()), author_id)
  );

create policy "Comment on posts you can see"
  on public.comments for insert to authenticated
  with check (author_id = (select auth.uid()) and exists (select 1 from public.posts p where p.id = post_id));

create policy "Edit your comments"
  on public.comments for update to authenticated
  using (author_id = (select auth.uid()) and not is_deleted and not is_removed)
  with check (author_id = (select auth.uid()));

revoke insert, update, delete on public.comments from anon, authenticated;
grant insert (id, post_id, author_id, parent_id, body) on public.comments to authenticated;
grant update (body, edited_at) on public.comments to authenticated;

create policy "Comment likes are visible"
  on public.comment_likes for select to authenticated
  using (exists (select 1 from public.comments c where c.id = comment_id));

create policy "Like comments"
  on public.comment_likes for insert to authenticated
  with check (user_id = (select auth.uid()) and exists (select 1 from public.comments c where c.id = comment_id));

create policy "Unlike comments"
  on public.comment_likes for delete to authenticated
  using (user_id = (select auth.uid()));

create policy "Your saved posts"
  on public.saved_posts for select to authenticated
  using (user_id = (select auth.uid()));

create policy "Save posts"
  on public.saved_posts for insert to authenticated
  with check (user_id = (select auth.uid()) and exists (select 1 from public.posts p where p.id = post_id));

create policy "Unsave posts"
  on public.saved_posts for delete to authenticated
  using (user_id = (select auth.uid()));

create policy "Your followed posts"
  on public.post_follows for select to authenticated
  using (user_id = (select auth.uid()));

create policy "Follow discussions"
  on public.post_follows for insert to authenticated
  with check (user_id = (select auth.uid()) and exists (select 1 from public.posts p where p.id = post_id));

create policy "Unfollow discussions"
  on public.post_follows for delete to authenticated
  using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- RPCs
-- ---------------------------------------------------------------------------

-- Creates a post (and its poll options) in one call. Runs as the caller, so
-- every RLS rule above still applies.
create or replace function public.create_post(
  p_type text,
  p_community_id uuid default null,
  p_title text default null,
  p_body text default null,
  p_media jsonb default '[]'::jsonb,
  p_tags text[] default '{}',
  p_event_id uuid default null,
  p_poll_options text[] default null,
  p_poll_ends_at timestamptz default null
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_post uuid := gen_random_uuid();
  v_label text;
  v_position integer := 0;
  v_options text[];
begin
  if auth.uid() is null then
    raise exception 'Sign in to post' using errcode = '28000';
  end if;

  if p_type = 'poll' then
    select coalesce(array_agg(trim(o)), '{}') into v_options
    from unnest(coalesce(p_poll_options, '{}')) o
    where nullif(trim(o), '') is not null;

    if cardinality(v_options) < 2 then
      raise exception 'Polls need at least two options' using errcode = '22023';
    elsif cardinality(v_options) > 6 then
      raise exception 'Polls can have up to six options' using errcode = '22023';
    end if;
  end if;

  insert into public.posts (id, author_id, community_id, type, title, body, media, tags, event_id, poll_ends_at)
  values (
    v_post,
    auth.uid(),
    p_community_id,
    p_type,
    nullif(trim(p_title), ''),
    nullif(trim(p_body), ''),
    coalesce(p_media, '[]'::jsonb),
    coalesce(p_tags, '{}'),
    p_event_id,
    case when p_type = 'poll' then p_poll_ends_at end
  );

  if p_type = 'poll' then
    foreach v_label in array v_options loop
      insert into public.poll_options (post_id, label, position) values (v_post, v_label, v_position);
      v_position := v_position + 1;
    end loop;
  end if;

  return v_post;
end;
$$;

-- Casts or changes the caller's vote.
create or replace function public.vote_poll(p_post uuid, p_option uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_previous uuid;
  v_ends_at timestamptz;
begin
  if v_uid is null then
    raise exception 'Sign in to vote' using errcode = '28000';
  end if;
  if not private.can_view_post(p_post) then
    raise exception 'Post not found' using errcode = 'P0002';
  end if;
  if not exists (select 1 from public.poll_options where id = p_option and post_id = p_post) then
    raise exception 'That option doesn''t exist' using errcode = 'P0002';
  end if;

  select poll_ends_at into v_ends_at from public.posts where id = p_post;
  if v_ends_at is not null and v_ends_at < now() then
    raise exception 'This poll has ended' using errcode = 'P0001';
  end if;

  select option_id into v_previous
  from public.poll_votes
  where post_id = p_post and user_id = v_uid
  for update;

  if v_previous = p_option then
    return;
  elsif v_previous is not null then
    update public.poll_votes set option_id = p_option, created_at = now()
     where post_id = p_post and user_id = v_uid;
    update public.poll_options set votes_count = greatest(votes_count - 1, 0) where id = v_previous;
  else
    insert into public.poll_votes (post_id, option_id, user_id) values (p_post, p_option, v_uid);
  end if;

  update public.poll_options set votes_count = votes_count + 1 where id = p_option;
end;
$$;

-- Deletes a comment. Comments with replies are blanked instead so the thread
-- keeps its shape.
create or replace function public.delete_comment(p_comment uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_comment public.comments%rowtype;
  v_community uuid;
begin
  select * into v_comment from public.comments where id = p_comment;
  if not found then
    return;
  end if;

  select community_id into v_community from public.posts where id = v_comment.post_id;

  if v_comment.author_id is distinct from auth.uid()
     and not (v_community is not null and private.is_community_mod(v_community))
     and not private.is_platform_admin() then
    raise exception 'You can only delete your own comments' using errcode = '42501';
  end if;

  if exists (select 1 from public.comments where parent_id = p_comment) then
    update public.comments
       set is_deleted = true, body = '[deleted]'
     where id = p_comment;
  else
    delete from public.comments where id = p_comment;
  end if;
end;
$$;

create or replace function public.record_post_view(p_post uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.posts set views_count = views_count + 1
  where id = p_post and auth.uid() is not null and private.can_view_post(p_post);
$$;

create or replace function public.record_post_share(p_post uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.posts set shares_count = shares_count + 1
  where id = p_post and auth.uid() is not null and private.can_view_post(p_post);
$$;


-- ===== 20260928000600_chat_rooms_calls.sql =====
-- Conversations (direct, group and community rooms), messages, reactions and
-- calls.
--
-- Every room is backed by a conversation. Room membership mirrors community
-- membership through triggers, so a single access check
-- (private.is_conversation_member) covers direct chats, groups and rooms.

create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in ('direct', 'group', 'room')),
  title text check (char_length(title) <= 80),
  avatar_url text,
  direct_key text unique,
  created_by uuid default auth.uid() references public.profiles (id) on delete set null,
  last_message_at timestamptz,
  last_message_preview text,
  last_message_sender_id uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  check ((type = 'direct') = (direct_key is not null))
);

create table public.conversation_members (
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'admin', 'member')),
  last_read_at timestamptz not null default now(),
  muted boolean not null default false,
  joined_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

create index conversation_members_user_idx on public.conversation_members (user_id);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  sender_id uuid default auth.uid() references public.profiles (id) on delete set null,
  kind text not null default 'text' check (kind in ('text', 'image', 'file', 'post', 'event', 'system', 'call')),
  body text check (char_length(body) <= 4000),
  attachments jsonb not null default '[]'::jsonb check (jsonb_typeof(attachments) = 'array' and jsonb_array_length(attachments) <= 10),
  reply_to_id uuid references public.messages (id) on delete set null,
  shared_post_id uuid references public.posts (id) on delete set null,
  shared_event_id uuid references public.events (id) on delete set null,
  reactions jsonb not null default '{}'::jsonb,
  edited_at timestamptz,
  deleted_at timestamptz,
  created_at timestamptz not null default now()
);

create index messages_conversation_idx on public.messages (conversation_id, created_at desc);
create index messages_sender_idx on public.messages (sender_id, created_at desc);
create index messages_body_trgm_idx on public.messages using gin (body extensions.gin_trgm_ops);

create table public.message_reactions (
  message_id uuid not null references public.messages (id) on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  emoji text not null check (char_length(emoji) between 1 and 16),
  conversation_id uuid references public.conversations (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (message_id, user_id, emoji)
);

create table public.rooms (
  id uuid primary key default gen_random_uuid(),
  community_id uuid not null references public.communities (id) on delete cascade,
  conversation_id uuid not null unique references public.conversations (id) on delete cascade,
  name text not null check (char_length(name) between 2 and 40),
  topic text check (char_length(topic) <= 160),
  kind text not null default 'general' check (
    kind in ('general', 'study', 'coding', 'placement', 'hackathon', 'gaming', 'club', 'event', 'announcements')
  ),
  position smallint not null default 0,
  is_locked boolean not null default false,
  created_by uuid default auth.uid() references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  unique (community_id, name)
);

create index rooms_community_idx on public.rooms (community_id, position);
create index rooms_name_trgm_idx on public.rooms using gin (name extensions.gin_trgm_ops);

create table public.calls (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  started_by uuid default auth.uid() references public.profiles (id) on delete set null,
  kind text not null default 'voice' check (kind in ('voice', 'video')),
  status text not null default 'ringing' check (status in ('ringing', 'ongoing', 'ended', 'missed', 'declined')),
  created_at timestamptz not null default now(),
  answered_at timestamptz,
  ended_at timestamptz
);

create index calls_conversation_idx on public.calls (conversation_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create or replace function private.is_conversation_member(p_conversation uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.conversation_members m
    where m.conversation_id = p_conversation and m.user_id = auth.uid()
  );
$$;

create or replace function private.conversation_role(p_conversation uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select m.role from public.conversation_members m
  where m.conversation_id = p_conversation and m.user_id = auth.uid();
$$;

-- Creates a room with its backing conversation and adds every active member
-- of the community.
create or replace function private.create_room_internal(
  p_community uuid,
  p_name text,
  p_topic text,
  p_kind text,
  p_position integer,
  p_created_by uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_conversation uuid;
  v_room uuid;
begin
  insert into public.conversations (type, title, created_by)
  values ('room', p_name, p_created_by)
  returning id into v_conversation;

  insert into public.rooms (community_id, conversation_id, name, topic, kind, position, created_by)
  values (p_community, v_conversation, p_name, p_topic, p_kind, p_position, p_created_by)
  returning id into v_room;

  insert into public.conversation_members (conversation_id, user_id)
  select v_conversation, m.user_id
  from public.community_members m
  where m.community_id = p_community and m.status = 'active'
  on conflict do nothing;

  return v_room;
end;
$$;

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------

create or replace function private.validate_message()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type text;
  v_other uuid;
  v_room public.rooms%rowtype;
begin
  if nullif(trim(coalesce(new.body, '')), '') is null
     and jsonb_array_length(new.attachments) = 0
     and new.shared_post_id is null
     and new.shared_event_id is null then
    raise exception 'Message is empty' using errcode = '22023';
  end if;

  if auth.uid() is null then
    return new;
  end if;

  select type into v_type from public.conversations where id = new.conversation_id;

  if v_type = 'direct' then
    select user_id into v_other
    from public.conversation_members
    where conversation_id = new.conversation_id and user_id <> auth.uid()
    limit 1;
    if v_other is not null and private.is_blocked_between(auth.uid(), v_other) then
      raise exception 'You can''t message this person' using errcode = '42501';
    end if;
  elsif v_type = 'room' then
    select * into v_room from public.rooms where conversation_id = new.conversation_id;
    if v_room.is_locked and new.kind not in ('system', 'call') and not private.is_community_mod(v_room.community_id) then
      raise exception 'Only moderators can post in this room' using errcode = '42501';
    end if;
  end if;

  if new.reply_to_id is not null
     and not exists (select 1 from public.messages m where m.id = new.reply_to_id and m.conversation_id = new.conversation_id) then
    new.reply_to_id := null;
  end if;
  return new;
end;
$$;

create trigger messages_validate
  before insert on public.messages
  for each row execute function private.validate_message();

create or replace function private.on_message_created()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_preview text;
begin
  v_preview := case new.kind
    when 'image' then coalesce(nullif(left(new.body, 140), ''), 'Photo')
    when 'file' then coalesce(new.attachments -> 0 ->> 'name', 'File')
    when 'post' then 'Shared a post'
    when 'event' then 'Shared an event'
    else left(coalesce(new.body, ''), 140)
  end;

  update public.conversations
     set last_message_at = new.created_at,
         last_message_preview = v_preview,
         last_message_sender_id = new.sender_id
   where id = new.conversation_id;

  if new.sender_id is not null then
    update public.conversation_members
       set last_read_at = greatest(last_read_at, new.created_at)
     where conversation_id = new.conversation_id and user_id = new.sender_id;
  end if;
  return null;
end;
$$;

create trigger messages_after_insert
  after insert on public.messages
  for each row execute function private.on_message_created();

create or replace function private.before_message_reaction()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  select m.conversation_id into new.conversation_id from public.messages m where m.id = new.message_id;
  return new;
end;
$$;

create trigger message_reactions_fill_conversation
  before insert on public.message_reactions
  for each row execute function private.before_message_reaction();

-- Reactions are mirrored onto the message as {"emoji": [user ids]} so one
-- realtime subscription on messages covers them.
create or replace function private.on_message_reaction_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_message uuid;
begin
  if tg_op = 'DELETE' then
    v_message := old.message_id;
  else
    v_message := new.message_id;
  end if;

  update public.messages m
     set reactions = coalesce((
       select jsonb_object_agg(t.emoji, t.users)
       from (
         select r.emoji, jsonb_agg(r.user_id order by r.created_at) as users
         from public.message_reactions r
         where r.message_id = v_message
         group by r.emoji
       ) t
     ), '{}'::jsonb)
   where m.id = v_message;
  return null;
end;
$$;

create trigger message_reactions_mirror
  after insert or delete on public.message_reactions
  for each row execute function private.on_message_reaction_change();

-- Room membership follows community membership.
create or replace function private.sync_room_membership()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op in ('INSERT', 'UPDATE') and new.status = 'active' then
    insert into public.conversation_members (conversation_id, user_id)
    select r.conversation_id, new.user_id
    from public.rooms r
    where r.community_id = new.community_id
    on conflict do nothing;
  end if;

  if tg_op = 'DELETE' then
    delete from public.conversation_members cm
    using public.rooms r
    where r.community_id = old.community_id
      and cm.conversation_id = r.conversation_id
      and cm.user_id = old.user_id;
  elsif tg_op = 'UPDATE' and new.status <> 'active' then
    delete from public.conversation_members cm
    using public.rooms r
    where r.community_id = new.community_id
      and cm.conversation_id = r.conversation_id
      and cm.user_id = new.user_id;
  end if;
  return null;
end;
$$;

create trigger community_members_sync_rooms
  after insert or update of status or delete on public.community_members
  for each row execute function private.sync_room_membership();

-- Every community starts with a #general room.
create or replace function private.create_default_room()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.create_room_internal(new.id, 'general', 'Say hi and hang out', 'general', 0, new.created_by);
  return null;
end;
$$;

create trigger communities_default_room
  after insert on public.communities
  for each row execute function private.create_default_room();

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages enable row level security;
alter table public.message_reactions enable row level security;
alter table public.rooms enable row level security;
alter table public.calls enable row level security;

create policy "Members see their conversations"
  on public.conversations for select to authenticated
  using (private.is_conversation_member(id));

create policy "Group admins edit the group"
  on public.conversations for update to authenticated
  using (type = 'group' and private.conversation_role(id) in ('owner', 'admin'))
  with check (type = 'group' and private.conversation_role(id) in ('owner', 'admin'));

revoke insert, update, delete on public.conversations from anon, authenticated;
grant update (title, avatar_url) on public.conversations to authenticated;

create policy "Members see each other"
  on public.conversation_members for select to authenticated
  using (private.is_conversation_member(conversation_id));

create policy "Update your read state"
  on public.conversation_members for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

revoke insert, update, delete on public.conversation_members from anon, authenticated;
grant update (last_read_at, muted) on public.conversation_members to authenticated;

create policy "Members read messages"
  on public.messages for select to authenticated
  using (private.is_conversation_member(conversation_id));

create policy "Members send messages"
  on public.messages for insert to authenticated
  with check (
    sender_id = (select auth.uid())
    and kind in ('text', 'image', 'file', 'post', 'event')
    and private.is_conversation_member(conversation_id)
  );

create policy "Edit or unsend your messages"
  on public.messages for update to authenticated
  using (sender_id = (select auth.uid()) and deleted_at is null)
  with check (sender_id = (select auth.uid()));

revoke insert, update, delete on public.messages from anon, authenticated;
grant insert (id, conversation_id, sender_id, kind, body, attachments, reply_to_id, shared_post_id, shared_event_id)
  on public.messages to authenticated;
grant update (body, edited_at, deleted_at) on public.messages to authenticated;

create policy "Members see reactions"
  on public.message_reactions for select to authenticated
  using (private.is_conversation_member(conversation_id));

create policy "Members react"
  on public.message_reactions for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (select 1 from public.messages m where m.id = message_id and private.is_conversation_member(m.conversation_id))
  );

create policy "Remove your reactions"
  on public.message_reactions for delete to authenticated
  using (user_id = (select auth.uid()));

create policy "Rooms are visible with the community"
  on public.rooms for select to authenticated
  using (private.can_view_community(community_id));

create policy "Moderators edit rooms"
  on public.rooms for update to authenticated
  using (private.is_community_mod(community_id))
  with check (private.is_community_mod(community_id));

create policy "Moderators delete rooms"
  on public.rooms for delete to authenticated
  using (private.is_community_mod(community_id));

revoke insert, update on public.rooms from anon, authenticated;
grant update (name, topic, kind, position, is_locked) on public.rooms to authenticated;

create policy "Members see calls"
  on public.calls for select to authenticated
  using (private.is_conversation_member(conversation_id));

revoke insert, update, delete on public.calls from anon, authenticated;

-- ---------------------------------------------------------------------------
-- RPCs
-- ---------------------------------------------------------------------------

-- Returns the direct conversation with another student, creating it on first
-- use.
create or replace function public.get_or_create_direct_conversation(p_user uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_key text;
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'Not signed in' using errcode = '28000';
  end if;
  if p_user = v_uid then
    raise exception 'You can''t message yourself' using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles where id = p_user) then
    raise exception 'Student not found' using errcode = 'P0002';
  end if;
  if private.is_blocked_between(v_uid, p_user) then
    raise exception 'You can''t message this person' using errcode = '42501';
  end if;

  v_key := least(v_uid::text, p_user::text) || ':' || greatest(v_uid::text, p_user::text);
  select id into v_id from public.conversations where direct_key = v_key;

  if v_id is null then
    insert into public.conversations (type, direct_key, created_by)
    values ('direct', v_key, v_uid)
    on conflict (direct_key) do nothing
    returning id into v_id;

    if v_id is null then
      select id into v_id from public.conversations where direct_key = v_key;
    end if;
  end if;

  insert into public.conversation_members (conversation_id, user_id)
  values (v_id, v_uid), (v_id, p_user)
  on conflict do nothing;

  return v_id;
end;
$$;

create or replace function public.create_group_conversation(p_title text, p_members uuid[])
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'Not signed in' using errcode = '28000';
  end if;
  if nullif(trim(coalesce(p_title, '')), '') is null then
    raise exception 'Give the group a name' using errcode = '22023';
  end if;
  if coalesce(cardinality(p_members), 0) = 0 then
    raise exception 'Add at least one person' using errcode = '22023';
  end if;
  if cardinality(p_members) > 255 then
    raise exception 'Groups can have up to 256 people' using errcode = '22023';
  end if;

  insert into public.conversations (type, title, created_by)
  values ('group', left(trim(p_title), 80), v_uid)
  returning id into v_id;

  insert into public.conversation_members (conversation_id, user_id, role)
  values (v_id, v_uid, 'owner');

  insert into public.conversation_members (conversation_id, user_id)
  select v_id, u
  from unnest(p_members) u
  where u <> v_uid
    and exists (select 1 from public.profiles p where p.id = u)
    and not private.is_blocked_between(v_uid, u)
  on conflict do nothing;

  insert into public.messages (conversation_id, sender_id, kind, body)
  values (v_id, v_uid, 'system', 'created the group');

  return v_id;
end;
$$;

create or replace function public.add_conversation_members(p_conversation uuid, p_users uuid[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_added integer;
begin
  if not exists (select 1 from public.conversations where id = p_conversation and type = 'group') then
    raise exception 'Group not found' using errcode = 'P0002';
  end if;
  if coalesce(private.conversation_role(p_conversation), '') not in ('owner', 'admin') then
    raise exception 'Only group admins can add people' using errcode = '42501';
  end if;

  insert into public.conversation_members (conversation_id, user_id)
  select p_conversation, u
  from unnest(coalesce(p_users, '{}')) u
  where exists (select 1 from public.profiles p where p.id = u)
    and not private.is_blocked_between(v_uid, u)
  on conflict do nothing;

  get diagnostics v_added = row_count;
  if v_added > 0 then
    insert into public.messages (conversation_id, sender_id, kind, body)
    values (p_conversation, v_uid, 'system', 'added ' || v_added || case when v_added = 1 then ' person' else ' people' end);
  end if;
end;
$$;

-- Group admins remove people; anyone can leave a group. When the owner leaves,
-- the longest-standing member takes over.
create or replace function public.remove_conversation_member(p_conversation uuid, p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_type text;
  v_role text;
  v_next uuid;
begin
  select type into v_type from public.conversations where id = p_conversation;
  if v_type is distinct from 'group' then
    raise exception 'You can only leave group chats' using errcode = '22023';
  end if;

  if p_user <> v_uid and coalesce(private.conversation_role(p_conversation), '') not in ('owner', 'admin') then
    raise exception 'Only group admins can remove people' using errcode = '42501';
  end if;

  select role into v_role from public.conversation_members
  where conversation_id = p_conversation and user_id = p_user;
  if v_role is null then
    return;
  end if;
  if v_role = 'owner' and p_user <> v_uid then
    raise exception 'The group owner can''t be removed' using errcode = '42501';
  end if;

  delete from public.conversation_members where conversation_id = p_conversation and user_id = p_user;

  insert into public.messages (conversation_id, sender_id, kind, body)
  values (
    p_conversation,
    p_user,
    'system',
    case when p_user = v_uid then 'left the group' else 'was removed' end
  );

  if v_role = 'owner' then
    select user_id into v_next from public.conversation_members
    where conversation_id = p_conversation
    order by case role when 'admin' then 0 else 1 end, joined_at
    limit 1;
    if v_next is not null then
      update public.conversation_members set role = 'owner'
      where conversation_id = p_conversation and user_id = v_next;
    end if;
  end if;
end;
$$;

-- The chat list: every conversation the caller is in, newest activity first,
-- with unread counts (capped at 99) and what's needed to render each row.
-- Runs as definer for speed; every row is scoped to the caller's memberships.
create or replace function public.my_conversations(p_type text default null)
returns table (
  id uuid,
  type text,
  title text,
  avatar_url text,
  last_message_at timestamptz,
  last_message_preview text,
  last_message_sender_id uuid,
  created_at timestamptz,
  unread_count integer,
  muted boolean,
  members_count integer,
  other_user jsonb,
  room jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    c.id,
    c.type,
    c.title,
    c.avatar_url,
    c.last_message_at,
    c.last_message_preview,
    c.last_message_sender_id,
    c.created_at,
    (
      select count(*)::integer from (
        select 1 from public.messages m
        where m.conversation_id = c.id
          and m.created_at > cm.last_read_at
          and m.sender_id is distinct from auth.uid()
          and m.deleted_at is null
        limit 99
      ) unread
    ) as unread_count,
    cm.muted,
    (select count(*)::integer from public.conversation_members x where x.conversation_id = c.id) as members_count,
    case when c.type = 'direct' then (
      select jsonb_build_object(
        'id', p.id, 'username', p.username, 'full_name', p.full_name,
        'avatar_url', p.avatar_url, 'is_verified', p.is_verified, 'last_seen_at', p.last_seen_at
      )
      from public.conversation_members om
      join public.profiles p on p.id = om.user_id
      where om.conversation_id = c.id and om.user_id <> auth.uid()
      limit 1
    ) end as other_user,
    case when c.type = 'room' then (
      select jsonb_build_object(
        'id', r.id, 'name', r.name, 'kind', r.kind,
        'community', jsonb_build_object('id', co.id, 'slug', co.slug, 'name', co.name, 'avatar_url', co.avatar_url, 'color', co.color)
      )
      from public.rooms r
      join public.communities co on co.id = r.community_id
      where r.conversation_id = c.id
    ) end as room
  from public.conversation_members cm
  join public.conversations c on c.id = cm.conversation_id
  where auth.uid() is not null
    and cm.user_id = auth.uid()
    and (p_type is null or c.type = p_type)
    and (c.type <> 'room' or c.last_message_at is not null)
  order by coalesce(c.last_message_at, c.created_at) desc
  limit 200;
$$;

-- Searches messages across every conversation the caller belongs to.
create or replace function public.search_messages(p_query text, p_conversation uuid default null, p_limit integer default 30)
returns table (
  id uuid,
  conversation_id uuid,
  body text,
  created_at timestamptz,
  sender jsonb,
  conversation jsonb
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    m.id,
    m.conversation_id,
    m.body,
    m.created_at,
    jsonb_build_object('id', s.id, 'username', s.username, 'full_name', s.full_name, 'avatar_url', s.avatar_url) as sender,
    jsonb_build_object(
      'id', c.id,
      'type', c.type,
      'title', coalesce(
        c.title,
        (select p.full_name from public.conversation_members om join public.profiles p on p.id = om.user_id
          where om.conversation_id = c.id and om.user_id <> auth.uid() limit 1)
      )
    ) as conversation
  from public.messages m
  join public.conversations c on c.id = m.conversation_id
  left join public.profiles s on s.id = m.sender_id
  where char_length(trim(coalesce(p_query, ''))) >= 2
    and m.deleted_at is null
    and m.kind in ('text', 'image', 'file')
    and m.body ilike private.contains_pattern(p_query)
    and (p_conversation is null or m.conversation_id = p_conversation)
  order by m.created_at desc
  limit least(greatest(p_limit, 1), 100);
$$;

-- Adds the reaction if it's missing, removes it otherwise. Returns true when
-- the reaction was added.
create or replace function public.toggle_message_reaction(p_message uuid, p_emoji text)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
begin
  delete from public.message_reactions
  where message_id = p_message and user_id = auth.uid() and emoji = p_emoji;
  if found then
    return false;
  end if;

  insert into public.message_reactions (message_id, user_id, emoji)
  values (p_message, auth.uid(), p_emoji);
  return true;
end;
$$;

create or replace function public.create_room(p_community uuid, p_name text, p_topic text default null, p_kind text default 'general')
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text := lower(regexp_replace(trim(coalesce(p_name, '')), '\s+', '-', 'g'));
  v_position integer;
begin
  if not private.is_community_mod(p_community) then
    raise exception 'Only moderators can create rooms' using errcode = '42501';
  end if;
  if char_length(v_name) < 2 then
    raise exception 'Give the room a name' using errcode = '22023';
  end if;
  if exists (select 1 from public.rooms where community_id = p_community and name = v_name) then
    raise exception 'A room with that name already exists' using errcode = '23505';
  end if;

  select coalesce(max(position), 0) + 1 into v_position from public.rooms where community_id = p_community;
  return private.create_room_internal(p_community, v_name, nullif(trim(p_topic), ''), coalesce(p_kind, 'general'), v_position, auth.uid());
end;
$$;

-- Deletes a room with its messages. Every community keeps at least one room.
create or replace function public.delete_room(p_room uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_room public.rooms%rowtype;
begin
  select * into v_room from public.rooms where id = p_room;
  if not found then
    return;
  end if;
  if not private.is_community_mod(v_room.community_id) then
    raise exception 'Only moderators can delete rooms' using errcode = '42501';
  end if;
  if (select count(*) from public.rooms where community_id = v_room.community_id) <= 1 then
    raise exception 'A community needs at least one room' using errcode = 'P0001';
  end if;

  delete from public.conversations where id = v_room.conversation_id;
end;
$$;

-- Starts a voice or video call in a conversation, or returns the call that's
-- already ringing or ongoing there.
create or replace function public.start_call(p_conversation uuid, p_kind text default 'voice')
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_type text;
  v_other uuid;
  v_call uuid;
begin
  if not private.is_conversation_member(p_conversation) then
    raise exception 'Conversation not found' using errcode = 'P0002';
  end if;
  if p_kind not in ('voice', 'video') then
    raise exception 'Unknown call type' using errcode = '22023';
  end if;

  select type into v_type from public.conversations where id = p_conversation;
  if v_type = 'direct' then
    select user_id into v_other from public.conversation_members
    where conversation_id = p_conversation and user_id <> v_uid limit 1;
    if private.is_blocked_between(v_uid, v_other) then
      raise exception 'You can''t call this person' using errcode = '42501';
    end if;
  end if;

  select id into v_call from public.calls
  where conversation_id = p_conversation
    and (status = 'ongoing' or (status = 'ringing' and created_at > now() - interval '1 minute'))
  order by created_at desc
  limit 1;

  if v_call is not null then
    return v_call;
  end if;

  insert into public.calls (conversation_id, started_by, kind)
  values (p_conversation, v_uid, p_kind)
  returning id into v_call;

  insert into public.messages (conversation_id, sender_id, kind, body)
  values (p_conversation, v_uid, 'call', case p_kind when 'video' then 'Video call' else 'Voice call' end);

  return v_call;
end;
$$;

create or replace function public.update_call(p_call uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_call public.calls%rowtype;
begin
  select * into v_call from public.calls where id = p_call for update;
  if not found or not private.is_conversation_member(v_call.conversation_id) then
    raise exception 'Call not found' using errcode = 'P0002';
  end if;
  if p_status not in ('ongoing', 'ended', 'missed', 'declined') then
    raise exception 'Unknown call status' using errcode = '22023';
  end if;
  if v_call.status in ('ended', 'missed', 'declined') then
    return;
  end if;

  update public.calls
     set status = p_status,
         answered_at = case when p_status = 'ongoing' then coalesce(answered_at, now()) else answered_at end,
         ended_at = case when p_status <> 'ongoing' then now() else ended_at end
   where id = p_call;
end;
$$;


-- ===== 20260928000700_notifications.sql =====
-- In-app notifications, generated by triggers and delivered over realtime.
-- Chat messages don't create notification rows; the chat list has its own
-- unread counts.

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  actor_id uuid references public.profiles (id) on delete cascade,
  type text not null check (
    type in (
      'follow', 'post_reaction', 'post_comment', 'comment_reply', 'mention', 'thread_activity', 'announcement',
      'community_join_request', 'community_join_approved', 'community_role', 'event_registration', 'event_update',
      'event_reminder', 'event_waitlist_promoted', 'missed_call', 'room_invite', 'report_update', 'content_removed'
    )
  ),
  post_id uuid references public.posts (id) on delete cascade,
  comment_id uuid references public.comments (id) on delete cascade,
  community_id uuid references public.communities (id) on delete cascade,
  event_id uuid references public.events (id) on delete cascade,
  conversation_id uuid references public.conversations (id) on delete cascade,
  room_id uuid references public.rooms (id) on delete cascade,
  data jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index notifications_user_idx on public.notifications (user_id, created_at desc);
create index notifications_unread_idx on public.notifications (user_id) where read_at is null;

alter table public.notifications enable row level security;

create policy "Your notifications"
  on public.notifications for select to authenticated
  using (user_id = (select auth.uid()));

create policy "Mark your notifications read"
  on public.notifications for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy "Clear your notifications"
  on public.notifications for delete to authenticated
  using (user_id = (select auth.uid()));

revoke insert, update on public.notifications from anon, authenticated;
grant update (read_at) on public.notifications to authenticated;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create or replace function private.notify(
  p_user uuid,
  p_actor uuid,
  p_type text,
  p_post uuid default null,
  p_comment uuid default null,
  p_community uuid default null,
  p_event uuid default null,
  p_conversation uuid default null,
  p_room uuid default null,
  p_data jsonb default '{}'::jsonb
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
  values (p_user, p_actor, p_type, p_post, p_comment, p_community, p_event, p_conversation, p_room, coalesce(p_data, '{}'::jsonb));
end;
$$;

create or replace function private.snippet(value text)
returns text
language sql
immutable
as $$
  select left(regexp_replace(trim(coalesce(value, '')), '\s+', ' ', 'g'), 140);
$$;

-- Profiles @mentioned in a piece of text.
create or replace function private.mentioned_profiles(p_text text)
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select distinct p.id
  from public.profiles p
  where p.username in (
    select rtrim(lower(m[1]), '.')
    from regexp_matches(coalesce(p_text, ''), '@([A-Za-z0-9_.]{3,24})', 'g') as found(m)
  );
$$;

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------

create or replace function private.notify_on_follow()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.notify(p_user := new.following_id, p_actor := new.follower_id, p_type := 'follow');
  return null;
end;
$$;

create trigger follows_notify
  after insert on public.follows
  for each row execute function private.notify_on_follow();

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

  -- Don't re-notify when someone toggles their reaction off and on again.
  if exists (
    select 1 from public.notifications n
    where n.user_id = v_author and n.actor_id = new.user_id and n.post_id = new.post_id
      and n.type = 'post_reaction' and n.created_at > now() - interval '1 day'
  ) then
    return null;
  end if;

  perform private.notify(
    p_user := v_author, p_actor := new.user_id, p_type := 'post_reaction',
    p_post := new.post_id, p_data := jsonb_build_object('kind', new.kind)
  );
  return null;
end;
$$;

create trigger post_reactions_notify
  after insert on public.post_reactions
  for each row execute function private.notify_on_reaction();

create or replace function private.notify_on_comment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_post public.posts%rowtype;
  v_parent_author uuid;
  v_data jsonb := jsonb_build_object('snippet', private.snippet(new.body));
  v_mentioned uuid;
begin
  select * into v_post from public.posts where id = new.post_id;

  if new.parent_id is not null then
    select author_id into v_parent_author from public.comments where id = new.parent_id;
    perform private.notify(
      p_user := v_parent_author, p_actor := new.author_id, p_type := 'comment_reply',
      p_post := new.post_id, p_comment := new.id, p_community := v_post.community_id, p_data := v_data
    );
  end if;

  if v_post.author_id is distinct from v_parent_author then
    perform private.notify(
      p_user := v_post.author_id, p_actor := new.author_id, p_type := 'post_comment',
      p_post := new.post_id, p_comment := new.id, p_community := v_post.community_id, p_data := v_data
    );
  end if;

  for v_mentioned in select * from private.mentioned_profiles(new.body) loop
    if v_mentioned is distinct from v_post.author_id and v_mentioned is distinct from v_parent_author then
      perform private.notify(
        p_user := v_mentioned, p_actor := new.author_id, p_type := 'mention',
        p_post := new.post_id, p_comment := new.id, p_community := v_post.community_id, p_data := v_data
      );
    end if;
  end loop;

  -- Everyone else following the discussion.
  insert into public.notifications (user_id, actor_id, type, post_id, comment_id, community_id, data)
  select f.user_id, new.author_id, 'thread_activity', new.post_id, new.id, v_post.community_id, v_data
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

create trigger comments_notify
  after insert on public.comments
  for each row execute function private.notify_on_comment();

create or replace function private.notify_on_post()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_mentioned uuid;
  v_data jsonb := jsonb_build_object('snippet', private.snippet(coalesce(new.title, new.body)));
begin
  for v_mentioned in select * from private.mentioned_profiles(concat_ws(' ', new.title, new.body)) loop
    perform private.notify(
      p_user := v_mentioned, p_actor := new.author_id, p_type := 'mention',
      p_post := new.id, p_community := new.community_id, p_data := v_data
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

create trigger posts_notify
  after insert on public.posts
  for each row execute function private.notify_on_post();

create or replace function private.notify_on_membership()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' and new.status = 'pending' then
    insert into public.notifications (user_id, actor_id, type, community_id)
    select m.user_id, new.user_id, 'community_join_request', new.community_id
    from public.community_members m
    where m.community_id = new.community_id
      and m.status = 'active'
      and m.role in ('owner', 'admin', 'moderator');
  elsif tg_op = 'UPDATE' and old.status = 'pending' and new.status = 'active' then
    perform private.notify(
      p_user := new.user_id, p_actor := auth.uid(), p_type := 'community_join_approved', p_community := new.community_id
    );
  elsif tg_op = 'UPDATE' and old.role <> new.role and new.role in ('admin', 'moderator', 'owner') and new.status = 'active' then
    perform private.notify(
      p_user := new.user_id, p_actor := auth.uid(), p_type := 'community_role',
      p_community := new.community_id, p_data := jsonb_build_object('role', new.role)
    );
  end if;
  return null;
end;
$$;

create trigger community_members_notify
  after insert or update on public.community_members
  for each row execute function private.notify_on_membership();

create or replace function private.notify_on_registration()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_organizer uuid;
begin
  select organizer_id into v_organizer from public.events where id = new.event_id;

  if new.status in ('going', 'waitlist')
     and (tg_op = 'INSERT' or old.status not in ('going', 'waitlist', 'attended')) then
    perform private.notify(
      p_user := v_organizer, p_actor := new.user_id, p_type := 'event_registration',
      p_event := new.event_id, p_data := jsonb_build_object('status', new.status)
    );
  elsif tg_op = 'UPDATE' and old.status = 'waitlist' and new.status = 'going' then
    perform private.notify(p_user := new.user_id, p_actor := null, p_type := 'event_waitlist_promoted', p_event := new.event_id);
  end if;
  return null;
end;
$$;

create trigger event_registrations_notify
  after insert or update of status on public.event_registrations
  for each row execute function private.notify_on_registration();

create or replace function private.notify_on_event_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.notifications (user_id, actor_id, type, event_id, data)
  select r.user_id, new.author_id, 'event_update', new.event_id, jsonb_build_object('snippet', private.snippet(new.body))
  from public.event_registrations r
  where r.event_id = new.event_id
    and r.status in ('going', 'waitlist')
    and r.user_id <> new.author_id;
  return null;
end;
$$;

create trigger event_updates_notify
  after insert on public.event_updates
  for each row execute function private.notify_on_event_update();

create or replace function private.notify_on_call_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'missed' and old.status = 'ringing' then
    insert into public.notifications (user_id, actor_id, type, conversation_id, data)
    select m.user_id, new.started_by, 'missed_call', new.conversation_id, jsonb_build_object('kind', new.kind)
    from public.conversation_members m
    where m.conversation_id = new.conversation_id
      and m.user_id is distinct from new.started_by;
  end if;
  return null;
end;
$$;

create trigger calls_notify
  after update of status on public.calls
  for each row execute function private.notify_on_call_update();

-- ---------------------------------------------------------------------------
-- RPCs and jobs
-- ---------------------------------------------------------------------------

create or replace function public.mark_all_notifications_read()
returns void
language sql
security invoker
set search_path = ''
as $$
  update public.notifications set read_at = now()
  where user_id = auth.uid() and read_at is null;
$$;

create or replace function public.invite_to_room(p_room uuid, p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_room public.rooms%rowtype;
begin
  select * into v_room from public.rooms where id = p_room;
  if not found or not private.is_conversation_member(v_room.conversation_id) then
    raise exception 'Room not found' using errcode = 'P0002';
  end if;

  perform private.notify(
    p_user := p_user, p_actor := auth.uid(), p_type := 'room_invite',
    p_community := v_room.community_id, p_room := v_room.id, p_conversation := v_room.conversation_id,
    p_data := jsonb_build_object('room', v_room.name)
  );
end;
$$;

-- Reminds attendees a day and an hour before an event starts. Scheduled with
-- pg_cron when it's available (see the realtime migration).
create or replace function private.send_event_reminders()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  with due as (
    update public.events e
       set reminder_day_sent = true
     where not e.is_cancelled
       and not e.reminder_day_sent
       and e.starts_at between now() + interval '1 hour' and now() + interval '24 hours'
    returning e.id
  )
  insert into public.notifications (user_id, type, event_id, data)
  select r.user_id, 'event_reminder', r.event_id, jsonb_build_object('when', 'day')
  from due join public.event_registrations r on r.event_id = due.id
  where r.status = 'going';

  with due as (
    update public.events e
       set reminder_hour_sent = true, reminder_day_sent = true
     where not e.is_cancelled
       and not e.reminder_hour_sent
       and e.starts_at between now() and now() + interval '1 hour'
    returning e.id
  )
  insert into public.notifications (user_id, type, event_id, data)
  select r.user_id, 'event_reminder', r.event_id, jsonb_build_object('when', 'hour')
  from due join public.event_registrations r on r.event_id = due.id
  where r.status = 'going';
end;
$$;


-- ===== 20260928000800_moderation.sql =====
-- Reports, moderation actions and basic spam protection.
--
-- Reports are routed to the moderators of the community the content lives in;
-- content outside communities (profile posts, direct messages, users) goes to
-- platform admins. Each report keeps a snapshot of the content so moderators
-- see what was reported even if it's edited or deleted later.

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  target_type text not null check (target_type in ('post', 'comment', 'user', 'community', 'message', 'event')),
  target_id uuid not null,
  community_id uuid references public.communities (id) on delete cascade,
  target_user_id uuid references public.profiles (id) on delete set null,
  reason text not null check (
    reason in ('spam', 'harassment', 'hate', 'nudity', 'violence', 'misinformation', 'self_harm', 'impersonation', 'other')
  ),
  details text check (char_length(details) <= 1000),
  snapshot jsonb not null default '{}'::jsonb,
  status text not null default 'open' check (status in ('open', 'actioned', 'dismissed')),
  reviewed_by uuid references public.profiles (id) on delete set null,
  reviewed_at timestamptz,
  resolution_note text check (char_length(resolution_note) <= 500),
  created_at timestamptz not null default now(),
  unique (reporter_id, target_type, target_id)
);

create index reports_community_idx on public.reports (community_id, status, created_at desc);
create index reports_status_idx on public.reports (status, created_at desc);
create index reports_target_idx on public.reports (target_type, target_id);

create table public.mod_actions (
  id uuid primary key default gen_random_uuid(),
  community_id uuid references public.communities (id) on delete cascade,
  moderator_id uuid references public.profiles (id) on delete set null,
  action text not null,
  target_type text not null,
  target_id uuid not null,
  reason text,
  created_at timestamptz not null default now()
);

create index mod_actions_community_idx on public.mod_actions (community_id, created_at desc);

alter table public.reports enable row level security;
alter table public.mod_actions enable row level security;

create policy "Reporters and moderators see reports"
  on public.reports for select to authenticated
  using (
    reporter_id = (select auth.uid())
    or (community_id is not null and private.is_community_mod(community_id))
    or private.is_platform_admin()
  );

revoke insert, update, delete on public.reports from anon, authenticated;

create policy "Moderators see the moderation log"
  on public.mod_actions for select to authenticated
  using ((community_id is not null and private.is_community_mod(community_id)) or private.is_platform_admin());

revoke insert, update, delete on public.mod_actions from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Spam protection
-- ---------------------------------------------------------------------------

-- Rate limits and duplicate/link-spam checks for student-written content.
-- Trusted writes (service role, seeds) have no auth.uid() and skip the checks.
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
    select count(*) into v_recent from public.messages
    where sender_id = v_uid and created_at > now() - interval '10 seconds';
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

create trigger posts_guard_spam
  before insert on public.posts
  for each row execute function private.guard_spam();

create trigger comments_guard_spam
  before insert on public.comments
  for each row execute function private.guard_spam();

create trigger messages_guard_spam
  before insert on public.messages
  for each row execute function private.guard_spam();

-- ---------------------------------------------------------------------------
-- RPCs
-- ---------------------------------------------------------------------------

-- Files a report. Reporting the same thing twice is a no-op. Posts that
-- collect reports from five different people are hidden until a moderator
-- reviews them.
create or replace function public.submit_report(
  p_target_type text,
  p_target_id uuid,
  p_reason text,
  p_details text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_community uuid;
  v_user uuid;
  v_snapshot jsonb := '{}'::jsonb;
  v_open integer;
begin
  if v_uid is null then
    raise exception 'Sign in to report' using errcode = '28000';
  end if;

  if p_target_type = 'post' then
    if not private.can_view_post(p_target_id) then
      raise exception 'Post not found' using errcode = 'P0002';
    end if;
    select p.community_id, p.author_id,
           jsonb_build_object('type', p.type, 'title', p.title, 'body', left(p.body, 1000), 'media', p.media)
      into v_community, v_user, v_snapshot
    from public.posts p where p.id = p_target_id;
  elsif p_target_type = 'comment' then
    select p.community_id, c.author_id, jsonb_build_object('body', left(c.body, 1000), 'post_id', c.post_id)
      into v_community, v_user, v_snapshot
    from public.comments c join public.posts p on p.id = c.post_id
    where c.id = p_target_id and private.can_view_post(c.post_id);
  elsif p_target_type = 'message' then
    select r.community_id, m.sender_id,
           jsonb_build_object('body', left(m.body, 1000), 'attachments', m.attachments, 'conversation_id', m.conversation_id)
      into v_community, v_user, v_snapshot
    from public.messages m left join public.rooms r on r.conversation_id = m.conversation_id
    where m.id = p_target_id and private.is_conversation_member(m.conversation_id);
  elsif p_target_type = 'event' then
    select e.community_id, e.organizer_id, jsonb_build_object('title', e.title, 'description', left(e.description, 1000))
      into v_community, v_user, v_snapshot
    from public.events e where e.id = p_target_id and private.can_view_event(e.id);
  elsif p_target_type = 'user' then
    select null, p.id, jsonb_build_object('username', p.username, 'full_name', p.full_name, 'bio', p.bio)
      into v_community, v_user, v_snapshot
    from public.profiles p where p.id = p_target_id;
  elsif p_target_type = 'community' then
    -- Community reports go to platform admins, not the community's own staff.
    select null, c.created_by, jsonb_build_object('name', c.name, 'description', left(c.description, 1000))
      into v_community, v_user, v_snapshot
    from public.communities c where c.id = p_target_id;
  else
    raise exception 'Unknown report target' using errcode = '22023';
  end if;

  if v_snapshot is null or v_snapshot = '{}'::jsonb then
    raise exception 'Nothing to report' using errcode = 'P0002';
  end if;
  if v_user = v_uid then
    raise exception 'You can''t report yourself' using errcode = '22023';
  end if;

  insert into public.reports (reporter_id, target_type, target_id, community_id, target_user_id, reason, details, snapshot)
  values (v_uid, p_target_type, p_target_id, v_community, v_user, p_reason, nullif(trim(p_details), ''), v_snapshot)
  on conflict (reporter_id, target_type, target_id) do nothing;

  if p_target_type = 'post' and found then
    update public.posts set reports_count = reports_count + 1 where id = p_target_id
    returning reports_count into v_open;
    if v_open >= 5 then
      update public.posts set is_removed = true, removed_reason = 'Hidden after multiple reports; awaiting review'
      where id = p_target_id and not is_removed;
    end if;
  end if;
end;
$$;

-- Moderator actions on posts, comments and messages: remove, restore, pin,
-- unpin, lock and unlock. Community moderators act inside their community;
-- platform admins act anywhere.
create or replace function public.moderate_content(
  p_target_type text,
  p_target_id uuid,
  p_action text,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_community uuid;
  v_author uuid;
  v_post uuid;
begin
  if p_target_type = 'post' then
    select community_id, author_id, id into v_community, v_author, v_post from public.posts where id = p_target_id;
  elsif p_target_type = 'comment' then
    select p.community_id, c.author_id, c.post_id into v_community, v_author, v_post
    from public.comments c join public.posts p on p.id = c.post_id where c.id = p_target_id;
  elsif p_target_type = 'message' then
    select r.community_id, m.sender_id into v_community, v_author
    from public.messages m left join public.rooms r on r.conversation_id = m.conversation_id where m.id = p_target_id;
  else
    raise exception 'Unknown target' using errcode = '22023';
  end if;

  if v_author is null and v_community is null and v_post is null then
    raise exception 'Content not found' using errcode = 'P0002';
  end if;
  if not (private.is_platform_admin() or (v_community is not null and private.is_community_mod(v_community))) then
    raise exception 'Only moderators can do that' using errcode = '42501';
  end if;

  if p_target_type = 'post' then
    update public.posts set
      is_removed = case p_action when 'remove' then true when 'restore' then false else is_removed end,
      removed_reason = case p_action when 'remove' then coalesce(nullif(trim(p_reason), ''), 'Removed by moderators')
                                     when 'restore' then null else removed_reason end,
      reports_count = case when p_action = 'restore' then 0 else reports_count end,
      is_pinned = case p_action when 'pin' then true when 'unpin' then false else is_pinned end,
      is_locked = case p_action when 'lock' then true when 'unlock' then false else is_locked end
    where id = p_target_id;
  elsif p_target_type = 'comment' then
    if p_action not in ('remove', 'restore') then
      raise exception 'Unsupported action' using errcode = '22023';
    end if;
    update public.comments set is_removed = (p_action = 'remove') where id = p_target_id;
  elsif p_target_type = 'message' then
    if p_action <> 'remove' then
      raise exception 'Unsupported action' using errcode = '22023';
    end if;
    update public.messages set deleted_at = now() where id = p_target_id;
  end if;

  insert into public.mod_actions (community_id, moderator_id, action, target_type, target_id, reason)
  values (v_community, auth.uid(), p_action, p_target_type, p_target_id, nullif(trim(p_reason), ''));

  if p_action = 'remove' and p_target_type in ('post', 'comment') then
    perform private.notify(
      p_user := v_author, p_actor := null, p_type := 'content_removed',
      p_post := v_post, p_community := v_community,
      p_data := jsonb_build_object('target', p_target_type, 'reason', coalesce(nullif(trim(p_reason), ''), 'Broke the community rules'))
    );
  end if;
end;
$$;

-- Closes every open report on the same target at once.
create or replace function public.resolve_report(p_report uuid, p_status text, p_note text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_report public.reports%rowtype;
begin
  if p_status not in ('actioned', 'dismissed') then
    raise exception 'Unknown status' using errcode = '22023';
  end if;

  select * into v_report from public.reports where id = p_report;
  if not found then
    raise exception 'Report not found' using errcode = 'P0002';
  end if;
  if not (private.is_platform_admin() or (v_report.community_id is not null and private.is_community_mod(v_report.community_id))) then
    raise exception 'Only moderators can review reports' using errcode = '42501';
  end if;

  with closed as (
    update public.reports
       set status = p_status, reviewed_by = auth.uid(), reviewed_at = now(), resolution_note = nullif(trim(p_note), '')
     where target_type = v_report.target_type and target_id = v_report.target_id and status = 'open'
    returning reporter_id
  )
  insert into public.notifications (user_id, type, community_id, data)
  select reporter_id, 'report_update', v_report.community_id,
         jsonb_build_object('status', p_status, 'target', v_report.target_type)
  from closed;

  insert into public.mod_actions (community_id, moderator_id, action, target_type, target_id, reason)
  values (v_report.community_id, auth.uid(), 'report_' || p_status, v_report.target_type, v_report.target_id, nullif(trim(p_note), ''));
end;
$$;


-- ===== 20260928000900_views_feeds_search_rankings.sql =====
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


-- ===== 20260928001000_storage.sql =====
-- Storage buckets.
--
--   avatars  public   <user id>/<file>                          profile photos
--   media    public   <user id>/<file>                          post images and videos, reels, posters,
--                                                               community icons and banners
--   chat     private  <conversation id>/<user id>/<file>        chat attachments, read via signed URLs

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('avatars', 'avatars', true, 5242880, array['image/jpeg', 'image/png', 'image/webp', 'image/gif']),
  ('media', 'media', true, 52428800, array[
    'image/jpeg', 'image/png', 'image/webp', 'image/gif', 'video/mp4', 'video/quicktime', 'video/webm'
  ]),
  ('chat', 'chat', false, 26214400, null)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Students upload to their own folder" on storage.objects;
create policy "Students upload to their own folder"
  on storage.objects for insert to authenticated
  with check (
    bucket_id in ('avatars', 'media')
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "Students manage their own files" on storage.objects;
create policy "Students manage their own files"
  on storage.objects for update to authenticated
  using (
    bucket_id in ('avatars', 'media')
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "Students delete their own files" on storage.objects;
create policy "Students delete their own files"
  on storage.objects for delete to authenticated
  using (
    bucket_id in ('avatars', 'media')
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "Chat members upload attachments" on storage.objects;
create policy "Chat members upload attachments"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'chat'
    and (storage.foldername(name))[2] = (select auth.uid())::text
    and private.is_conversation_member(private.try_uuid((storage.foldername(name))[1]))
  );

drop policy if exists "Chat members read attachments" on storage.objects;
create policy "Chat members read attachments"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'chat'
    and private.is_conversation_member(private.try_uuid((storage.foldername(name))[1]))
  );


-- ===== 20260928001100_realtime_jobs_grants.sql =====
-- Realtime publication, private channel authorization, scheduled jobs and the
-- final API grants.

-- ---------------------------------------------------------------------------
-- Postgres changes
-- ---------------------------------------------------------------------------

do $$
declare
  v_table text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise notice 'supabase_realtime publication not found; skipping';
    return;
  end if;

  foreach v_table in array array['messages', 'conversations', 'conversation_members', 'notifications', 'calls'] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = v_table
    ) then
      execute format('alter publication supabase_realtime add table public.%I', v_table);
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Private channels (broadcast and presence)
--
--   online            app-wide presence, any signed-in student
--   chat:<id>         typing indicators for a conversation, members only
--   call:<id>         WebRTC signaling for a call, conversation members only
--   voice:<room id>   voice/video in a community room, room members only
--   user:<id>         a student's own channel (incoming calls)
-- ---------------------------------------------------------------------------

create or replace function private.can_use_topic(p_topic text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_kind text := split_part(coalesce(p_topic, ''), ':', 1);
  v_id uuid := private.try_uuid(split_part(coalesce(p_topic, ''), ':', 2));
begin
  if auth.uid() is null then
    return false;
  end if;
  if p_topic = 'online' then
    return true;
  end if;
  if v_id is null then
    return false;
  end if;

  return case v_kind
    when 'chat' then private.is_conversation_member(v_id)
    when 'call' then exists (
      select 1 from public.calls c where c.id = v_id and private.is_conversation_member(c.conversation_id)
    )
    when 'voice' then exists (
      select 1 from public.rooms r where r.id = v_id and private.is_conversation_member(r.conversation_id)
    )
    when 'user' then v_id = auth.uid()
    else false
  end;
end;
$$;

do $$
begin
  if to_regclass('realtime.messages') is null then
    raise notice 'realtime.messages not found; skipping channel policies';
    return;
  end if;

  execute 'drop policy if exists "Students join allowed channels" on realtime.messages';
  execute $policy$
    create policy "Students join allowed channels"
      on realtime.messages for select to authenticated
      using (private.can_use_topic((select realtime.topic())))
  $policy$;

  execute 'drop policy if exists "Students send on allowed channels" on realtime.messages';
  execute $policy$
    create policy "Students send on allowed channels"
      on realtime.messages for insert to authenticated
      with check (private.can_use_topic((select realtime.topic())))
  $policy$;
end;
$$;

-- ---------------------------------------------------------------------------
-- Scheduled jobs (pg_cron, where the project has it)
-- ---------------------------------------------------------------------------

do $$
begin
  create extension if not exists pg_cron;
  perform cron.schedule('quad-event-reminders', '*/10 * * * *', 'select private.send_event_reminders()');
  perform cron.schedule('quad-college-stats', '17 * * * *', 'select private.refresh_college_stats()');
exception when others then
  raise notice 'pg_cron unavailable (%); event reminders and hourly college stats are not scheduled', sqlerrm;
end;
$$;

-- ---------------------------------------------------------------------------
-- API grants
--
-- Nothing in the app works without signing in, so signed-out requests can't
-- call any RPC. Security definer functions also check auth.uid() themselves.
-- ---------------------------------------------------------------------------

revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated, service_role;


-- ===== seed.sql =====
-- Reference data: colleges shown in onboarding and college discovery.
-- Safe to run repeatedly. Students can add colleges that are missing; those
-- start unverified.

insert into public.colleges (name, short_name, slug, city, state, type, established, is_verified) values
  ('Indian Institute of Technology Bombay', 'IIT Bombay', 'iit-bombay', 'Mumbai', 'Maharashtra', 'public', 1958, true),
  ('Indian Institute of Technology Delhi', 'IIT Delhi', 'iit-delhi', 'New Delhi', 'Delhi', 'public', 1961, true),
  ('Indian Institute of Technology Madras', 'IIT Madras', 'iit-madras', 'Chennai', 'Tamil Nadu', 'public', 1959, true),
  ('Indian Institute of Technology Kanpur', 'IIT Kanpur', 'iit-kanpur', 'Kanpur', 'Uttar Pradesh', 'public', 1959, true),
  ('Indian Institute of Technology Kharagpur', 'IIT Kharagpur', 'iit-kharagpur', 'Kharagpur', 'West Bengal', 'public', 1951, true),
  ('Indian Institute of Technology Roorkee', 'IIT Roorkee', 'iit-roorkee', 'Roorkee', 'Uttarakhand', 'public', 1847, true),
  ('Indian Institute of Technology Guwahati', 'IIT Guwahati', 'iit-guwahati', 'Guwahati', 'Assam', 'public', 1994, true),
  ('Indian Institute of Technology Hyderabad', 'IIT Hyderabad', 'iit-hyderabad', 'Hyderabad', 'Telangana', 'public', 2008, true),
  ('Indian Institute of Technology (BHU) Varanasi', 'IIT BHU', 'iit-bhu', 'Varanasi', 'Uttar Pradesh', 'public', 1919, true),
  ('Indian Institute of Technology Indore', 'IIT Indore', 'iit-indore', 'Indore', 'Madhya Pradesh', 'public', 2009, true),
  ('Indian Institute of Science', 'IISc', 'iisc-bangalore', 'Bengaluru', 'Karnataka', 'public', 1909, true),
  ('Indian Institute of Science Education and Research Pune', 'IISER Pune', 'iiser-pune', 'Pune', 'Maharashtra', 'public', 2006, true),
  ('National Institute of Technology Tiruchirappalli', 'NIT Trichy', 'nit-trichy', 'Tiruchirappalli', 'Tamil Nadu', 'public', 1964, true),
  ('National Institute of Technology Karnataka', 'NITK Surathkal', 'nitk-surathkal', 'Mangaluru', 'Karnataka', 'public', 1960, true),
  ('National Institute of Technology Warangal', 'NIT Warangal', 'nit-warangal', 'Warangal', 'Telangana', 'public', 1959, true),
  ('National Institute of Technology Calicut', 'NIT Calicut', 'nit-calicut', 'Kozhikode', 'Kerala', 'public', 1961, true),
  ('National Institute of Technology Rourkela', 'NIT Rourkela', 'nit-rourkela', 'Rourkela', 'Odisha', 'public', 1961, true),
  ('Birla Institute of Technology and Science, Pilani', 'BITS Pilani', 'bits-pilani', 'Pilani', 'Rajasthan', 'deemed', 1964, true),
  ('Birla Institute of Technology, Mesra', 'BIT Mesra', 'bit-mesra', 'Ranchi', 'Jharkhand', 'deemed', 1955, true),
  ('International Institute of Information Technology, Hyderabad', 'IIIT Hyderabad', 'iiit-hyderabad', 'Hyderabad', 'Telangana', 'deemed', 1998, true),
  ('International Institute of Information Technology, Bangalore', 'IIIT Bangalore', 'iiit-bangalore', 'Bengaluru', 'Karnataka', 'deemed', 1999, true),
  ('Delhi Technological University', 'DTU', 'dtu', 'New Delhi', 'Delhi', 'public', 1941, true),
  ('Jadavpur University', 'Jadavpur University', 'jadavpur-university', 'Kolkata', 'West Bengal', 'public', 1955, true),
  ('Anna University', 'Anna University', 'anna-university', 'Chennai', 'Tamil Nadu', 'public', 1978, true),
  ('College of Engineering, Guindy', 'CEG', 'ceg-guindy', 'Chennai', 'Tamil Nadu', 'public', 1794, true),
  ('Vellore Institute of Technology', 'VIT Vellore', 'vit-vellore', 'Vellore', 'Tamil Nadu', 'deemed', 1984, true),
  ('SRM Institute of Science and Technology', 'SRM IST', 'srm-ist', 'Chennai', 'Tamil Nadu', 'deemed', 1985, true),
  ('Manipal Institute of Technology', 'MIT Manipal', 'mit-manipal', 'Manipal', 'Karnataka', 'private', 1957, true),
  ('PSG College of Technology', 'PSG Tech', 'psg-tech', 'Coimbatore', 'Tamil Nadu', 'autonomous', 1951, true),
  ('Coimbatore Institute of Technology', 'CIT', 'cit-coimbatore', 'Coimbatore', 'Tamil Nadu', 'autonomous', 1956, true),
  ('SSN College of Engineering', 'SSN', 'ssn-chennai', 'Chennai', 'Tamil Nadu', 'autonomous', 1996, true),
  ('Sri Venkateswara College of Engineering', 'SVCE', 'svce-sriperumbudur', 'Sriperumbudur', 'Tamil Nadu', 'autonomous', 1985, true),
  ('Kongu Engineering College', 'KEC', 'kongu-engineering-college', 'Perundurai', 'Tamil Nadu', 'autonomous', 1984, true),
  ('RV College of Engineering', 'RVCE', 'rvce', 'Bengaluru', 'Karnataka', 'autonomous', 1963, true),
  ('BMS College of Engineering', 'BMSCE', 'bmsce', 'Bengaluru', 'Karnataka', 'autonomous', 1946, true),
  ('PES University', 'PES University', 'pes-university', 'Bengaluru', 'Karnataka', 'private', null, true),
  ('COEP Technological University', 'COEP', 'coep', 'Pune', 'Maharashtra', 'public', 1854, true),
  ('Veermata Jijabai Technological Institute', 'VJTI', 'vjti', 'Mumbai', 'Maharashtra', 'autonomous', 1887, true),
  ('Thapar Institute of Engineering and Technology', 'Thapar', 'thapar', 'Patiala', 'Punjab', 'deemed', 1956, true),
  ('Amrita Vishwa Vidyapeetham', 'Amrita', 'amrita-coimbatore', 'Coimbatore', 'Tamil Nadu', 'deemed', null, true),
  ('University of Delhi', 'DU', 'university-of-delhi', 'New Delhi', 'Delhi', 'public', 1922, true),
  ('St. Stephen''s College', 'St. Stephen''s', 'st-stephens-college', 'New Delhi', 'Delhi', 'autonomous', 1881, true),
  ('Jawaharlal Nehru University', 'JNU', 'jnu', 'New Delhi', 'Delhi', 'public', 1969, true),
  ('University of Hyderabad', 'UoH', 'university-of-hyderabad', 'Hyderabad', 'Telangana', 'public', 1974, true),
  ('Christ University', 'Christ University', 'christ-university', 'Bengaluru', 'Karnataka', 'deemed', 1969, true),
  ('Loyola College', 'Loyola College', 'loyola-college-chennai', 'Chennai', 'Tamil Nadu', 'autonomous', 1925, true),
  ('Indian Institute of Management Ahmedabad', 'IIM Ahmedabad', 'iim-ahmedabad', 'Ahmedabad', 'Gujarat', 'public', 1961, true),
  ('All India Institute of Medical Sciences, New Delhi', 'AIIMS Delhi', 'aiims-delhi', 'New Delhi', 'Delhi', 'public', 1956, true),
  ('Lovely Professional University', 'LPU', 'lpu', 'Phagwara', 'Punjab', 'private', 2005, true),
  ('Chandigarh University', 'Chandigarh University', 'chandigarh-university', 'Mohali', 'Punjab', 'private', 2012, true)
on conflict (slug) do nothing;
