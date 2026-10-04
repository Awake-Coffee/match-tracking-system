-- Behavioural tests for unrated results in every game. Each block raises on
-- failure. Rolled back so other tests see an empty database.
\set ON_ERROR_STOP on
begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000a3', 'ana@unrated.example', '{"display_name":"Unrated Ana"}'),
  ('00000000-0000-0000-0000-0000000000b3', 'bo@unrated.example',  '{"display_name":"Unrated Bo"}');

set role authenticated;

-- Ana reports one unrated result in each game; Bo confirms them all.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a3', false);
select public.request_chess_match(
  '00000000-0000-0000-0000-0000000000b3', 'white', 'win', 1::smallint, null, null, false);
select public.request_backgammon_match(
  '00000000-0000-0000-0000-0000000000b3', 5::smallint, 5::smallint, 2::smallint, false);
select public.request_swu_match(
  '00000000-0000-0000-0000-0000000000b3', 2::smallint, 0::smallint, false);

do $$
begin
  assert (select bool_and(not rated) from public.match_requests), 'chess request stored unrated';
  assert (select bool_and(not rated) from public.backgammon_match_requests), 'backgammon request stored unrated';
  assert (select bool_and(not rated) from public.swu_match_requests), 'SWU request stored unrated';
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b3', false);
select public.respond_to_chess_match((select max(id) from public.match_requests), true);
select public.respond_to_backgammon_match((select max(id) from public.backgammon_match_requests), true);
select public.respond_to_swu_match((select max(id) from public.swu_match_requests), true);

do $$
declare
  ana public.profiles := (select p from public.profiles p where display_name = 'Unrated Ana');
  bo public.profiles := (select p from public.profiles p where display_name = 'Unrated Bo');
  chess public.matches := (select m from public.matches m order by id desc limit 1);
  bg public.backgammon_matches := (select m from public.backgammon_matches m order by id desc limit 1);
  swu public.swu_matches := (select m from public.swu_matches m order by id desc limit 1);
begin
  assert not chess.rated and chess.white_id = ana.id and chess.result = 'white'
    and chess.white_rating_before = 1000 and chess.white_rating_delta = 0
    and chess.black_rating_delta = 0, 'chess game kept with zero deltas';
  assert not bg.rated and bg.winner_id = ana.id and bg.loser_score = 2
    and bg.winner_rating_before = 1500 and bg.winner_rating_delta = 0
    and bg.loser_rating_delta = 0, 'backgammon match kept with zero deltas';
  assert not swu.rated and swu.reporter_games = 2 and swu.reporter_rating_before = 1000
    and swu.reporter_rating_delta = 0 and swu.respondent_rating_delta = 0,
    'SWU match kept with zero deltas';

  assert ana.rating = 1000 and ana.peak_rating = 1000 and ana.games_played = 0 and ana.wins = 0
    and bo.rating = 1000 and bo.losses = 0, 'chess rating and record untouched';
  assert ana.bg_rating = 1500 and ana.bg_matches_played = 0 and ana.bg_experience = 0
    and bo.bg_rating = 1500 and bo.bg_experience = 0, 'backgammon rating, record and experience untouched';
  assert ana.swu_rating = 1000 and ana.swu_matches_played = 0 and bo.swu_losses = 0,
    'SWU rating and record untouched';
end $$;

-- A rated game afterwards is rated as if the unrated ones never happened, and
-- results reported without p_rated stay rated.
select public.request_chess_match('00000000-0000-0000-0000-0000000000a3', 'black', 'win', 1::smallint);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a3', false);
select public.respond_to_chess_match((select max(id) from public.match_requests), true);

do $$
declare
  ana public.profiles := (select p from public.profiles p where display_name = 'Unrated Ana');
  bo public.profiles := (select p from public.profiles p where display_name = 'Unrated Bo');
begin
  assert (select rated from public.matches order by id desc limit 1), 'rated by default';
  assert ana.rating = 980 and bo.rating = 1020 and ana.games_played = 1 and bo.games_played = 1,
    'first rated game still uses K = 40 from 1000';
  -- Ratings still replay from history (principle II).
  assert not exists (
    select 1 from public.profiles p
    where p.rating <> 1000 + coalesce((
      select sum(case when x.white_id = p.id then x.white_rating_delta else x.black_rating_delta end)
      from public.matches x where p.id in (x.white_id, x.black_id)
    ), 0)
  ), 'ratings replay from history';
end $$;

-- Rejections.
do $$
declare
  bo uuid := '00000000-0000-0000-0000-0000000000b3';
begin
  begin
    perform public.request_chess_match(bo, 'white', 'win', 1::smallint, null, null, null);
    raise exception 'null rated should fail for chess';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.request_backgammon_match(bo, 3::smallint, 3::smallint, 0::smallint, null);
    raise exception 'null rated should fail for backgammon';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.request_swu_match(bo, 2::smallint, 0::smallint, null);
    raise exception 'null rated should fail for SWU';
  exception when sqlstate '22023' then null;
  end;
end $$;

reset role;

-- An unrated result can't carry a rating change.
do $$
begin
  begin
    update public.matches set white_rating_delta = 5 where not rated;
    raise exception 'unrated chess delta should be rejected';
  exception when check_violation then null;
  end;
  begin
    update public.backgammon_matches set loser_rating_delta = -5 where not rated;
    raise exception 'unrated backgammon delta should be rejected';
  exception when check_violation then null;
  end;
  begin
    update public.swu_matches set reporter_rating_delta = 5 where not rated;
    raise exception 'unrated SWU delta should be rejected';
  exception when check_violation then null;
  end;
end $$;

rollback;
\echo 'unrated_test: all assertions passed'
