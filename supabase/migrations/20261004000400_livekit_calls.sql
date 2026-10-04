-- Calls through LiveKit.
--
-- The app asks `call_token` for a short-lived LiveKit access token. The
-- database checks that the student belongs to the call's conversation (or the
-- room's community) and signs the token with the LiveKit API secret, which
-- lives in Supabase Vault and never reaches the app.
--
-- Vault secrets (set by `npm run livekit:setup` in tools/):
--   livekit_url, livekit_api_key, livekit_api_secret

-- Base64url without padding, as JWTs use.
create or replace function private.base64url(p_data bytea)
returns text
language sql
immutable
set search_path = ''
as $$
  select translate(rtrim(replace(encode(p_data, 'base64'), E'\n', ''), '='), '+/', '-_');
$$;

create or replace function private.livekit_secret(p_name text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select decrypted_secret from vault.decrypted_secrets where name = p_name limit 1;
$$;

-- An HS256 JWT signed with the LiveKit API secret. `iss` is the API key.
create or replace function private.livekit_jwt(p_claims jsonb)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_key text := private.livekit_secret('livekit_api_key');
  v_secret text := private.livekit_secret('livekit_api_secret');
  v_signing text;
begin
  if v_key is null or v_secret is null then
    raise exception 'Calls aren''t set up yet' using errcode = 'P0001';
  end if;
  v_signing := private.base64url(convert_to('{"alg":"HS256","typ":"JWT"}', 'UTF8'))
    || '.' || private.base64url(convert_to((p_claims || jsonb_build_object('iss', v_key))::text, 'UTF8'));
  return v_signing || '.'
    || private.base64url(extensions.hmac(convert_to(v_signing, 'UTF8'), convert_to(v_secret, 'UTF8'), 'sha256'));
end;
$$;

-- A token for joining a call (p_call) or a community room's voice/video
-- (p_room). Returns the server URL, the token and how you appear in the call.
-- Private profiles join room calls under a fresh anonymous name.
create or replace function public.call_token(p_call uuid default null, p_room uuid default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_room_name text;
  v_identity text;
  v_name text;
  v_metadata jsonb := '{}'::jsonb;
  v_profile public.profiles%rowtype;
  v_now bigint := extract(epoch from now())::bigint;
  v_url text := private.livekit_secret('livekit_url');
begin
  if v_me is null then
    raise exception 'Sign in first' using errcode = '28000';
  end if;
  if (p_call is null) = (p_room is null) then
    raise exception 'Pass a call or a room' using errcode = '22023';
  end if;
  if v_url is null then
    raise exception 'Calls aren''t set up yet' using errcode = 'P0001';
  end if;

  select * into v_profile from public.profiles where id = v_me;

  if p_call is not null then
    if not exists (
      select 1 from public.calls c
      where c.id = p_call
        and c.status in ('ringing', 'ongoing')
        and private.is_conversation_member(c.conversation_id)
    ) then
      raise exception 'This call has ended or isn''t yours to join' using errcode = '42501';
    end if;
    v_room_name := 'call-' || p_call;
  else
    if not exists (
      select 1 from public.rooms r
      where r.id = p_room and private.is_conversation_member(r.conversation_id)
    ) then
      raise exception 'Join the community to use this room' using errcode = '42501';
    end if;
    v_room_name := 'room-' || p_room;
  end if;

  if p_room is not null and private.is_private_user(v_me) then
    v_identity := 'anon-' || replace(gen_random_uuid()::text, '-', '');
    v_name := private.anonymous_name();
  else
    v_identity := v_me::text;
    v_name := coalesce(nullif(v_profile.full_name, ''), v_profile.username, 'Student');
    v_metadata := jsonb_build_object('username', v_profile.username, 'avatar_url', v_profile.avatar_url);
  end if;

  return jsonb_build_object(
    'url', v_url,
    'room', v_room_name,
    'identity', v_identity,
    'name', v_name,
    'token', private.livekit_jwt(jsonb_build_object(
      'sub', v_identity,
      'name', v_name,
      'metadata', v_metadata::text,
      'nbf', v_now - 10,
      'exp', v_now + 2 * 60 * 60,
      'video', jsonb_build_object(
        'room', v_room_name,
        'roomJoin', true,
        'canPublish', true,
        'canSubscribe', true,
        'canPublishData', true
      )
    ))
  );
end;
$$;

-- Only call_token (which runs as the owner) may read the secrets.
revoke execute on function private.livekit_secret(text), private.livekit_jwt(jsonb) from public, anon, authenticated;

revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated, service_role;
