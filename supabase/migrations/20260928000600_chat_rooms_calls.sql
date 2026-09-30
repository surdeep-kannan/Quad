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
