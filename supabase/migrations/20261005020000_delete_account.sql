-- Account deletion that keeps the history.
--
-- Confirmed results used to reference profiles with ON DELETE RESTRICT, so a
-- member with any game could never be deleted, and cascading instead would
-- erase their opponents' history while leaving the opponents' ratings (start
-- + sum of deltas, constitution II) unexplained. So each result keeps a copy
-- of both players' display names and drops its foreign keys to profiles: the
-- ids stay as plain uuids, the names stay readable, and deleting a member
-- only removes their profile, their ratings and their open requests.
--
-- The copies follow renames (a trigger on profiles), so history reads the
-- same as the live join it replaces, until the member is deleted.

alter table public.matches
  add column white_name text,
  add column black_name text;
alter table public.backgammon_matches
  add column winner_name text,
  add column loser_name text;
alter table public.swu_matches
  add column reporter_name text,
  add column respondent_name text;

update public.matches m
  set white_name = (select display_name from public.profiles where id = m.white_id),
      black_name = (select display_name from public.profiles where id = m.black_id);
update public.backgammon_matches m
  set winner_name = (select display_name from public.profiles where id = m.winner_id),
      loser_name = (select display_name from public.profiles where id = m.loser_id);
update public.swu_matches m
  set reporter_name = (select display_name from public.profiles where id = m.reporter_id),
      respondent_name = (select display_name from public.profiles where id = m.respondent_id);

alter table public.matches
  alter column white_name set not null,
  alter column black_name set not null,
  drop constraint matches_white_id_fkey,
  drop constraint matches_black_id_fkey,
  drop constraint matches_recorded_by_fkey;
alter table public.backgammon_matches
  alter column winner_name set not null,
  alter column loser_name set not null,
  drop constraint backgammon_matches_winner_id_fkey,
  drop constraint backgammon_matches_loser_id_fkey,
  drop constraint backgammon_matches_recorded_by_fkey;
alter table public.swu_matches
  alter column reporter_name set not null,
  alter column respondent_name set not null,
  drop constraint swu_matches_reporter_id_fkey,
  drop constraint swu_matches_respondent_id_fkey;

-- Fills a new result's name copies from the two players' profiles. The
-- result RPCs don't have to know about them: TG_ARGV holds the two side
-- prefixes ('white', 'black').
create or replace function public.copy_player_names()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  row_json jsonb := to_jsonb(new);
  first_side text := tg_argv[0];
  second_side text := tg_argv[1];
begin
  new := jsonb_populate_record(new, jsonb_build_object(
    first_side || '_name',
    (select display_name from public.profiles where id = (row_json ->> (first_side || '_id'))::uuid),
    second_side || '_name',
    (select display_name from public.profiles where id = (row_json ->> (second_side || '_id'))::uuid)));
  return new;
end;
$$;

create trigger matches_copy_names before insert on public.matches
  for each row execute function public.copy_player_names('white', 'black');
create trigger backgammon_matches_copy_names before insert on public.backgammon_matches
  for each row execute function public.copy_player_names('winner', 'loser');
create trigger swu_matches_copy_names before insert on public.swu_matches
  for each row execute function public.copy_player_names('reporter', 'respondent');

-- A rename shows in the history, as it did with the live join.
create or replace function public.propagate_display_name()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.matches set white_name = new.display_name where white_id = new.id;
  update public.matches set black_name = new.display_name where black_id = new.id;
  update public.backgammon_matches set winner_name = new.display_name where winner_id = new.id;
  update public.backgammon_matches set loser_name = new.display_name where loser_id = new.id;
  update public.swu_matches set reporter_name = new.display_name where reporter_id = new.id;
  update public.swu_matches set respondent_name = new.display_name where respondent_id = new.id;
  return new;
end;
$$;

create trigger profiles_propagate_name after update of display_name on public.profiles
  for each row when (old.display_name is distinct from new.display_name)
  execute function public.propagate_display_name();

-- ---------------------------------------------------------------------------
-- delete_my_account
-- ---------------------------------------------------------------------------

-- Deletes the caller's login; the profile (and with it their ratings and any
-- open or declined requests) goes by cascade. Confirmed results stay in the
-- history under the name they had when the account was deleted. Takes no
-- arguments: nobody can delete anybody else.
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in first' using errcode = '28000';
  end if;
  delete from auth.users where id = auth.uid();
end;
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
