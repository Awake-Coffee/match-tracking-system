-- Behavioural tests for Star Wars: Unlimited ratings. Each block raises on
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
end $$;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000a2', 'ana@swu.example', '{"display_name":"Swu Ana"}'),
  ('00000000-0000-0000-0000-0000000000b2', 'bo@swu.example',  '{"display_name":"Swu Bo"}'),
  ('00000000-0000-0000-0000-0000000000c2', 'cy@swu.example',  '{"display_name":"Swu Cy"}');

-- A member's standing in a game.
create function pg_temp.standing(p_name text, p_type public.match_type) returns public.ratings
language sql as $$
  select r from public.ratings r join public.profiles p on p.id = r.player_id
  where p.display_name = p_name and r.match_type = p_type;
$$;

do $$
begin
  assert (select count(*) from public.ratings r join public.profiles p on p.id = r.player_id
    where p.display_name like 'Swu %' and r.match_type = 'swu'
      and r.rating = 1000 and r.peak_rating = 1000) = 3,
    'everyone starts at 1000';
end $$;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a2', false);

-- Ana reports a 2-1 win: nothing moves until Bo confirms.
select public.request_match('swu', '00000000-0000-0000-0000-0000000000b2', 2, 1);

do $$
declare
  req public.match_requests := (select r from public.match_requests r order by id desc limit 1);
begin
  assert req.match_type = 'swu' and req.player1_id = auth.uid()
    and req.player1_score = 2 and req.player2_score = 1,
    'score stored from the reporter''s side';
  assert (select count(*) from public.matches where match_type = 'swu') = 0,
    'no match before confirmation';
  begin
    perform public.respond_to_match(req.id, true);
    raise exception 'reporter should not confirm their own match';
  exception when sqlstate '42501' then null;
  end;
  assert (select count(*) from public.match_requests) = 1, 'failed self-confirm keeps the request';
end $$;

-- Cy isn't in it: can't see or answer it.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c2', false);
do $$
begin
  assert (select count(*) from public.match_requests) = 0, 'outsiders cannot see requests';
  begin
    perform public.respond_to_match((select max(id) from public.match_requests), true);
    raise exception 'outsider should not confirm';
  exception when sqlstate 'P0002' then null;
  end;
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false);
select public.respond_to_match((select max(id) from public.match_requests), true);

do $$
declare
  ana public.ratings := pg_temp.standing('Swu Ana', 'swu');
  bo public.ratings := pg_temp.standing('Swu Bo', 'swu');
  m public.matches := (select m from public.matches m order by id desc limit 1);
begin
  assert ana.rating = 1020 and bo.rating = 980, 'FIDE deltas with K = 40';
  assert ana.peak_rating = 1020 and bo.peak_rating = 1000, 'peaks tracked';
  assert ana.wins = 1 and bo.losses = 1 and ana.played = 1, 'record counted';
  assert (pg_temp.standing('Swu Ana', 'chess')).rating = 1000
    and (pg_temp.standing('Swu Ana', 'backgammon')).rating = 1500, 'chess and backgammon untouched';
  assert m.match_type = 'swu' and m.player1_id = ana.player_id and m.recorded_by = ana.player_id
    and m.player1_rating_before = 1000 and m.player1_rating_delta = 20
    and m.player2_rating_delta = -20 and m.player1_score = 2, 'match row is auditable';
  assert (select count(*) from public.match_requests) = 0, 'request consumed';
end $$;

-- Bo reports a 1-1 draw against the higher-rated Ana, then a declined and a
-- withdrawn one.
select public.request_match('swu', '00000000-0000-0000-0000-0000000000a2', 1, 1);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a2', false);
select public.respond_to_match((select max(id) from public.match_requests), true);
select public.request_match('swu', '00000000-0000-0000-0000-0000000000b2', 0, 2);
select public.respond_to_match((select max(id) from public.match_requests), false);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false);
select public.request_match('swu', '00000000-0000-0000-0000-0000000000a2', 2, 0);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a2', false);
select public.respond_to_match((select max(id) from public.match_requests), false);

do $$
declare
  ana public.ratings := pg_temp.standing('Swu Ana', 'swu');
  bo public.ratings := pg_temp.standing('Swu Bo', 'swu');
begin
  assert ana.rating = 1018 and bo.rating = 982, 'a draw moves the favourite down';
  assert ana.draws = 1 and bo.draws = 1 and bo.played = 2, 'draw counted';
  assert (select count(*) from public.matches where match_type = 'swu') = 2,
    'only confirmed matches are rated';
  assert (select count(*) from public.match_requests) = 0, 'withdrawn and declined requests are gone';
  -- Every SWU rating is 1000 plus its match deltas (principle II).
  assert not exists (
    select 1 from public.ratings r
    where r.match_type = 'swu' and r.rating <> 1000 + coalesce((
      select sum(case when x.player1_id = r.player_id
        then x.player1_rating_delta else x.player2_rating_delta end)
      from public.matches x
      where x.match_type = 'swu' and r.player_id in (x.player1_id, x.player2_id)
    ), 0)
  ), 'ratings replay from history';
end $$;

-- Rejections.
do $$
declare
  bo uuid := '00000000-0000-0000-0000-0000000000b2';
begin
  begin
    perform public.request_match('swu', auth.uid(), 2, 0);
    raise exception 'self-play should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.request_match('swu', bo, 0, 0);
    raise exception '0-0 should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.request_match('swu', bo, 2, 2);
    raise exception '2-2 should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.request_match('swu', bo, 3, 0);
    raise exception 'three wins should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.request_match('swu', gen_random_uuid(), 2, 0);
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
    insert into public.matches (match_type, player1_id, player2_id, player1_score, player2_score,
      player1_rating_before, player2_rating_before, player1_rating_delta, player2_rating_delta,
      recorded_by)
    values ('swu', auth.uid(), '00000000-0000-0000-0000-0000000000b2', 2, 0, 1, 1, 400, -400,
            auth.uid());
    raise exception 'direct match insert should be denied';
  exception when insufficient_privilege then null;
  end;
end $$;

select set_config('request.jwt.claim.sub', '', false);
do $$
begin
  begin
    perform public.request_match('swu', '00000000-0000-0000-0000-0000000000b2', 2, 0);
    raise exception 'anonymous record should fail';
  exception when sqlstate '28000' then null;
  end;
end $$;

reset role;
rollback;
\echo 'swu_test: all assertions passed'
