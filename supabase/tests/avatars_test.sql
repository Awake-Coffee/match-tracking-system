-- Members can upload, replace and remove only their own photo, and stamp
-- only their own profile with it. Each block raises on failure. Rolled back
-- so other tests see an empty database.
\set ON_ERROR_STOP on
begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000a8', 'ana@avatar.example', '{"display_name":"Avatar Ana"}'),
  ('00000000-0000-0000-0000-0000000000b8', 'bo@avatar.example',  '{"display_name":"Avatar Bo"}');

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b8', false);
insert into storage.objects (bucket_id, name) values ('avatars', '00000000-0000-0000-0000-0000000000b8');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a8', false);
insert into storage.objects (bucket_id, name) values ('avatars', '00000000-0000-0000-0000-0000000000a8');
update storage.objects set name = name where name = '00000000-0000-0000-0000-0000000000a8';
update public.profiles set avatar_updated_at = now() where id = '00000000-0000-0000-0000-0000000000a8';

do $$
begin
  insert into storage.objects (bucket_id, name) values ('avatars', 'someone-else');
  assert false, 'a photo must be named after its uploader';
exception when insufficient_privilege then null;
end $$;

do $$
begin
  insert into storage.objects (bucket_id, name) values ('avatars', '00000000-0000-0000-0000-0000000000a8/extra');
  assert false, 'one photo per member, at the top of the bucket';
exception when insufficient_privilege then null;
end $$;

-- Bo's photo and profile are out of Ana's reach: RLS skips the rows.
update storage.objects set name = 'stolen' where name = '00000000-0000-0000-0000-0000000000b8';
delete from storage.objects where name = '00000000-0000-0000-0000-0000000000b8';
update public.profiles set avatar_updated_at = now() where id = '00000000-0000-0000-0000-0000000000b8';

delete from storage.objects where name = '00000000-0000-0000-0000-0000000000a8';

reset role;
do $$
begin
  assert exists (select 1 from storage.objects where name = '00000000-0000-0000-0000-0000000000b8'),
    'Bo''s photo survives Ana';
  assert not exists (select 1 from storage.objects where name = '00000000-0000-0000-0000-0000000000a8'),
    'Ana removed her own photo';
  assert (select avatar_updated_at is not null from public.profiles where id = '00000000-0000-0000-0000-0000000000a8'),
    'Ana stamped her profile';
  assert (select avatar_updated_at is null from public.profiles where id = '00000000-0000-0000-0000-0000000000b8'),
    'Ana can''t stamp Bo''s profile';
end $$;

rollback;
\echo 'avatars_test: all assertions passed'
