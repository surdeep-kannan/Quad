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
