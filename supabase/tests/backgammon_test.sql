-- Behavioural tests for backgammon ratings. Each block raises on failure.
-- Rolled back so the chess tests see an empty database.
\set ON_ERROR_STOP on
begin;

-- fibs_rating_change matches the Dart implementation (see app/test/backgammon_test.dart).
do $$
begin
  assert public.fibs_rating_change(1500, 0, 1500, 5, true) = 22, 'newcomer win to 5';
  assert public.fibs_rating_change(1500, 0, 1500, 5, false) = -22, 'newcomer loss to 5';
  assert public.fibs_rating_change(1500, 0, 1500, 11, true) = 33, 'longer matches move more';
  assert public.fibs_rating_change(1500, 500, 1500, 1, true) = 2, 'experience multiplier bottoms out at 1';
  assert public.fibs_rating_change(1563, 90, 1684, 5, true) = 21, 'underdog win';
  assert public.fibs_rating_change(1684, 214, 1563, 5, false) = -15, 'favourite loss';
  assert public.fibs_rating_change(1700, 400, 1500, 5, true) = 3, 'favourite win';
  assert public.fibs_rating_change(1500, 400, 1700, 5, true) = 6, 'experienced underdog win';
end $$;

do $$
begin
  assert public.is_valid_score('backgammon', 5, 3) and public.is_valid_score('backgammon', 0, 1)
    and public.is_valid_score('backgammon', 25, 24), 'final scores accepted';
  assert not public.is_valid_score('backgammon', 5, 5) and not public.is_valid_score('backgammon', 0, 0)
    and not public.is_valid_score('backgammon', 26, 0) and not public.is_valid_score('backgammon', 5, -1)
    and not public.is_valid_score('backgammon', 4.5, 3), 'impossible scores rejected';
end $$;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000a1', 'ana@bg.example', '{"display_name":"Bg Ana"}'),
  ('00000000-0000-0000-0000-0000000000b1', 'bo@bg.example',  '{"display_name":"Bg Bo"}'),
  ('00000000-0000-0000-0000-0000000000c1', 'cy@bg.example',  '{"display_name":"Bg Cy"}');

do $$
begin
  assert (select count(*) from public.ratings
    where match_type = 'backgammon' and rating = 1500 and peak_rating = 1500) = 3,
    'everyone starts at 1500';
end $$;

-- A member's standing in a game.
create function pg_temp.standing(p_name text, p_type public.match_type) returns public.ratings
language sql as $$
  select r from public.ratings r join public.profiles p on p.id = r.player_id
  where p.display_name = p_name and r.match_type = p_type;
$$;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);

-- Ana reports a 5-3 win in a match to 5: nothing moves until Bo confirms.
select public.request_match('backgammon', '00000000-0000-0000-0000-0000000000b1', 5, 3);

do $$
declare
  req public.match_requests := (select r from public.match_requests r order by id desc limit 1);
begin
  assert req.match_type = 'backgammon' and req.player1_id = auth.uid()
    and req.player1_score = 5 and req.player2_score = 3 and req.dgt_option is null,
    'score stored from the reporter''s side';
  assert (select count(*) from public.matches) = 0, 'no match before confirmation';
  begin
    perform public.respond_to_match(req.id, true);
    raise exception 'reporter should not confirm their own match';
  exception when sqlstate '42501' then null;
  end;
  assert (select count(*) from public.match_requests) = 1, 'failed self-confirm keeps the request';
end $$;

-- Cy isn't in it: can't see or answer it.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', false);
do $$
begin
  assert (select count(*) from public.match_requests) = 0, 'outsiders cannot see requests';
  begin
    perform public.respond_to_match((select max(id) from public.match_requests), true);
    raise exception 'outsider should not confirm';
  exception when sqlstate 'P0002' then null;
  end;
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', false);
select public.respond_to_match((select max(id) from public.match_requests), true);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);

do $$
declare
  ana public.ratings := pg_temp.standing('Bg Ana', 'backgammon');
  bo public.ratings := pg_temp.standing('Bg Bo', 'backgammon');
  m public.matches := (select m from public.matches m order by id desc limit 1);
