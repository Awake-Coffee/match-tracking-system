-- Deleting an account removes the login, profile, ratings and open requests,
-- keeps confirmed results in every game under the recorded names, and leaves
-- the opponent's ratings alone. Each block raises on failure. Rolled back so
-- other tests see an empty database.
\set ON_ERROR_STOP on
begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000a7', 'ana@delete.example', '{"display_name":"Delete Ana"}'),
  ('00000000-0000-0000-0000-0000000000b7', 'bo@delete.example',  '{"display_name":"Delete Bo"}');

set role authenticated;

-- Ana and Bo play one confirmed game in each game; Ana leaves one more of
-- each waiting for Bo. Ana is player1 every time (white, or the reporter).
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a7', false);
select test.request_duel('chess', '00000000-0000-0000-0000-0000000000b7', 1, 0, true, 'white', 1::smallint);
select test.request_duel('backgammon', '00000000-0000-0000-0000-0000000000b7', 5, 2);
select test.request_duel('swu', '00000000-0000-0000-0000-0000000000b7', 2, 0);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b7', false);
select public.respond_to_match(id, true) from test.match_requests order by id;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a7', false);
select test.request_duel('chess', '00000000-0000-0000-0000-0000000000b7', 1, 0, true, 'white', 1::smallint);
select test.request_duel('backgammon', '00000000-0000-0000-0000-0000000000b7', 5, 2);
select test.request_duel('swu', '00000000-0000-0000-0000-0000000000b7', 2, 0);

do $$
begin
  assert (select count(distinct match_type) = 3
      and bool_and(player1_name = 'Delete Ana' and player2_name = 'Delete Bo')
    from test.matches where player1_id = '00000000-0000-0000-0000-0000000000a7'), 'results copy both names in every game';
end $$;

-- A rename shows in the history while the member is still here.
update public.profiles set display_name = 'Ana Renamed' where id = '00000000-0000-0000-0000-0000000000a7';
do $$
begin
  assert (select count(*) = 3 and bool_and(player1_name = 'Ana Renamed')
    from test.matches where player1_id = '00000000-0000-0000-0000-0000000000a7'), 'history follows a rename in every game';
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
  assert not exists (select 1 from auth.users where id = '00000000-0000-0000-0000-0000000000a7'), 'the login is gone';
  assert not exists (select 1 from public.profiles where id = '00000000-0000-0000-0000-0000000000a7'), 'the profile is gone';
  assert not exists (select 1 from public.ratings where player_id = '00000000-0000-0000-0000-0000000000a7'), 'her ratings are gone';
  assert exists (select 1 from auth.users where id = '00000000-0000-0000-0000-0000000000b7')
    and exists (select 1 from public.profiles where id = '00000000-0000-0000-0000-0000000000b7'),
    'the opponent is untouched';
  assert not exists (select 1 from test.match_requests where '00000000-0000-0000-0000-0000000000a7' in (player1_id, player2_id)),
    'her open requests are gone';
  assert (select count(distinct match_type) = 3
      and bool_and(player1_name = 'Ana Renamed' and player2_name = 'Delete Bo')
    from test.matches where player1_id = '00000000-0000-0000-0000-0000000000a7'),
    'results stay in every game under the recorded names';
  -- Bo keeps what the games gave him: the deltas still explain his ratings.
  assert (select count(*) = 3
      and bool_and(r.rating = public.starting_rating(r.match_type) + m.player2_rating_delta)
    from public.ratings r join test.matches m
      on m.match_type = r.match_type and m.player2_id = r.player_id
    where r.player_id = '00000000-0000-0000-0000-0000000000b7'),
    'the opponent keeps the ratings the games gave them';
end $$;

-- The opponent still reads the results, and renaming him still works.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b7', false);
do $$
begin
  assert (select count(*) from test.matches where player1_id = '00000000-0000-0000-0000-0000000000a7') = 3,
    'the opponent still reads the results';
end $$;
update public.profiles set display_name = 'Bo Renamed' where id = '00000000-0000-0000-0000-0000000000b7';
do $$
begin
  assert (select count(*) = 3 and bool_and(player1_name = 'Ana Renamed' and player2_name = 'Bo Renamed')
    from test.matches where player1_id = '00000000-0000-0000-0000-0000000000a7'),
    'the deleted member''s name is frozen, the opponent''s follows';
end $$;

rollback;
\echo 'delete_account_test: all assertions passed'
