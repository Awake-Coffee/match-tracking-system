-- Behavioural tests for the Star Wars: Unlimited migration. Each block
-- raises on failure. Rolled back so other tests see an empty database.
\set ON_ERROR_STOP on
begin;

do $$
begin
  assert public.is_swu_score(2, 0) and public.is_swu_score(1, 2) and public.is_swu_score(1, 0)
    and public.is_swu_score(1, 1), 'best-of-three scores accepted';
  assert not public.is_swu_score(0, 0) and not public.is_swu_score(2, 2)
    and not public.is_swu_score(3, 0) and not public.is_swu_score(-1, 2)
    and not public.is_swu_score(null, 1), 'impossible scores rejected';
end $$;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000a2', 'ana@swu.example', '{"display_name":"Swu Ana"}'),
  ('00000000-0000-0000-0000-0000000000b2', 'bo@swu.example',  '{"display_name":"Swu Bo"}'),
  ('00000000-0000-0000-0000-0000000000c2', 'cy@swu.example',  '{"display_name":"Swu Cy"}');

do $$
begin
  assert (select count(*) from public.profiles
    where display_name like 'Swu %' and swu_rating = 1000 and swu_peak_rating = 1000) = 3,
    'everyone starts at 1000';
end $$;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a2', false);

-- Ana reports a 2-1 win: nothing moves until Bo confirms.
select public.request_swu_match('00000000-0000-0000-0000-0000000000b2', 2::smallint, 1::smallint);

do $$
declare
  req public.swu_match_requests := (select r from public.swu_match_requests r order by id desc limit 1);
begin
  assert req.reporter_id = auth.uid() and req.reporter_games = 2 and req.respondent_games = 1,
    'score stored from the reporter''s side';
  assert (select count(*) from public.swu_matches) = 0, 'no match before confirmation';
  begin
    perform public.respond_to_swu_match(req.id, true);
    raise exception 'reporter should not confirm their own match';
  exception when sqlstate '42501' then null;
  end;
  assert (select count(*) from public.swu_match_requests) = 1, 'failed self-confirm keeps the request';
end $$;

-- Cy isn't in it: can't see or answer it.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c2', false);
do $$
begin
  assert (select count(*) from public.swu_match_requests) = 0, 'outsiders cannot see requests';
  begin
    perform public.respond_to_swu_match((select max(id) from public.swu_match_requests), true);
    raise exception 'outsider should not confirm';
  exception when sqlstate 'P0002' then null;
  end;
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false);
select public.respond_to_swu_match((select max(id) from public.swu_match_requests), true);

do $$
declare
  ana public.profiles := (select p from public.profiles p where display_name = 'Swu Ana');
  bo public.profiles := (select p from public.profiles p where display_name = 'Swu Bo');
  m public.swu_matches := (select m from public.swu_matches m order by id desc limit 1);
begin
  assert ana.swu_rating = 1020 and bo.swu_rating = 980, 'FIDE deltas with K = 40';
  assert ana.swu_peak_rating = 1020 and bo.swu_peak_rating = 1000, 'peaks tracked';
  assert ana.swu_wins = 1 and bo.swu_losses = 1 and ana.swu_matches_played = 1, 'record counted';
  assert ana.rating = 1000 and ana.bg_rating = 1500, 'chess and backgammon untouched';
  assert m.reporter_id = ana.id and m.reporter_rating_before = 1000 and m.reporter_rating_delta = 20
    and m.respondent_rating_delta = -20 and m.reporter_games = 2, 'match row is auditable';
  assert (select count(*) from public.swu_match_requests) = 0, 'request consumed';
end $$;

-- Bo reports a 1-1 draw against the higher-rated Ana, then a declined and a
-- withdrawn one.
select public.request_swu_match('00000000-0000-0000-0000-0000000000a2', 1::smallint, 1::smallint);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a2', false);
select public.respond_to_swu_match((select max(id) from public.swu_match_requests), true);
select public.request_swu_match('00000000-0000-0000-0000-0000000000b2', 0::smallint, 2::smallint);
select public.respond_to_swu_match((select max(id) from public.swu_match_requests), false);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false);
select public.request_swu_match('00000000-0000-0000-0000-0000000000a2', 2::smallint, 0::smallint);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a2', false);
select public.respond_to_swu_match((select max(id) from public.swu_match_requests), false);

do $$
declare
  ana public.profiles := (select p from public.profiles p where display_name = 'Swu Ana');
  bo public.profiles := (select p from public.profiles p where display_name = 'Swu Bo');
begin
  assert ana.swu_rating = 1018 and bo.swu_rating = 982, 'a draw moves the favourite down';
  assert ana.swu_draws = 1 and bo.swu_draws = 1 and bo.swu_matches_played = 2, 'draw counted';
  assert (select count(*) from public.swu_matches) = 2, 'only confirmed matches are rated';
  assert (select count(*) from public.swu_match_requests) = 0, 'withdrawn and declined requests are gone';
  -- Every SWU rating is 1000 plus its match deltas (principle II).
  assert not exists (
    select 1 from public.profiles p
    where p.swu_rating <> 1000 + coalesce((
      select sum(case when x.reporter_id = p.id then x.reporter_rating_delta else x.respondent_rating_delta end)
      from public.swu_matches x where p.id in (x.reporter_id, x.respondent_id)
    ), 0)
  ), 'ratings replay from history';
end $$;

-- Rejections.
do $$
declare
  bo uuid := '00000000-0000-0000-0000-0000000000b2';
begin
  begin
    perform public.request_swu_match(auth.uid(), 2::smallint, 0::smallint);
    raise exception 'self-play should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.request_swu_match(bo, 0::smallint, 0::smallint);
    raise exception '0-0 should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.request_swu_match(bo, 2::smallint, 2::smallint);
    raise exception '2-2 should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.request_swu_match(bo, 3::smallint, 0::smallint);
    raise exception 'three wins should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.request_swu_match(gen_random_uuid(), 2::smallint, 0::smallint);
    raise exception 'unknown opponent should fail';
  exception when sqlstate 'P0002' then null;
  end;
end $$;

-- Members cannot touch SWU ratings or matches directly.
do $$
begin
  begin
    update public.profiles set swu_rating = 3000 where id = auth.uid();
    raise exception 'rating update should be denied';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.swu_match_requests (reporter_id, respondent_id, reporter_games, respondent_games)
    values (auth.uid(), '00000000-0000-0000-0000-0000000000b2', 2, 0);
    raise exception 'direct request insert should be denied';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.swu_matches (reporter_id, respondent_id, reporter_games, respondent_games,
      reporter_rating_before, respondent_rating_before, reporter_rating_delta, respondent_rating_delta)
    values (auth.uid(), '00000000-0000-0000-0000-0000000000b2', 2, 0, 1, 1, 400, -400);
    raise exception 'direct match insert should be denied';
  exception when insufficient_privilege then null;
  end;
end $$;

select set_config('request.jwt.claim.sub', '', false);
do $$
begin
  begin
    perform public.request_swu_match('00000000-0000-0000-0000-0000000000b2', 2::smallint, 0::smallint);
    raise exception 'anonymous record should fail';
  exception when sqlstate '28000' then null;
  end;
end $$;

reset role;
rollback;
\echo 'swu_test: all assertions passed'
