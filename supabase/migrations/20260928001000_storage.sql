-- Storage buckets.
--
--   avatars  public   <user id>/<file>                          profile photos
--   media    public   <user id>/<file>                          post images and videos, reels, posters,
--                                                               community icons and banners
--   chat     private  <conversation id>/<user id>/<file>        chat attachments, read via signed URLs

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('avatars', 'avatars', true, 5242880, array['image/jpeg', 'image/png', 'image/webp', 'image/gif']),
  ('media', 'media', true, 52428800, array[
    'image/jpeg', 'image/png', 'image/webp', 'image/gif', 'video/mp4', 'video/quicktime', 'video/webm'
  ]),
  ('chat', 'chat', false, 26214400, null)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Students upload to their own folder" on storage.objects;
create policy "Students upload to their own folder"
  on storage.objects for insert to authenticated
  with check (
    bucket_id in ('avatars', 'media')
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "Students manage their own files" on storage.objects;
create policy "Students manage their own files"
  on storage.objects for update to authenticated
  using (
    bucket_id in ('avatars', 'media')
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "Students delete their own files" on storage.objects;
create policy "Students delete their own files"
  on storage.objects for delete to authenticated
  using (
    bucket_id in ('avatars', 'media')
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "Chat members upload attachments" on storage.objects;
create policy "Chat members upload attachments"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'chat'
    and (storage.foldername(name))[2] = (select auth.uid())::text
    and private.is_conversation_member(private.try_uuid((storage.foldername(name))[1]))
  );

drop policy if exists "Chat members read attachments" on storage.objects;
create policy "Chat members read attachments"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'chat'
    and private.is_conversation_member(private.try_uuid((storage.foldername(name))[1]))
  );
