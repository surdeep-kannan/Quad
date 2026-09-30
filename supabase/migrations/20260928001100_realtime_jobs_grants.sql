-- Realtime publication, private channel authorization, scheduled jobs and the
-- final API grants.

-- ---------------------------------------------------------------------------
-- Postgres changes
-- ---------------------------------------------------------------------------

do $$
declare
  v_table text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise notice 'supabase_realtime publication not found; skipping';
    return;
  end if;

  foreach v_table in array array['messages', 'conversations', 'conversation_members', 'notifications', 'calls'] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = v_table
    ) then
      execute format('alter publication supabase_realtime add table public.%I', v_table);
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Private channels (broadcast and presence)
--
--   online            app-wide presence, any signed-in student
--   chat:<id>         typing indicators for a conversation, members only
--   call:<id>         WebRTC signaling for a call, conversation members only
--   voice:<room id>   voice/video in a community room, room members only
--   user:<id>         a student's own channel (incoming calls)
-- ---------------------------------------------------------------------------

create or replace function private.can_use_topic(p_topic text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_kind text := split_part(coalesce(p_topic, ''), ':', 1);
  v_id uuid := private.try_uuid(split_part(coalesce(p_topic, ''), ':', 2));
begin
  if auth.uid() is null then
    return false;
  end if;
  if p_topic = 'online' then
    return true;
  end if;
  if v_id is null then
    return false;
  end if;

  return case v_kind
    when 'chat' then private.is_conversation_member(v_id)
    when 'call' then exists (
      select 1 from public.calls c where c.id = v_id and private.is_conversation_member(c.conversation_id)
    )
    when 'voice' then exists (
      select 1 from public.rooms r where r.id = v_id and private.is_conversation_member(r.conversation_id)
    )
    when 'user' then v_id = auth.uid()
    else false
  end;
end;
$$;

do $$
begin
  if to_regclass('realtime.messages') is null then
    raise notice 'realtime.messages not found; skipping channel policies';
    return;
  end if;

  execute 'drop policy if exists "Students join allowed channels" on realtime.messages';
  execute $policy$
    create policy "Students join allowed channels"
      on realtime.messages for select to authenticated
      using (private.can_use_topic((select realtime.topic())))
  $policy$;

  execute 'drop policy if exists "Students send on allowed channels" on realtime.messages';
  execute $policy$
    create policy "Students send on allowed channels"
      on realtime.messages for insert to authenticated
      with check (private.can_use_topic((select realtime.topic())))
  $policy$;
end;
$$;

-- ---------------------------------------------------------------------------
-- Scheduled jobs (pg_cron, where the project has it)
-- ---------------------------------------------------------------------------

do $$
begin
  create extension if not exists pg_cron;
  perform cron.schedule('quad-event-reminders', '*/10 * * * *', 'select private.send_event_reminders()');
  perform cron.schedule('quad-college-stats', '17 * * * *', 'select private.refresh_college_stats()');
exception when others then
  raise notice 'pg_cron unavailable (%); event reminders and hourly college stats are not scheduled', sqlerrm;
end;
$$;

-- ---------------------------------------------------------------------------
-- API grants
--
-- Nothing in the app works without signing in, so signed-out requests can't
-- call any RPC. Security definer functions also check auth.uid() themselves.
-- ---------------------------------------------------------------------------

revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated, service_role;
