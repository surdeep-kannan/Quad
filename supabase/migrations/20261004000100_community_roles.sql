-- Custom community roles and permissions.
--
-- Communities define their own roles (name, colour, rank and a set of
-- permissions) and give members any number of them. A member's permissions
-- are the union of their roles' permissions; the owner has every permission.
--
-- Roles are ranked by `position`. You can only manage members, and assign or
-- edit roles, that rank below your own highest role, and you can't grant
-- permissions you don't have yourself.
--
-- Existing admins and moderators move onto the default "Admin" and
-- "Moderator" roles that every community now gets.

-- ---------------------------------------------------------------------------
-- Permissions
-- ---------------------------------------------------------------------------

-- Every permission a role can hold.
--   manage_community    edit name, description, banner, rules and visibility
--   manage_roles        create, edit, delete and assign roles below your rank
--   manage_rooms        create, edit, lock and delete rooms
--   manage_members      approve join requests and remove members
--   ban_members         ban and unban people
--   manage_posts        remove/restore posts and comments, pin, turn off comments
--   manage_messages     delete messages in rooms, post in locked rooms
--   post_announcements  post announcements that notify every member
--   manage_events       host community events and manage their registrations
--   view_reports        see and resolve the community's report queue
create or replace function private.permission_keys()
returns text[]
language sql
immutable
as $$
  select array[
    'manage_community', 'manage_roles', 'manage_rooms', 'manage_members', 'ban_members',
    'manage_posts', 'manage_messages', 'post_announcements', 'manage_events', 'view_reports'
  ]::text[];
$$;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table public.community_roles (
  id uuid primary key default gen_random_uuid(),
  community_id uuid not null references public.communities (id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 32),
  color smallint not null default 11 check (color between 0 and 11),
  position integer not null default 10 check (position between 0 and 999999),
  permissions text[] not null default '{}',
  created_at timestamptz not null default now(),
  unique (community_id, name)
);

create index community_roles_community_idx on public.community_roles (community_id, position desc);

create table public.community_member_roles (
  community_id uuid not null,
  user_id uuid not null,
  role_id uuid not null references public.community_roles (id) on delete cascade,
  assigned_at timestamptz not null default now(),
  primary key (user_id, role_id),
  foreign key (community_id, user_id) references public.community_members (community_id, user_id) on delete cascade
);

create index community_member_roles_member_idx on public.community_member_roles (community_id, user_id);
create index community_member_roles_role_idx on public.community_member_roles (role_id);

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create or replace function private.is_community_owner(p_community uuid, p_user uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.community_members m
    where m.community_id = p_community and m.user_id = p_user and m.status = 'active' and m.role = 'owner'
  );
$$;

