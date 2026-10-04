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
select public.request_match(
  'chess', '00000000-0000-0000-0000-0000000000b3', 1, 0, false, 'white', 1::smallint);
select public.request_match('backgammon', '00000000-0000-0000-0000-0000000000b3', 5, 2, false);
select public.request_match('swu', '00000000-0000-0000-0000-0000000000b3', 2, 0, false);

do $$
begin
  assert (select count(*) from public.match_requests where not rated) = 3,
    'requests stored unrated in every game';
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b3', false);
select public.respond_to_match(id, true) from public.match_requests order by id;

do $$
declare
  ana uuid := '00000000-0000-0000-0000-0000000000a3';
  m public.matches;
begin
  assert (select count(*) from public.matches where player1_id = ana) = 3, 'all three kept';
  for m in select * from public.matches where player1_id = ana loop
    assert not m.rated and m.player1_rating_before = public.starting_rating(m.match_type)
      and m.player1_rating_delta = 0 and m.player2_rating_delta = 0,
      format('%s result kept with zero deltas', m.match_type);
  end loop;

  assert not exists (
    select 1 from public.ratings
    where player_id in (ana, '00000000-0000-0000-0000-0000000000b3')
      and (rating <> public.starting_rating(match_type)
        or peak_rating <> rating or played <> 0 or experience <> 0)
  ), 'ratings, records and experience untouched';
end $$;

-- A rated game afterwards is rated as if the unrated ones never happened, and
-- results reported without p_rated stay rated.
select public.request_match(
  'chess', '00000000-0000-0000-0000-0000000000a3', 1, 0, p_my_color => 'black', p_dgt_option => 1::smallint);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a3', false);
select public.respond_to_match((select max(id) from public.match_requests), true);

do $$
declare
  ana public.ratings := (select r from public.ratings r
    where player_id = '00000000-0000-0000-0000-0000000000a3' and match_type = 'chess');
  bo public.ratings := (select r from public.ratings r
    where player_id = '00000000-0000-0000-0000-0000000000b3' and match_type = 'chess');
begin
  assert (select rated from public.matches order by id desc limit 1), 'rated by default';
  assert ana.rating = 980 and bo.rating = 1020 and ana.played = 1 and bo.played = 1,
    'first rated game still uses K = 40 from 1000';
  -- Ratings still replay from history (principle II).
  assert not exists (
    select 1 from public.ratings r
    where r.rating <> public.starting_rating(r.match_type) + coalesce((
      select sum(case when x.player1_id = r.player_id
        then x.player1_rating_delta else x.player2_rating_delta end)
      from public.matches x
      where x.match_type = r.match_type and r.player_id in (x.player1_id, x.player2_id)
    ), 0)
  ), 'ratings replay from history';
end $$;

-- Rejections.
do $$
declare
  bo uuid := '00000000-0000-0000-0000-0000000000b3';
begin
  begin
    perform public.request_match('swu', bo, 2, 0, null);
    raise exception 'null rated should fail';
  exception when sqlstate '22023' then null;
  end;
end $$;

reset role;

-- An unrated result can't carry a rating change.
do $$
begin
  begin
    update public.matches set player1_rating_delta = 5 where not rated;
    raise exception 'unrated delta should be rejected';
  exception when check_violation then null;
  end;
end $$;

rollback;
\echo 'unrated_test: all assertions passed'
