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
