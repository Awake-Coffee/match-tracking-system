-- Minimal stand-in for the pieces of Supabase the migration relies on, so the
-- migration can be tested against a plain Postgres. Not used in production.
-- Roles are cluster-wide, so a second test database finds them already there.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
    create role authenticated nologin;
  end if;
end $$;

create schema auth;
grant usage on schema auth to anon, authenticated;
grant usage on schema public to anon, authenticated;

create table auth.users (
  id uuid primary key default gen_random_uuid(),
  email text,
  raw_user_meta_data jsonb not null default '{}'::jsonb
);

create function auth.uid() returns uuid
language sql stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;
grant execute on function auth.uid() to anon, authenticated;