begin
  assert ana.rating = 1522 and bo.rating = 1478, 'FIBS deltas applied';
  assert ana.peak_rating = 1522 and bo.peak_rating = 1500, 'peaks tracked';
  assert ana.wins = 1 and bo.losses = 1 and ana.played = 1 and ana.draws = 0, 'record counted';
  assert ana.experience = 5 and bo.experience = 5, 'experience grows by the match length';
  assert (pg_temp.standing('Bg Ana', 'chess')).rating = 1000
    and (pg_temp.standing('Bg Ana', 'chess')).played = 0, 'chess rating untouched';
  assert m.match_type = 'backgammon' and m.player1_rating_before = 1500
    and m.player1_rating_delta = 22 and m.player2_rating_delta = -22
    and m.player1_score = 5 and m.player2_score = 3 and m.recorded_by = ana.player_id,
    'match row is auditable';
  assert (select count(*) from public.match_requests) = 0, 'request consumed';
end $$;

-- Ana loses a match to 3 she reported, then a declined and a withdrawn one.
select public.request_match('backgammon', '00000000-0000-0000-0000-0000000000b1', 1, 3);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', false);
select public.respond_to_match((select max(id) from public.match_requests), true);
select public.request_match('backgammon', '00000000-0000-0000-0000-0000000000a1', 7, 0);
select public.respond_to_match((select max(id) from public.match_requests), false);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
select public.request_match('backgammon', '00000000-0000-0000-0000-0000000000b1', 7, 0);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', false);
select public.respond_to_match((select max(id) from public.match_requests), false);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);

do $$
declare
  m public.matches := (select m from public.matches m order by id desc limit 1);
begin
  assert (select count(*) from public.matches) = 2, 'only confirmed matches are rated';
  assert (select count(*) from public.match_requests where status = 'pending') = 0, 'withdrawn and declined requests stop waiting';
  assert (select count(*) from public.match_requests) = 1, 'withdrawing deletes, declining keeps the request for the reporter';
  assert m.player1_id = auth.uid() and m.player1_score = 1 and m.player2_score = 3
    and m.player1_rating_delta < 0, 'reporter can record a loss';
  assert (pg_temp.standing('Bg Ana', 'backgammon')).experience = 8, 'experience adds up';
  -- Every backgammon rating is 1500 plus its match deltas (principle II).
  assert not exists (
    select 1 from public.ratings r
    where r.match_type = 'backgammon' and r.rating <> 1500 + coalesce((
      select sum(case when x.player1_id = r.player_id
        then x.player1_rating_delta else x.player2_rating_delta end)
      from public.matches x
      where x.match_type = 'backgammon' and r.player_id in (x.player1_id, x.player2_id)
    ), 0)
  ), 'ratings replay from history';
end $$;

-- Rejections.
do $$
declare
  bo uuid := '00000000-0000-0000-0000-0000000000b1';
begin
  begin
    perform public.request_match('backgammon', auth.uid(), 5, 3);
    raise exception 'self-play should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.request_match('backgammon', bo, 5, 5);
    raise exception 'two winners should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.request_match('backgammon', bo, 26, 3);
    raise exception 'scoring past the longest match should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.request_match('backgammon', bo, 0, 0);
    raise exception 'zero-length match should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.request_match('backgammon', bo, 5, 3, true, 'white');
    raise exception 'a color should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.request_match('backgammon', bo, 5, 3, true, null, 9::smallint);
    raise exception 'a time control should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.request_match('backgammon', gen_random_uuid(), 5, 3);
    raise exception 'unknown opponent should fail';
  exception when sqlstate 'P0002' then null;
  end;
end $$;

-- Members cannot touch backgammon ratings or matches directly.
do $$
begin
  begin
    update public.ratings set rating = 3000
      where player_id = auth.uid() and match_type = 'backgammon';
    raise exception 'rating update should be denied';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.match_requests (match_type, player1_id, player2_id, player1_score,
      player2_score, requested_by)
    values ('backgammon', auth.uid(), '00000000-0000-0000-0000-0000000000b1', 5, 0, auth.uid());
    raise exception 'direct request insert should be denied';
  exception when insufficient_privilege then null;
  end;
end $$;

select set_config('request.jwt.claim.sub', '', false);
do $$
begin
  begin
    perform public.request_match('backgammon', '00000000-0000-0000-0000-0000000000b1', 5, 3);
    raise exception 'anonymous record should fail';
  exception when sqlstate '28000' then null;
  end;
end $$;

reset role;

-- Only backgammon builds experience.
do $$
begin
  begin
    update public.ratings set experience = 5 where match_type = 'chess';
    raise exception 'chess experience should be rejected';
  exception when check_violation then null;
  end;
end $$;

rollback;
\echo 'backgammon_test: all assertions passed'
