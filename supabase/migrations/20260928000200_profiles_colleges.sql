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
