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
