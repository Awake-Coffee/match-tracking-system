-- Account deletion that keeps the history.
--
-- Confirmed results used to reference profiles with ON DELETE RESTRICT, so a
-- member with any game could never be deleted, and cascading instead would
-- erase their opponents' history while leaving the opponents' ratings (start
-- + sum of deltas, constitution II) unexplained. So each result keeps a copy
-- of both players' display names and drops its foreign keys to profiles: the
-- ids stay as plain uuids, the names stay readable, and deleting a member
-- only removes their profile, their ratings and their open requests. Every
-- game shares the matches table, so this covers chess, backgammon and SWU.
--
-- The copies follow renames (a trigger on profiles), so history reads the
-- same as the live join it replaces, until the member is deleted.

alter table public.matches
  add column player1_name text,
  add column player2_name text;

update public.matches m
  set player1_name = (select display_name from public.profiles where id = m.player1_id),
      player2_name = (select display_name from public.profiles where id = m.player2_id);

alter table public.matches
  alter column player1_name set not null,
  alter column player2_name set not null,
  drop constraint matches_player1_id_fkey,
  drop constraint matches_player2_id_fkey,
  drop constraint matches_recorded_by_fkey;

-- Fills a new result's name copies from the two players' profiles, so
-- respond_to_match doesn't have to know about them.
create or replace function public.copy_player_names()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.player1_name := (select display_name from public.profiles where id = new.player1_id);
  new.player2_name := (select display_name from public.profiles where id = new.player2_id);
  return new;
end;
$$;

create trigger matches_copy_names before insert on public.matches
  for each row execute function public.copy_player_names();

-- A rename shows in the history, as it did with the live join.
create or replace function public.propagate_display_name()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.matches set player1_name = new.display_name where player1_id = new.id;
  update public.matches set player2_name = new.display_name where player2_id = new.id;
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