create or replace function private.has_permission(p_community uuid, p_permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_platform_admin()
    or private.is_community_owner(p_community)
    or exists (
      select 1
      from public.community_member_roles mr
      join public.community_roles r on r.id = mr.role_id
      join public.community_members m on m.community_id = mr.community_id and m.user_id = mr.user_id
      where mr.community_id = p_community
        and mr.user_id = auth.uid()
        and m.status = 'active'
        and p_permission = any (r.permissions)
    );
$$;

create or replace function private.my_permissions(p_community uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when private.is_platform_admin() or private.is_community_owner(p_community) then private.permission_keys()
    else coalesce((
      select array_agg(distinct perm order by perm)
      from public.community_member_roles mr
      join public.community_roles r on r.id = mr.role_id
      join public.community_members m on m.community_id = mr.community_id and m.user_id = mr.user_id
      cross join lateral unnest(r.permissions) as perm
      where mr.community_id = p_community and mr.user_id = auth.uid() and m.status = 'active'
    ), '{}')
  end;
$$;

-- A member's rank: the owner is above every role; members without a role are 0.
create or replace function private.member_rank(p_community uuid, p_user uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when private.is_community_owner(p_community, p_user) then 1000000
    else coalesce((
      select max(r.position)
      from public.community_member_roles mr
      join public.community_roles r on r.id = mr.role_id
      where mr.community_id = p_community and mr.user_id = p_user
    ), 0)
  end;
$$;

create or replace function private.my_rank(p_community uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select case when private.is_platform_admin() then 2000000 else private.member_rank(p_community, auth.uid()) end;
$$;

-- The old helpers now mean specific permissions, so every existing policy
-- that uses them keeps working.
create or replace function private.is_community_mod(p_community uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_permission(p_community, 'manage_posts');
$$;

create or replace function private.is_community_admin(p_community uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_permission(p_community, 'manage_community');
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
        or (e.community_id is not null and private.has_permission(e.community_id, 'manage_events'))
        or private.is_platform_admin()
      )
  );
$$;

-- ---------------------------------------------------------------------------
-- Default roles, and moving existing admins and moderators onto them
-- ---------------------------------------------------------------------------

create or replace function private.create_default_roles(p_community uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.community_roles (community_id, name, color, position, permissions)
  values
    (p_community, 'Admin', 0, 100, private.permission_keys()),
    (p_community, 'Moderator', 4, 50, array['manage_posts', 'manage_messages', 'manage_members', 'view_reports', 'post_announcements'])
  on conflict (community_id, name) do nothing;
$$;

create or replace function private.on_community_created_roles()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.create_default_roles(new.id);
  return null;
end;
$$;

create trigger communities_default_roles
  after insert on public.communities
  for each row execute function private.on_community_created_roles();

do $$
declare
  v_community uuid;
begin
  for v_community in select id from public.communities loop
    perform private.create_default_roles(v_community);
  end loop;

  insert into public.community_member_roles (community_id, user_id, role_id)
  select m.community_id, m.user_id, r.id
  from public.community_members m
  join public.community_roles r
    on r.community_id = m.community_id
   and r.name = case m.role when 'admin' then 'Admin' when 'moderator' then 'Moderator' end
  where m.role in ('admin', 'moderator')
  on conflict do nothing;

  update public.community_members set role = 'member' where role in ('admin', 'moderator');
end;
$$;

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

alter table public.community_roles enable row level security;
alter table public.community_member_roles enable row level security;

create policy "Roles are visible with the community"
  on public.community_roles for select to authenticated
  using (private.can_view_community(community_id));

create policy "Role assignments are visible with the community"
  on public.community_member_roles for select to authenticated
  using (private.can_view_community(community_id));

revoke insert, update, delete on public.community_roles from anon, authenticated;
revoke insert, update, delete on public.community_member_roles from anon, authenticated;

-- Events: hosting and managing community events needs manage_events.
drop policy "Students create events" on public.events;
create policy "Students create events"
  on public.events for insert to authenticated
  with check (
    organizer_id = (select auth.uid())
    and (community_id is null or private.has_permission(community_id, 'manage_events'))
  );

drop policy "Organizers edit their events" on public.events;
create policy "Organizers edit their events"
  on public.events for update to authenticated
  using (organizer_id = (select auth.uid()) or (community_id is not null and private.has_permission(community_id, 'manage_events')))
  with check (organizer_id = (select auth.uid()) or (community_id is not null and private.has_permission(community_id, 'manage_events')));

drop policy "Organizers delete their events" on public.events;
create policy "Organizers delete their events"
  on public.events for delete to authenticated
  using (
    organizer_id = (select auth.uid())
    or (community_id is not null and private.has_permission(community_id, 'manage_events'))
    or private.is_platform_admin()
  );

-- Rooms: manage_rooms.
drop policy "Moderators edit rooms" on public.rooms;
create policy "Room managers edit rooms"
  on public.rooms for update to authenticated
  using (private.has_permission(community_id, 'manage_rooms'))
  with check (private.has_permission(community_id, 'manage_rooms'));

drop policy "Moderators delete rooms" on public.rooms;
create policy "Room managers delete rooms"
  on public.rooms for delete to authenticated
  using (private.has_permission(community_id, 'manage_rooms'));

-- Reports and the moderation log: view_reports.
drop policy "Reporters and moderators see reports" on public.reports;
create policy "Reporters and moderators see reports"
  on public.reports for select to authenticated
  using (
    reporter_id = (select auth.uid())
    or (community_id is not null and private.has_permission(community_id, 'view_reports'))
    or private.is_platform_admin()
  );

drop policy "Moderators see the moderation log" on public.mod_actions;
create policy "Moderators see the moderation log"
  on public.mod_actions for select to authenticated
  using ((community_id is not null and private.has_permission(community_id, 'view_reports')) or private.is_platform_admin());

-- ---------------------------------------------------------------------------
-- Functions that now check specific permissions
-- ---------------------------------------------------------------------------

create or replace function private.validate_post()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    return new;
  end if;

  if new.type = 'announcement'
     and (new.community_id is null or not private.has_permission(new.community_id, 'post_announcements')) then
    raise exception 'You don''t have permission to post announcements here' using errcode = '42501';
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
  if not private.has_permission(p_community, 'manage_rooms') then
    raise exception 'You don''t have permission to create rooms' using errcode = '42501';
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
  if not private.has_permission(v_room.community_id, 'manage_rooms') then
    raise exception 'You don''t have permission to delete rooms' using errcode = '42501';
  end if;
  if (select count(*) from public.rooms where community_id = v_room.community_id) <= 1 then
    raise exception 'A community needs at least one room' using errcode = 'P0001';
  end if;

  delete from public.conversations where id = v_room.conversation_id;
end;
$$;

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
    if v_room.is_locked and new.kind not in ('system', 'call')
       and not private.has_permission(v_room.community_id, 'manage_messages') then
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
  v_permission text := case when p_target_type = 'message' then 'manage_messages' else 'manage_posts' end;
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
  if not (private.is_platform_admin() or (v_community is not null and private.has_permission(v_community, v_permission))) then
    raise exception 'You don''t have permission to do that' using errcode = '42501';
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
  if not (private.is_platform_admin() or (v_report.community_id is not null and private.has_permission(v_report.community_id, 'view_reports'))) then
    raise exception 'You don''t have permission to review reports' using errcode = '42501';
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

-- Approve requests and unban (manage_members / ban_members) or ban
-- (ban_members). You can only act on people ranked below you.
create or replace function public.set_member_status(p_community uuid, p_user uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current text;
begin
  if p_status not in ('active', 'banned') then
    raise exception 'Unknown status' using errcode = '22023';
  end if;
  if p_user = auth.uid() then
    raise exception 'You can''t change your own membership' using errcode = '42501';
  end if;

  select status into v_current from public.community_members where community_id = p_community and user_id = p_user;

  if p_status = 'banned' or v_current = 'banned' then
    if not private.has_permission(p_community, 'ban_members') then
      raise exception 'You don''t have permission to ban or unban people' using errcode = '42501';
    end if;
  elsif not private.has_permission(p_community, 'manage_members') then
    raise exception 'You don''t have permission to approve members' using errcode = '42501';
  end if;
  if private.member_rank(p_community, p_user) >= private.my_rank(p_community) then
    raise exception 'You can''t moderate someone ranked at or above you' using errcode = '42501';
  end if;

  if v_current is null then
    if p_status = 'banned' then
      insert into public.community_members (community_id, user_id, role, status)
      values (p_community, p_user, 'member', 'banned');
    else
      raise exception 'That person isn''t in this community' using errcode = 'P0002';
    end if;
  else
    update public.community_members set status = p_status where community_id = p_community and user_id = p_user;
    if p_status = 'banned' then
      delete from public.community_member_roles where community_id = p_community and user_id = p_user;
    end if;
  end if;
end;
$$;

-- Removes a member (they can join again) or declines a join request.
create or replace function public.remove_member(p_community uuid, p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.has_permission(p_community, 'manage_members') then
    raise exception 'You don''t have permission to remove members' using errcode = '42501';
  end if;
  if p_user = auth.uid() then
    raise exception 'Use "Leave community" to leave' using errcode = '22023';
  end if;
  if private.member_rank(p_community, p_user) >= private.my_rank(p_community) then
    raise exception 'You can''t remove someone ranked at or above you' using errcode = '42501';
  end if;

  delete from public.community_members
  where community_id = p_community and user_id = p_user and status <> 'banned';
end;
$$;

-- Replaced by role assignment below.
drop function if exists public.set_member_role(uuid, uuid, text);

-- Join requests go to everyone who can approve them.
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
      and (
        m.role = 'owner'
        or exists (
          select 1 from public.community_member_roles mr
          join public.community_roles r on r.id = mr.role_id
          where mr.community_id = m.community_id and mr.user_id = m.user_id and 'manage_members' = any (r.permissions)
        )
      );
  elsif tg_op = 'UPDATE' and old.status = 'pending' and new.status = 'active' then
    perform private.notify(
      p_user := new.user_id, p_actor := auth.uid(), p_type := 'community_join_approved', p_community := new.community_id
    );
  end if;
  return null;
end;
$$;

-- Tell people when they're given a role.
create or replace function private.notify_on_role_assigned()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.notify(
    p_user := new.user_id, p_actor := auth.uid(), p_type := 'community_role',
    p_community := new.community_id,
    p_data := jsonb_build_object('role', (select name from public.community_roles where id = new.role_id))
  );
  return null;
end;
$$;

create trigger community_member_roles_notify
  after insert on public.community_member_roles
  for each row execute function private.notify_on_role_assigned();

-- ---------------------------------------------------------------------------
-- Role management RPCs
-- ---------------------------------------------------------------------------

-- Throws unless every permission is real and the caller holds it.
create or replace function private.check_grantable(p_community uuid, p_permissions text[])
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_unknown text[];
  v_missing text[];
begin
  select array_agg(p) into v_unknown from unnest(coalesce(p_permissions, '{}')) p where p <> all (private.permission_keys());
  if v_unknown is not null then
    raise exception 'Unknown permission: %', array_to_string(v_unknown, ', ') using errcode = '22023';
  end if;
  select array_agg(p) into v_missing from unnest(coalesce(p_permissions, '{}')) p where p <> all (private.my_permissions(p_community));
  if v_missing is not null then
    raise exception 'You can''t give permissions you don''t have' using errcode = '42501';
  end if;
end;
$$;

create or replace function public.create_community_role(
  p_community uuid,
  p_name text,
  p_color integer default 11,
  p_permissions text[] default '{}'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not private.has_permission(p_community, 'manage_roles') then
    raise exception 'You don''t have permission to manage roles' using errcode = '42501';
  end if;
  perform private.check_grantable(p_community, p_permissions);

  -- New roles start low, and always below the creator.
  insert into public.community_roles (community_id, name, color, position, permissions)
  values (
    p_community,
    trim(p_name),
    coalesce(p_color, 11),
    greatest(0, least(10, private.my_rank(p_community) - 1)),
    (select coalesce(array_agg(distinct p), '{}') from unnest(coalesce(p_permissions, '{}')) p)
  )
  returning id into v_id;
  return v_id;
exception when unique_violation then
  raise exception 'A role with that name already exists' using errcode = '23505';
end;
$$;

create or replace function public.update_community_role(
  p_role uuid,
  p_name text,
  p_color integer,
  p_permissions text[],
  p_position integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role public.community_roles%rowtype;
  v_rank integer;
begin
  select * into v_role from public.community_roles where id = p_role;
  if not found then
    raise exception 'Role not found' using errcode = 'P0002';
  end if;
  if not private.has_permission(v_role.community_id, 'manage_roles') then
    raise exception 'You don''t have permission to manage roles' using errcode = '42501';
  end if;
  v_rank := private.my_rank(v_role.community_id);
  if v_role.position >= v_rank then
    raise exception 'You can only edit roles ranked below yours' using errcode = '42501';
  end if;
  if p_position is not null and (p_position < 0 or p_position >= v_rank) then
    raise exception 'Roles you edit must stay below your own rank' using errcode = '42501';
  end if;
  perform private.check_grantable(v_role.community_id, p_permissions);

  update public.community_roles set
    name = coalesce(nullif(trim(p_name), ''), name),
    color = coalesce(p_color, color),
    permissions = (select coalesce(array_agg(distinct p), '{}') from unnest(coalesce(p_permissions, '{}')) p),
    position = coalesce(p_position, position)
  where id = p_role;
exception when unique_violation then
  raise exception 'A role with that name already exists' using errcode = '23505';
end;
$$;

create or replace function public.delete_community_role(p_role uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role public.community_roles%rowtype;
begin
  select * into v_role from public.community_roles where id = p_role;
  if not found then
    return;
  end if;
  if not private.has_permission(v_role.community_id, 'manage_roles') then
    raise exception 'You don''t have permission to manage roles' using errcode = '42501';
  end if;
  if v_role.position >= private.my_rank(v_role.community_id) then
    raise exception 'You can only delete roles ranked below yours' using errcode = '42501';
  end if;
  delete from public.community_roles where id = p_role;
end;
$$;

-- Sets exactly which roles a member has. Only roles below your rank can be
-- added or removed, and only for members ranked below you.
create or replace function public.set_member_roles(p_community uuid, p_user uuid, p_role_ids uuid[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rank integer := private.my_rank(p_community);
  v_wanted uuid[] := coalesce(p_role_ids, '{}');
begin
  if not private.has_permission(p_community, 'manage_roles') then
    raise exception 'You don''t have permission to manage roles' using errcode = '42501';
  end if;
  if p_user = auth.uid() and not private.is_platform_admin() then
    raise exception 'You can''t change your own roles' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.community_members where community_id = p_community and user_id = p_user and status = 'active'
  ) then
    raise exception 'That person isn''t an active member' using errcode = 'P0002';
  end if;
  if private.member_rank(p_community, p_user) >= v_rank then
    raise exception 'You can''t change roles for someone ranked at or above you' using errcode = '42501';
  end if;
  if exists (
    select 1 from unnest(v_wanted) w
    left join public.community_roles r on r.id = w and r.community_id = p_community
    where r.id is null or r.position >= v_rank
  ) then
    raise exception 'You can only give roles ranked below yours' using errcode = '42501';
  end if;

  delete from public.community_member_roles mr
  using public.community_roles r
  where mr.community_id = p_community and mr.user_id = p_user and r.id = mr.role_id
    and r.position < v_rank and mr.role_id <> all (v_wanted);

  insert into public.community_member_roles (community_id, user_id, role_id)
  select p_community, p_user, w from unnest(v_wanted) w
  on conflict do nothing;
end;
$$;

-- ---------------------------------------------------------------------------
-- The viewer's permissions on community pages
-- ---------------------------------------------------------------------------

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
  m.status as my_status,
  case when m.status = 'active' or private.is_platform_admin() then private.my_permissions(c.id) else '{}'::text[] end as my_permissions,
  case when m.status = 'active' or private.is_platform_admin() then private.my_rank(c.id) else 0 end as my_rank
from public.communities c
left join public.colleges col on col.id = c.college_id
left join public.community_members m on m.community_id = c.id and m.user_id = auth.uid();

revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated, service_role;
