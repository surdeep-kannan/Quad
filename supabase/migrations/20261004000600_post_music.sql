-- Music on photo posts. The song is uploaded to the media bucket and stored as
-- an 'audio' item in the post's media (with its title and which clip plays).

update storage.buckets
set allowed_mime_types = array[
  'image/jpeg', 'image/png', 'image/webp', 'image/gif',
  'video/mp4', 'video/quicktime', 'video/webm',
  'audio/mpeg', 'audio/mp3', 'audio/mp4', 'audio/x-m4a', 'audio/m4a', 'audio/aac', 'audio/x-aac',
  'audio/ogg', 'audio/opus', 'audio/wav', 'audio/x-wav', 'audio/wave', 'audio/webm', 'audio/flac', 'audio/x-flac'
]
where id = 'media';

create or replace function private.media_count(p_media jsonb, p_type text)
returns integer
language sql
immutable
set search_path = ''
as $$
  select count(*)::integer from jsonb_array_elements(coalesce(p_media, '[]'::jsonb)) m where m ->> 'type' = p_type;
$$;

-- One song per post.
alter table public.posts add constraint posts_one_song check (private.media_count(media, 'audio') <= 1);
