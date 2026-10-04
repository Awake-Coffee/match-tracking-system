-- Checks that the rows from upgrade/20261007000000_game_modes_seed.sql carried
-- over to game modes unchanged. Each block raises on failure.
\set ON_ERROR_STOP on

do $$
declare
  ana uuid := '00000000-0000-0000-0000-000000000011';
  bo uuid := '00000000-0000-0000-0000-000000000012';
begin
  assert (select array_agg(format('%s/%s', match_type, mode) order by match_type)
    from public.ratings where player_id = ana)
    = array['chess/standard', 'backgammon/standard', 'swu/premier'],
    'ratings land in each game''s original mode';
  assert (select (rating, peak_rating, played, wins) from public.ratings
    where player_id = ana and match_type = 'chess') = (1020, 1020, 1, 1), 'standing kept';

  assert (select (match_type, mode, dgt_option, recorded_by) from public.matches)
    = ('chess'::public.match_type, 'standard'::text, 9::smallint, bo), 'result kept in its mode';
  assert (select array_agg(format('%s %s %s %s %s %s', player_id = ana, player_name, side, score,
      rating_before, rating_delta) order by side)
    from public.match_players)
    = array['t Ana 1 1.0 1000 20', 'f Bo Renamed 2 0.0 1000 -20'],
    'both players kept with their side, score, rating and name copy';
  assert not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name in ('matches', 'match_requests')
      and column_name like 'player%'
  ), 'player columns moved out';
end $$;

do $$
declare
  ana uuid := '00000000-0000-0000-0000-000000000011';
  bo uuid := '00000000-0000-0000-0000-000000000012';
begin
  assert (select array_agg(format('%s/%s %s %s', match_type, mode, status, declined_by is null)
      order by id) from public.match_requests)
    = array['swu/premier declined t', 'backgammon/standard pending t'], 'requests kept';
  assert (select array_agg(format('%s %s %s %s', r.match_type, p.player_id = ana, p.score, p.confirmed)
      order by r.id, p.side)
    from public.match_requests r join public.match_request_players p on p.request_id = r.id)
    = array['swu f 2.0 t', 'swu t 1.0 f', 'backgammon t 5.0 t', 'backgammon f 2.0 f'],
    'the reporter is the one confirmed';
end $$;

-- Bo confirms the carried-over backgammon match.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000012', false);
select public.respond_to_match((select id from public.match_requests where match_type = 'backgammon'), true);
reset role;

do $$
begin
  assert (select count(*) from public.matches where match_type = 'backgammon' and mode = 'standard') = 1,
    'a carried-over request is rated in its mode';
  assert (select played from public.ratings
    where player_id = '00000000-0000-0000-0000-000000000011' and match_type = 'backgammon') = 1,
    'into the carried-over rating';
end $$;

\echo 'game_modes upgrade_test: all assertions passed'
