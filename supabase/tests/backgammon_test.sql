-- Behavioural tests for the backgammon migration. Each block raises on
-- failure. Rolled back so the chess tests see an empty database.
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

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000a1', 'ana@bg.example', '{"display_name":"Bg Ana"}'),
  ('00000000-0000-0000-0000-0000000000b1', 'bo@bg.example',  '{"display_name":"Bg Bo"}'),
  ('00000000-0000-0000-0000-0000000000c1', 'cy@bg.example',  '{"display_name":"Bg Cy"}');

do $$
begin
  assert (select count(*) from public.profiles where bg_rating = 1500 and bg_peak_rating = 1500) = 3,
    'everyone starts at 1500';
end $$;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);

-- Ana reports a 5-3 win in a match to 5: nothing moves until Bo confirms.
select public.request_backgammon_match('00000000-0000-0000-0000-0000000000b1', 5::smallint, 5::smallint, 3::smallint);

do $$
declare
  req public.backgammon_match_requests;
begin
  select * into req from public.backgammon_match_requests order by id desc limit 1;
  assert req.winner_id = auth.uid() and req.loser_score = 3, 'winner and loser score stored';
  assert (select count(*) from public.backgammon_matches) = 0, 'no match before confirmation';
  begin
    perform public.respond_to_backgammon_match(req.id, true);
    raise exception 'reporter should not confirm their own match';
  exception when sqlstate '42501' then null;
  end;
  assert (select count(*) from public.backgammon_match_requests) = 1, 'failed self-confirm keeps the request';
end $$;

-- Cy isn't in it: can't see or answer it.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', false);
do $$
begin
  assert (select count(*) from public.backgammon_match_requests) = 0, 'outsiders cannot see requests';
  begin
    perform public.respond_to_backgammon_match((select max(id) from public.backgammon_match_requests), true);
    raise exception 'outsider should not confirm';
  exception when sqlstate 'P0002' then null;
  end;
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', false);
select public.respond_to_backgammon_match((select max(id) from public.backgammon_match_requests), true);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);

do $$
declare
  ana public.profiles := (select p from public.profiles p where display_name = 'Bg Ana');
  bo public.profiles := (select p from public.profiles p where display_name = 'Bg Bo');
  m public.backgammon_matches := (select m from public.backgammon_matches m order by id desc limit 1);
begin
  assert ana.bg_rating = 1522 and bo.bg_rating = 1478, 'FIBS deltas applied';
  assert ana.bg_peak_rating = 1522 and bo.bg_peak_rating = 1500, 'peaks tracked';
  assert ana.bg_wins = 1 and bo.bg_losses = 1 and ana.bg_matches_played = 1, 'record counted';
  assert ana.bg_experience = 5 and bo.bg_experience = 5, 'experience grows by the match length';
  assert ana.rating = 1000 and ana.games_played = 0, 'chess rating untouched';
  assert m.winner_rating_before = 1500 and m.winner_rating_delta = 22 and m.loser_rating_delta = -22
    and m.match_length = 5 and m.recorded_by = ana.id, 'match row is auditable';
  assert (select count(*) from public.backgammon_match_requests) = 0, 'request consumed';
end $$;

-- Ana loses a match to 3 she reported, then a declined and a withdrawn one.
select public.request_backgammon_match('00000000-0000-0000-0000-0000000000b1', 3::smallint, 1::smallint, 3::smallint);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', false);
select public.respond_to_backgammon_match((select max(id) from public.backgammon_match_requests), true);
select public.request_backgammon_match('00000000-0000-0000-0000-0000000000a1', 7::smallint, 7::smallint, 0::smallint);
select public.respond_to_backgammon_match((select max(id) from public.backgammon_match_requests), false);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
select public.request_backgammon_match('00000000-0000-0000-0000-0000000000b1', 7::smallint, 7::smallint, 0::smallint);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', false);
select public.respond_to_backgammon_match((select max(id) from public.backgammon_match_requests), false);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);

do $$
begin
  assert (select count(*) from public.backgammon_matches) = 2, 'only confirmed matches are rated';
  assert (select count(*) from public.backgammon_match_requests) = 0, 'withdrawn and declined requests are gone';
  assert (select winner_id from public.backgammon_matches order by id desc limit 1)
    = '00000000-0000-0000-0000-0000000000b1', 'reporter can record a loss';
  -- Every backgammon rating is 1500 plus its match deltas (principle II).
  assert not exists (
    select 1 from public.profiles p
    where p.bg_rating <> 1500 + coalesce((
      select sum(case when x.winner_id = p.id then x.winner_rating_delta else x.loser_rating_delta end)
      from public.backgammon_matches x where p.id in (x.winner_id, x.loser_id)
    ), 0)
  ), 'ratings replay from history';
end $$;

-- Rejections.
do $$
declare
  bo uuid := '00000000-0000-0000-0000-0000000000b1';
begin
  begin
    perform public.request_backgammon_match(auth.uid(), 5::smallint, 5::smallint, 3::smallint);
    raise exception 'self-play should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.request_backgammon_match(bo, 5::smallint, 5::smallint, 5::smallint);
    raise exception 'two winners should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.request_backgammon_match(bo, 5::smallint, 4::smallint, 3::smallint);
    raise exception 'nobody reaching the length should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.request_backgammon_match(bo, 5::smallint, 6::smallint, 3::smallint);
    raise exception 'scoring past the length should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.request_backgammon_match(bo, 0::smallint, 0::smallint, 0::smallint);
    raise exception 'zero-length match should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.request_backgammon_match(gen_random_uuid(), 5::smallint, 5::smallint, 3::smallint);
    raise exception 'unknown opponent should fail';
  exception when sqlstate 'P0002' then null;
  end;
end $$;

-- Members cannot touch backgammon ratings or matches directly.
do $$
begin
  begin
    update public.profiles set bg_rating = 3000 where id = auth.uid();
    raise exception 'rating update should be denied';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.backgammon_match_requests (winner_id, loser_id, match_length, loser_score, requested_by)
    values (auth.uid(), '00000000-0000-0000-0000-0000000000b1', 5, 0, auth.uid());
    raise exception 'direct request insert should be denied';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.backgammon_matches (winner_id, loser_id, match_length, loser_score,
      winner_rating_before, loser_rating_before, winner_rating_delta, loser_rating_delta, recorded_by)
    values (auth.uid(), '00000000-0000-0000-0000-0000000000b1', 5, 0, 1, 1, 400, -400, auth.uid());
    raise exception 'direct match insert should be denied';
  exception when insufficient_privilege then null;
  end;
end $$;

select set_config('request.jwt.claim.sub', '', false);
do $$
begin
  begin
    perform public.request_backgammon_match('00000000-0000-0000-0000-0000000000b1', 5::smallint, 5::smallint, 3::smallint);
    raise exception 'anonymous record should fail';
  exception when sqlstate '28000' then null;
  end;
end $$;

reset role;
rollback;
\echo 'backgammon_test: all assertions passed'
