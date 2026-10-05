-- Profile photos. Each member has at most one, in the public avatars bucket
-- under their own id, so a profile can never point at an image outside the
-- app. avatar_updated_at says whether there is one and busts caches when it
-- changes; the app builds the URL from the id.

alter table public.profiles add column avatar_updated_at timestamptz;
grant update (avatar_updated_at) on public.profiles to authenticated;

-- Photos are shrunk to 512 px in the browser, so 1 MB is generous.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 1048576, array['image/jpeg', 'image/png', 'image/webp']);

-- Reads go through the public URL; select is only here because uploading
-- over an existing photo (upsert) needs it.
create policy "Members see their own photo"
  on storage.objects for select to authenticated
  using (bucket_id = 'avatars' and name = auth.uid()::text);

create policy "Members upload their own photo"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and name = auth.uid()::text);

create policy "Members replace their own photo"
  on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and name = auth.uid()::text)
  with check (bucket_id = 'avatars' and name = auth.uid()::text);

-- Storage refuses deletes made in SQL, so the app removes the photo before
-- delete_my_account.
create policy "Members remove their own photo"
  on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and name = auth.uid()::text);
