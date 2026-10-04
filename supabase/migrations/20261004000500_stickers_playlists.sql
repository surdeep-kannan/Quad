-- Stickers in chat, liked videos, and video playlists.

-- ---------------------------------------------------------------------------
-- Stickers
-- ---------------------------------------------------------------------------

-- A sticker message stores the sticker's id ("pack/name") in body. The app
-- ships the sticker art, so nothing is uploaded.
alter table public.messages drop constraint messages_kind_check;
alter table public.messages add constraint messages_kind_check
  check (kind in ('text', 'image', 'file', 'post', 'event', 'system', 'call', 'sticker'));
alter table public.messages add constraint messages_sticker_body
  check (kind <> 'sticker' or body ~ '^[a-z0-9-]{1,30}/[a-z0-9-]{1,40}$');

drop policy "Members send messages" on public.messages;
create policy "Members send messages"
  on public.messages for insert to authenticated
  with check (
    (sender_id = (select auth.uid()) or (sender_id is null and is_anonymous and anon_name is not null))
    and kind in ('text', 'image', 'file', 'post', 'event', 'sticker')
    and private.is_conversation_member(conversation_id)
  );

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
    when 'sticker' then 'Sticker'
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

-- Stickers can be sent anonymously in rooms too.
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
  if v_type = 'room' and new.kind in ('text', 'image', 'file', 'sticker')
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

-- ---------------------------------------------------------------------------
-- Liked videos
-- ---------------------------------------------------------------------------

-- Reels and videos you reacted to, most recently liked first.
create or replace function public.liked_videos(p_limit integer default 30, p_offset integer default 0)
returns setof public.post_details
language sql
stable
security invoker
set search_path = ''
as $$
  select d.*
  from public.post_reactions r
  join public.post_details d on d.id = r.post_id
  where r.user_id = (select auth.uid()) and d.type in ('reel', 'video') and not d.is_removed
  order by r.created_at desc
  limit least(greatest(p_limit, 1), 100) offset greatest(p_offset, 0);
$$;

-- ---------------------------------------------------------------------------
-- Playlists: your own named collections of reels and videos (private)
-- ---------------------------------------------------------------------------

create table public.playlists (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 60),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (owner_id, name)
);

create index playlists_owner_idx on public.playlists (owner_id, updated_at desc);

create table public.playlist_items (
  playlist_id uuid not null references public.playlists (id) on delete cascade,
  post_id uuid not null references public.posts (id) on delete cascade,
  added_at timestamptz not null default now(),
  primary key (playlist_id, post_id)
);

create index playlist_items_post_idx on public.playlist_items (post_id);
create index playlist_items_order_idx on public.playlist_items (playlist_id, added_at desc);

alter table public.playlists enable row level security;
alter table public.playlist_items enable row level security;

create policy "Owners manage their playlists"
  on public.playlists for all to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

create policy "Owners see their playlist items"
  on public.playlist_items for select to authenticated
  using (exists (select 1 from public.playlists p where p.id = playlist_id and p.owner_id = (select auth.uid())));

-- Only reels and videos you can see go into your own playlists.
create policy "Owners add videos to their playlists"
  on public.playlist_items for insert to authenticated
  with check (
    exists (select 1 from public.playlists p where p.id = playlist_id and p.owner_id = (select auth.uid()))
    and exists (select 1 from public.posts v where v.id = post_id and v.type in ('reel', 'video'))
  );

create policy "Owners remove videos from their playlists"
  on public.playlist_items for delete to authenticated
  using (exists (select 1 from public.playlists p where p.id = playlist_id and p.owner_id = (select auth.uid())));

revoke all on public.playlists, public.playlist_items from anon, authenticated;
grant select, delete on public.playlists to authenticated;
grant insert (name) on public.playlists to authenticated;
grant update (name) on public.playlists to authenticated;
grant select, delete on public.playlist_items to authenticated;
grant insert (playlist_id, post_id) on public.playlist_items to authenticated;

-- Keeps the lists a sensible size.
create or replace function private.guard_playlists()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_table_name = 'playlists' then
    new.name := trim(new.name);
    if tg_op = 'INSERT' and (select count(*) from public.playlists where owner_id = new.owner_id) >= 100 then
      raise exception 'You can have up to 100 playlists' using errcode = 'P0001';
    end if;
    new.updated_at := now();
  elsif (select count(*) from public.playlist_items where playlist_id = new.playlist_id) >= 1000 then
    raise exception 'A playlist can hold up to 1000 videos' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create trigger playlists_guard
  before insert or update on public.playlists
  for each row execute function private.guard_playlists();

create trigger playlist_items_guard
  before insert on public.playlist_items
  for each row execute function private.guard_playlists();

-- Adding or removing a video moves the playlist to the top of your list.
create or replace function private.touch_playlist()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.playlists set updated_at = now()
  where id = coalesce(new.playlist_id, old.playlist_id);
  return null;
end;
$$;

create trigger playlist_items_touch
  after insert or delete on public.playlist_items
  for each row execute function private.touch_playlist();

-- Your playlists with their size and cover. Pass p_post to also learn which
-- playlists already contain that video.
create or replace function public.my_playlists(p_post uuid default null)
returns table (
  id uuid,
  name text,
  items_count integer,
  cover jsonb,
  contains_post boolean,
  updated_at timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    pl.id,
    pl.name,
    (select count(*)::integer from public.playlist_items i where i.playlist_id = pl.id),
    (
      select v.media -> 0
      from public.playlist_items i
      join public.posts v on v.id = i.post_id
      where i.playlist_id = pl.id
      order by i.added_at desc
      limit 1
    ),
    p_post is not null and exists (
      select 1 from public.playlist_items i where i.playlist_id = pl.id and i.post_id = p_post
    ),
    pl.updated_at
  from public.playlists pl
  where pl.owner_id = (select auth.uid())
  order by pl.updated_at desc;
$$;

-- A playlist's videos, newest additions first.
create or replace function public.playlist_videos(p_playlist uuid, p_limit integer default 50, p_offset integer default 0)
returns setof public.post_details
language sql
stable
security invoker
set search_path = ''
as $$
  select d.*
  from public.playlist_items i
  join public.post_details d on d.id = i.post_id
  where i.playlist_id = p_playlist
  order by i.added_at desc
  limit least(greatest(p_limit, 1), 200) offset greatest(p_offset, 0);
$$;

revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated, service_role;
