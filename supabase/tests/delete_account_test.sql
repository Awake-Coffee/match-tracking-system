-- Deleting an account removes the login, profile and open requests, keeps
-- confirmed results in every game under the recorded names, and leaves the
-- opponent's rating alone. Each block raises on failure. Rolled back so
-- other tests see an empty database.
\set ON_ERROR_STOP on
begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000a7', 'ana@delete.example', '{"display_name":"Delete Ana"}'),
  ('00000000-0000-0000-0000-0000000000b7', 'bo@delete.example',  '{"display_name":"Delete Bo"}');

set role authenticated;

-- Ana and Bo play one confirmed game in each game; Ana leaves one more of
-- each waiting for Bo.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a7', false);
select public.request_chess_match(
  '00000000-0000-0000-0000-0000000000b7', 'white', 'win', 1::smallint, null, null, true);
select public.request_backgammon_match(
  '00000000-0000-0000-0000-0000000000b7', 5::smallint, 5::smallint, 2::smallint, true);
select public.request_swu_match(
  '00000000-0000-0000-0000-0000000000b7', 2::smallint, 0::smallint, true);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b7', false);
select public.respond_to_chess_match((select max(id) from public.match_requests), true);
select public.respond_to_backgammon_match((select max(id) from public.backgammon_match_requests), true);
select public.respond_to_swu_match((select max(id) from public.swu_match_requests), true);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a7', false);
select public.request_chess_match(
  '00000000-0000-0000-0000-0000000000b7', 'white', 'win', 1::smallint, null, null, true);
select public.request_backgammon_match(
  '00000000-0000-0000-0000-0000000000b7', 5::smallint, 5::smallint, 2::smallint, true);
select public.request_swu_match(
  '00000000-0000-0000-0000-0000000000b7', 2::smallint, 0::smallint, true);

do $$
begin
  assert (select white_name = 'Delete Ana' and black_name = 'Delete Bo'
    from public.matches where white_id = '00000000-0000-0000-0000-0000000000a7'), 'chess result copies both names';
  assert (select winner_name = 'Delete Ana' and loser_name = 'Delete Bo'
    from public.backgammon_matches where winner_id = '00000000-0000-0000-0000-0000000000a7'), 'backgammon result copies both names';
  assert (select reporter_name = 'Delete Ana' and respondent_name = 'Delete Bo'
    from public.swu_matches where reporter_id = '00000000-0000-0000-0000-0000000000a7'), 'SWU result copies both names';
end $$;

-- A rename shows in the history while the member is still here.
update public.profiles set display_name = 'Ana Renamed'
  where id = '00000000-0000-0000-0000-0000000000a7';
do $$
begin
  assert (select white_name = 'Ana Renamed' from public.matches where white_id = '00000000-0000-0000-0000-0000000000a7'),
    'chess history follows a rename';
  assert (select winner_name = 'Ana Renamed' from public.backgammon_matches where winner_id = '00000000-0000-0000-0000-0000000000a7'),
    'backgammon history follows a rename';
  assert (select reporter_name = 'Ana Renamed' from public.swu_matches where reporter_id = '00000000-0000-0000-0000-0000000000a7'),
    'SWU history follows a rename';
end $$;

-- Deleting needs a signed-in member.
select set_config('request.jwt.claim.sub', '', false);
do $$
begin
  perform public.delete_my_account();
  assert false, 'deleting needs sign-in';
exception when sqlstate '28000' then null;
end $$;

-- Anonymous callers can't even reach it.
reset role;
set role anon;
do $$
begin
  perform public.delete_my_account();
  assert false, 'anon must not execute delete_my_account';
exception when insufficient_privilege then null;
end $$;
reset role;
set role authenticated;

-- Ana deletes her account.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a7', false);
select public.delete_my_account();

reset role;
do $$
begin
  assert not exists (select 1 from auth.users where id = '00000000-0000-0000-0000-0000000000a7'),
    'the login is gone';
  assert not exists (select 1 from public.profiles where id = '00000000-0000-0000-0000-0000000000a7'),
    'the profile is gone';
  assert exists (select 1 from auth.users where id = '00000000-0000-0000-0000-0000000000b7')
    and exists (select 1 from public.profiles where id = '00000000-0000-0000-0000-0000000000b7'),
    'the opponent is untouched';
  assert not exists (select 1 from public.match_requests where '00000000-0000-0000-0000-0000000000a7' in (white_id, black_id))
    and not exists (select 1 from public.backgammon_match_requests where '00000000-0000-0000-0000-0000000000a7' in (winner_id, loser_id))
    and not exists (select 1 from public.swu_match_requests where '00000000-0000-0000-0000-0000000000a7' in (reporter_id, respondent_id)),
    'her open requests are gone';
  assert (select count(*) = 1 and bool_and(white_name = 'Ana Renamed' and black_name = 'Delete Bo')
    from public.matches where white_id = '00000000-0000-0000-0000-0000000000a7'),
    'chess result stays under the recorded names';
  assert (select count(*) = 1 and bool_and(winner_name = 'Ana Renamed' and loser_name = 'Delete Bo')
    from public.backgammon_matches where winner_id = '00000000-0000-0000-0000-0000000000a7'),
    'backgammon result stays under the recorded names';
  assert (select count(*) = 1 and bool_and(reporter_name = 'Ana Renamed' and respondent_name = 'Delete Bo')
    from public.swu_matches where reporter_id = '00000000-0000-0000-0000-0000000000a7'),
    'SWU result stays under the recorded names';
  -- Bo keeps what the games gave him: the deltas still explain his ratings.
  assert (select p.rating = 1000 - m.white_rating_delta
    from public.profiles p, public.matches m
    where p.id = '00000000-0000-0000-0000-0000000000b7' and m.white_id = '00000000-0000-0000-0000-0000000000a7'),
    'the opponent keeps the chess rating the game gave them';
end $$;

-- The opponent still reads the result, and renaming him still works.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b7', false);
do $$
begin
  assert (select count(*) from public.matches where white_id = '00000000-0000-0000-0000-0000000000a7') = 1,
    'the opponent still reads the result';
end $$;
update public.profiles set display_name = 'Bo Renamed' where id = '00000000-0000-0000-0000-0000000000b7';
do $$
begin
  assert (select white_name = 'Ana Renamed' and black_name = 'Bo Renamed'
    from public.matches where white_id = '00000000-0000-0000-0000-0000000000a7'),
    'the deleted member''s name is frozen, the opponent''s follows';
end $$;

rollback;
\echo 'delete_account_test: all assertions passed'
