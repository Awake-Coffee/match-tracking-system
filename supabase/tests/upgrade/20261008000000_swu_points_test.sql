-- Checks that the rows from upgrade/20261008000000_swu_points_seed.sql were
-- re-scored with SWU points. Each block raises on failure.
\set ON_ERROR_STOP on

do $$
declare
  ana uuid := '00000000-0000-0000-0000-000000000021';
  bo uuid := '00000000-0000-0000-0000-000000000022';
begin
  -- In order played: Ana wins a best of three (+3; Bo stays at 0), Bo wins
  -- one (+3; Ana -1), an unrated one moves nothing, a draw is 0.
  assert (select array_agg(format('%s %s %s %s %s', match_id, player_id = ana, score, rating_before,
      rating_delta) order by match_id, side) from public.match_players where match_id between 101 and 104)
    = array['101 f 2.0 0 3', '101 t 0.0 3 -1', '102 t 2.0 0 3', '102 f 1.0 0 0',
            '103 t 2.0 2 0', '103 f 0.0 3 0', '104 t 1.0 2 0', '104 f 1.0 3 0'],
    'premier results re-scored in the order played';
  assert (select array_agg(best_of order by id) from public.matches where match_type = 'swu')
    = array[3, 3, 3, 3, null]::smallint[], 'premier results were best of three';
  assert (select (rating, peak_rating, played, wins, losses, draws) from public.ratings
    where player_id = ana and match_type = 'swu' and mode = 'premier') = (2, 3, 3, 1, 1, 1),
    'standing replayed';
  assert (select (rating, peak_rating, played) from public.ratings
    where player_id = '00000000-0000-0000-0000-000000000023' and mode = 'premier') = (0, 0, 0),
    'no results, back to 0';

  -- The sole leader won; Bo survived; Cy and Di (since deleted) were out
  -- together, first.
  assert (select array_agg(format('%s %s %s', score, rating_before, rating_delta) order by side)
    from public.match_players where match_id = 105)
    = array['3.0 0 2', '2.0 0 1', '0.0 0 0', '0.0 0 0'], 'twin suns re-scored by how each finished';
  assert (select array_agg(rating order by player_id) from public.ratings where mode = 'twin_suns')
    = array[2, 1, 0], 'twin suns standings';

  assert (select (rating_before, rating_delta) from public.match_players
    where match_id = 106 and player_id = ana) = (1000, 20), 'chess untouched';
  assert (select rating from public.ratings where player_id = ana and match_type = 'chess') = 1020,
    'chess standing untouched';
  assert not exists (
    select 1 from public.ratings r
    where r.match_type = 'swu' and r.rating <> coalesce((
      select sum(p.rating_delta) from public.match_players p join public.matches m on m.id = p.match_id
      where m.match_type = 'swu' and m.mode = r.mode and p.player_id = r.player_id
    ), 0)
  ), 'every SWU rating is 0 plus its deltas';
end $$;

do $$
begin
  assert (select array_agg(format('%s %s', id, coalesce(best_of::text, '-')) order by id)
    from public.match_requests) = array['201 3', '202 -'],
    'the premier report is a best of three; the twin suns for two is dropped';
  assert (select array_agg(score order by side) from public.match_request_players where request_id = 202)
    = array[3, 2, 0]::numeric[], 'the twin suns for three is re-scored';
end $$;

-- Cy confirms the carried-over Premier report.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000023', false);
select public.respond_to_match(201, true);
reset role;

do $$
begin
  assert (select array_agg(format('%s %s', rating_before, rating_delta) order by side)
    from public.match_players where match_id = (select id from public.matches where id < 101))
    = array['2 3', '0 0'], 'a carried-over report is rated with points';
end $$;

\echo 'swu_points upgrade_test: all assertions passed'
