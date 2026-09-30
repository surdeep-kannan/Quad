-- Foundation: extensions, the private helper schema and shared utilities.
--
-- Functions in `private` are used by RLS policies and triggers. The schema is
-- not exposed through the Data API, so none of them can be called as RPCs.

create schema if not exists extensions;
create extension if not exists pg_trgm with schema extensions;

create schema if not exists private;
grant usage on schema private to anon, authenticated, service_role;

-- Keeps `updated_at` current. Attach with `before update of <columns>` so that
-- counter updates made by triggers don't bump it.
create or replace function private.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- Parses a uuid without raising. Used to read ids out of storage paths and
-- realtime topics, which are user-controlled strings.
create or replace function private.try_uuid(value text)
returns uuid
language sql
immutable
as $$
  select case
    when value ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then value::uuid
  end;
$$;

-- Escapes LIKE wildcards in user input and wraps it for a contains-match.
create or replace function private.contains_pattern(value text)
returns text
language sql
immutable
as $$
  select '%' || replace(replace(replace(trim(coalesce(value, '')), '\', '\\'), '%', '\%'), '_', '\_') || '%';
$$;

-- Same as contains_pattern, for a starts-with match.
create or replace function private.prefix_pattern(value text)
returns text
language sql
immutable
as $$
  select replace(replace(replace(trim(coalesce(value, '')), '\', '\\'), '%', '\%'), '_', '\_') || '%';
$$;

create or replace function private.slugify(value text)
returns text
language sql
immutable
as $$
  select trim(both '-' from regexp_replace(lower(coalesce(value, '')), '[^a-z0-9]+', '-', 'g'));
$$;
