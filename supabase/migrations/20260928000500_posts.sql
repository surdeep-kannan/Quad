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
