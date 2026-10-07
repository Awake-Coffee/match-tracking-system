-- Behavioural tests for Star Wars: Unlimited points. Each block raises on
-- failure. Rolled back so other tests see an empty database.
\set ON_ERROR_STOP on
begin;

do $$
begin
  assert public.is_valid_score('swu', 2, 0) and public.is_valid_score('swu', 1, 2)
    and public.is_valid_score('swu', 1, 0) and public.is_valid_score('swu', 1, 1),
    'best-of-three scores accepted';
  assert not public.is_valid_score('swu', 0, 0) and not public.is_valid_score('swu', 2, 2)
    and not public.is_valid_score('swu', 3, 0) and not public.is_valid_score('swu', -1, 2)
    and not public.is_valid_score('swu', 0.5, 0.5) and not public.is_valid_score('swu', null, 1),
    'impossible scores rejected';
  assert public.swu_points('duel', 1::smallint, 1, 0) = 1 and public.swu_points('duel', 1::smallint, 0, 1) = -1
    and public.swu_points('duel', 3::smallint, 2, 1) = 3 and public.swu_points('duel', 3::smallint, 0, 2) = -1
    and public.swu_points('duel', 3::smallint, 1, 1) = 0, 'best of one 1/-1, best of three 3/-1, draw 0';
  assert public.swu_points('free_for_all', null, 0, 3) = -1 and public.swu_points('free_for_all', null, 1, 3) = 0
    and public.swu_points('free_for_all', null, 2, 3) = 1 and public.swu_points('free_for_all', null, 3, 2) = 2,
    'twin suns: first out -1, out in the final round 0, survived 1, winner 2';
  assert public.starting_rating('swu') = 0, 'everyone starts at 0';
end $$;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000a2', 'ana@swu.example', '{"display_name":"Swu Ana"}'),
  ('00000000-0000-0000-0000-0000000000b2', 'bo@swu.example',  '{"display_name":"Swu Bo"}'),
  ('00000000-0000-0000-0000-0000000000c2', 'cy@swu.example',  '{"display_name":"Swu Cy"}');

-- A member's standing in a game.
create function pg_temp.standing(
  p_name text, p_type public.match_type, p_mode text default 'premier'
) returns public.ratings
language sql as $$
  select r from public.ratings r join public.profiles p on p.id = r.player_id
  where p.display_name = p_name and r.match_type = p_type
    and (r.match_type <> 'swu' or r.mode = p_mode);
$$;


set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a2', false);

-- Ana reports a 2-1 win in a best of three: nothing moves until Bo confirms.
select test.request_duel('swu', '00000000-0000-0000-0000-0000000000b2', 2, 1);

do $$
declare
  req test.match_requests := (select r from test.match_requests r order by id desc limit 1);
begin
  assert req.match_type = 'swu' and req.player1_id = auth.uid()
    and req.player1_score = 2 and req.player2_score = 1 and req.best_of = 3,
    'score stored from the reporter''s side';
  assert (select count(*) from test.matches where match_type = 'swu') = 0,
    'no match before confirmation';
  begin
    perform public.respond_to_match(req.id, true);
    raise exception 'reporter should not confirm their own match';
  exception when sqlstate '42501' then null;
  end;
  assert (select count(*) from test.match_requests) = 1, 'failed self-confirm keeps the request';
end $$;

-- Cy isn't in it: can't see or answer it.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c2', false);
do $$
begin
  assert (select count(*) from test.match_requests) = 0, 'outsiders cannot see requests';
  begin
    perform public.respond_to_match((select max(id) from test.match_requests), true);
    raise exception 'outsider should not confirm';
  exception when sqlstate 'P0002' then null;
  end;
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false);
select public.respond_to_match((select max(id) from test.match_requests), true);

do $$
declare
  ana public.ratings := pg_temp.standing('Swu Ana', 'swu');
  bo public.ratings := pg_temp.standing('Swu Bo', 'swu');
  m test.matches := (select m from test.matches m order by id desc limit 1);
begin
  assert ana.rating = 3 and bo.rating = 0, 'a best of three win is 3; a loss can''t go below 0';
  assert ana.peak_rating = 3 and bo.peak_rating = 0, 'peaks tracked';
  assert ana.wins = 1 and bo.losses = 1 and ana.played = 1, 'record counted';
  assert pg_temp.standing('Swu Ana', 'chess') is null
    and pg_temp.standing('Swu Ana', 'backgammon') is null, 'chess and backgammon untouched';
  assert m.match_type = 'swu' and m.player1_id = ana.player_id and m.recorded_by = ana.player_id
    and m.player1_rating_before = 0 and m.player1_rating_delta = 3
    and m.player2_rating_delta = 0 and m.player1_score = 2 and m.best_of = 3,
    'match row is auditable: the delta is what was applied';
  assert (select count(*) from test.match_requests) = 0, 'request consumed';
end $$;

-- Bo reports a 1-1 draw, then a declined and a withdrawn one, then wins a
-- best of one.
select test.request_duel('swu', '00000000-0000-0000-0000-0000000000a2', 1, 1);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a2', false);
select public.respond_to_match((select max(id) from test.match_requests), true);
select test.request_duel('swu', '00000000-0000-0000-0000-0000000000b2', 0, 2);
select public.respond_to_match((select max(id) from test.match_requests), false);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false);
select test.request_duel('swu', '00000000-0000-0000-0000-0000000000a2', 2, 0);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a2', false);
select public.respond_to_match((select max(id) from test.match_requests), false);

