-- create_post can ask for an anonymous post. Whether it really is anonymous
-- is decided by the posts_anonymize trigger (community posts only; always for
-- private profiles).

drop function public.create_post(text, uuid, text, text, jsonb, text[], uuid, text[], timestamptz);

create function public.create_post(
  p_type text,
  p_community_id uuid default null,
  p_title text default null,
  p_body text default null,
  p_media jsonb default '[]'::jsonb,
  p_tags text[] default '{}',
  p_event_id uuid default null,
  p_poll_options text[] default null,
  p_poll_ends_at timestamptz default null,
  p_is_anonymous boolean default false
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

  insert into public.posts (id, author_id, community_id, type, title, body, media, tags, event_id, poll_ends_at, is_anonymous)
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
    case when p_type = 'poll' then p_poll_ends_at end,
    coalesce(p_is_anonymous, false)
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

revoke execute on function public.create_post(text, uuid, text, text, jsonb, text[], uuid, text[], timestamptz, boolean) from public, anon;
grant execute on function public.create_post(text, uuid, text, text, jsonb, text[], uuid, text[], timestamptz, boolean) to authenticated, service_role;