do $$
declare
  ana public.ratings := pg_temp.standing('Swu Ana', 'swu');
  bo public.ratings := pg_temp.standing('Swu Bo', 'swu');
begin
  assert ana.rating = 3 and bo.rating = 0, 'a draw is worth nothing';
  assert ana.draws = 1 and bo.draws = 1 and bo.played = 2, 'draw counted';
  assert (select count(*) from test.matches where match_type = 'swu') = 2,
    'only confirmed matches are rated';
  assert (select count(*) from test.match_requests where status = 'pending') = 0, 'withdrawn and declined requests stop waiting';
  -- Ana declined Bo's report, so only Bo still reads it.
  assert (select count(*) from test.match_requests) = 0, 'the one who declined no longer sees the request';
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false);
select test.request_duel('swu', '00000000-0000-0000-0000-0000000000a2', 1, 0, p_best_of => 1::smallint);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a2', false);
select public.respond_to_match((select max(id) from test.match_requests), true);

do $$
begin
  assert (pg_temp.standing('Swu Ana', 'swu')).rating = 2
    and (pg_temp.standing('Swu Bo', 'swu')).rating = 1, 'a best of one is 1 for the win, -1 for the loss';
  assert (select best_of from test.matches order by id desc limit 1) = 1, 'the best of is kept';
end $$;

-- Trilogy is its own ladder, always a best of three.
select public.request_match('swu', 'trilogy', jsonb_build_array(
  jsonb_build_object('player_id', '00000000-0000-0000-0000-0000000000a2', 'side', 1, 'score', 1),
  jsonb_build_object('player_id', '00000000-0000-0000-0000-0000000000c2', 'side', 2, 'score', 2)),
  p_best_of => 3::smallint);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c2', false);
select public.respond_to_match((select max(id) from test.match_requests), true);

do $$
begin
  assert (pg_temp.standing('Swu Cy', 'swu', 'trilogy')).rating = 3
    and (pg_temp.standing('Swu Ana', 'swu', 'trilogy')).rating = 0, 'trilogy is 3 for the win';
  assert (pg_temp.standing('Swu Ana', 'swu')).rating = 2, 'premier untouched';
  -- Every SWU rating is 0 plus its result deltas, per mode (principle II).
  assert not exists (
    select 1 from public.ratings r
    where r.match_type = 'swu' and r.rating <> coalesce((
      select sum(p.rating_delta) from public.match_players p join public.matches m on m.id = p.match_id
      where m.match_type = 'swu' and m.mode = r.mode and p.player_id = r.player_id
    ), 0)
  ), 'ratings replay from history';
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a2', false);

-- Rejections.
do $$
declare
  bo uuid := '00000000-0000-0000-0000-0000000000b2';
begin
  begin
    perform test.request_duel('swu', auth.uid(), 2, 0);
    raise exception 'self-play should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform test.request_duel('swu', bo, 0, 0);
    raise exception '0-0 should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform test.request_duel('swu', bo, 2, 2);
    raise exception '2-2 should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform test.request_duel('swu', bo, 3, 0);
    raise exception 'three wins should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform test.request_duel('swu', bo, 2, 0, p_best_of => 1::smallint);
    raise exception 'a best of one 2-0 should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform test.request_duel('swu', bo, 1, 1, p_best_of => 1::smallint);
    raise exception 'a best of one draw should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform test.request_duel('swu', bo, 2, 0, p_best_of => 2::smallint);
    raise exception 'a best of two should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.request_match('swu', 'premier', jsonb_build_array(
      jsonb_build_object('player_id', auth.uid(), 'side', 1, 'score', 2),
      jsonb_build_object('player_id', bo, 'side', 2, 'score', 0)));
    raise exception 'a duel without its best of should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.request_match('swu', 'trilogy', jsonb_build_array(
      jsonb_build_object('player_id', auth.uid(), 'side', 1, 'score', 1),
      jsonb_build_object('player_id', bo, 'side', 2, 'score', 0)), p_best_of => 1::smallint);
    raise exception 'a trilogy best of one should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.request_match('backgammon', 'standard', jsonb_build_array(
      jsonb_build_object('player_id', auth.uid(), 'side', 1, 'score', 5),
      jsonb_build_object('player_id', bo, 'side', 2, 'score', 2)), p_best_of => 3::smallint);
    raise exception 'backgammon with a best of should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform test.request_duel('swu', gen_random_uuid(), 2, 0);
    raise exception 'unknown opponent should fail';
  exception when sqlstate 'P0002' then null;
  end;
end $$;

-- Members cannot touch SWU ratings or matches directly.
do $$
begin
  begin
    update public.ratings set rating = 3000 where player_id = auth.uid() and match_type = 'swu';
    raise exception 'rating update should be denied';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.match_players (match_id, player_id, player_name, side, score,
      rating_before, rating_delta)
    select id, auth.uid(), 'Swu Ana', 1, 2, 1, 400 from public.matches limit 1;
    raise exception 'direct match insert should be denied';
  exception when insufficient_privilege then null;
  end;
end $$;

select set_config('request.jwt.claim.sub', '', false);
do $$
begin
  begin
    perform test.request_duel('swu', '00000000-0000-0000-0000-0000000000b2', 2, 0);
    raise exception 'anonymous record should fail';
  exception when sqlstate '28000' then null;
  end;
end $$;

reset role;
rollback;
\echo 'swu_test: all assertions passed'
