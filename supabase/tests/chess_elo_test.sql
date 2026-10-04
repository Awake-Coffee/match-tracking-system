-- Behavioural tests for chess ratings. Each block raises on failure.
\set ON_ERROR_STOP on

-- fide_rating_change matches the Dart implementation (see app/test/elo_test.dart).
do $$
begin
  assert public.fide_rating_change(1000, 0, 1000, 1000, 1) = 20, 'newcomer win';
  assert public.fide_rating_change(1000, 0, 1000, 1000, 0) = -20, 'newcomer loss';
  assert public.fide_rating_change(1000, 0, 1000, 1000, 0.5) = 0, 'even draw';
  assert public.fide_rating_change(1200, 0, 1200, 1000, 1) = 10, 'favourite win';
  assert public.fide_rating_change(1000, 0, 1000, 1200, 1) = 30, 'upset win';
  assert public.fide_rating_change(1000, 0, 1000, 1200, 0.5) = 10, 'underdog draw';
  assert public.fide_rating_change(1000, 30, 1000, 1000, 1) = 10, 'K 20 after 30 games';
  assert public.fide_rating_change(1600, 30, 1600, 1000, 1) = 2, '400-point rule';
  assert public.fide_rating_change(2400, 30, 2400, 2400, 1) = 5, 'K 10 from 2400';
  assert public.fide_rating_change(2435, 30, 2435, 2400, 1) = 5, 'half rounds up';
  assert public.fide_rating_change(2435, 30, 2435, 2400, 0) = -5, 'negative half rounds up';
  assert public.fide_rating_change(2300, 30, 2400, 2300, 1) = 5, 'K 10 stays after dropping below 2400';
end $$;

do $$
begin
  assert public.is_valid_score('chess', 1, 0) and public.is_valid_score('chess', 0, 1)
    and public.is_valid_score('chess', 0.5, 0.5), 'chess results accepted';
  assert not public.is_valid_score('chess', 1, 1) and not public.is_valid_score('chess', 0, 0)
    and not public.is_valid_score('chess', 2, 0) and not public.is_valid_score('chess', null, 1),
    'impossible chess results rejected';
end $$;

-- Sign-up creates profiles with a starting rating in every game and
-- de-duplicates display names.
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', 'ana@example.com', '{"display_name":"Ana"}'),
  ('00000000-0000-0000-0000-00000000000b', 'bo@example.com',  '{"display_name":"Bo"}'),
  ('00000000-0000-0000-0000-00000000000c', 'cy@example.com',  '{}'),
  ('00000000-0000-0000-0000-00000000000d', 'ana2@example.com', '{"display_name":"ana"}');

do $$
begin
  assert (select count(*) from public.ratings
    where match_type = 'chess' and rating = 1000 and peak_rating = 1000 and played = 0) = 4,
    'everyone starts at 1000';
  assert (select count(*) from public.ratings) = 4 * cardinality(enum_range(null::public.match_type)),
    'one rating per member per game';
  assert (select display_name from public.profiles where id = '00000000-0000-0000-0000-00000000000c') = 'cy',
    'falls back to email local part';
  assert (select display_name from public.profiles where id = '00000000-0000-0000-0000-00000000000d') = 'ana 2',
    'duplicate names get a suffix';
end $$;

-- A member's chess standing.
create function pg_temp.chess(p_name text) returns public.ratings
language sql as $$
  select r from public.ratings r join public.profiles p on p.id = r.player_id
  where p.display_name = p_name and r.match_type = 'chess';
$$;

-- Reports a chess game from the caller's side: result is 'win' | 'loss' | 'draw'.
create function pg_temp.report(
  p_opponent uuid, p_color text, p_result text, p_dgt smallint,
  p_base smallint default null, p_extra smallint default null
) returns public.match_requests
language sql as $$
  select public.request_match(
    'chess', p_opponent,
    case p_result when 'win' then 1 when 'loss' then 0 else 0.5 end,
    case p_result when 'win' then 0 when 'loss' then 1 else 0.5 end,
    true, p_color, p_dgt, p_base, p_extra);
$$;

-- A game reported by p_by and confirmed by its opponent, through the
-- authenticated role like the app does. Leaves the caller as p_by.
create function pg_temp.play(p_by uuid, p_opponent uuid, p_color text, p_result text)
returns void language plpgsql as $$
declare
  req_id bigint;
begin
  perform set_config('request.jwt.claim.sub', p_by::text, false);
  select id into req_id from pg_temp.report(p_opponent, p_color, p_result, 10::smallint);
  perform set_config('request.jwt.claim.sub', p_opponent::text, false);
  perform public.respond_to_match(req_id, true);
  perform set_config('request.jwt.claim.sub', p_by::text, false);
end $$;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);

-- A reported game waits for the opponent: nothing moves until they accept.
select pg_temp.report('00000000-0000-0000-0000-00000000000b', 'white', 'win', 10::smallint);

do $$
declare
  req public.match_requests := (select r from public.match_requests r order by id desc limit 1);
begin
  assert req.match_type = 'chess' and req.player1_id = auth.uid()
    and req.player1_score = 1 and req.player2_score = 0, 'white is player 1';
  assert (select count(*) from public.matches) = 0, 'no match before confirmation';
  assert (pg_temp.chess('Ana')).rating = 1000, 'rating waits';
  begin
    perform public.respond_to_match(req.id, true);
    raise exception 'reporter should not confirm their own game';
  exception when sqlstate '42501' then null;
  end;
  assert (select count(*) from public.match_requests) = 1, 'failed self-confirm keeps the request';
end $$;

-- Cy is not a player in it: can't see or answer it.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000c', false);
do $$
begin
  assert (select count(*) from public.match_requests) = 0, 'outsiders cannot see requests';
  begin
    perform public.respond_to_match((select max(id) from public.match_requests), true);
    raise exception 'outsider should not confirm';
  exception when sqlstate 'P0002' then null;
  end;
end $$;

-- Bo accepts: ratings move and the request is gone.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false);
select public.respond_to_match((select id from public.match_requests order by id desc limit 1), true);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);

do $$
declare
  m public.matches := (select m from public.matches m order by id desc limit 1);
begin
  assert (pg_temp.chess('Ana')).rating = 1020, 'winner +20';
  assert (pg_temp.chess('Bo')).rating = 980, 'loser -20';
  assert (pg_temp.chess('Ana')).peak_rating = 1020, 'peak rises';
  assert (pg_temp.chess('Bo')).peak_rating = 1000, 'peak stays';
  assert (pg_temp.chess('Ana')).wins = 1, 'win counted';
  assert (pg_temp.chess('Bo')).losses = 1, 'loss counted';
  assert m.match_type = 'chess' and m.player1_score = 1 and m.player2_score = 0,
    'result stored from white';
  assert m.player1_rating_before = 1000 and m.player1_rating_delta = 20
    and m.player2_rating_delta = -20, 'match row is auditable';
  assert m.dgt_option = 10, 'time control kept';
  assert m.recorded_by = auth.uid(), 'reporter kept';
  assert (select count(*) from public.match_requests) = 0, 'request consumed';
  assert (select count(*) from public.ratings where match_type <> 'chess' and played > 0) = 0,
    'other games untouched';
end $$;

-- Declining or withdrawing drops the request without rating anything.
select pg_temp.report('00000000-0000-0000-0000-00000000000b', 'white', 'win', 9::smallint);
select public.respond_to_match((select max(id) from public.match_requests), false);
select pg_temp.report('00000000-0000-0000-0000-00000000000b', 'white', 'win', 9::smallint);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false);
select public.respond_to_match((select max(id) from public.match_requests), false);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);

do $$
begin
  assert (select count(*) from public.match_requests where status = 'pending') = 0, 'withdrawn and declined requests stop waiting';
  assert (select count(*) from public.match_requests) = 1, 'withdrawing deletes, declining keeps the request for the reporter';
  assert (select count(*) from public.matches) = 1, 'declined games are not rated';
  assert (pg_temp.chess('Ana')).rating = 1020, 'rating unchanged';
end $$;

-- Custom presets carry the time actually set on the clock.
select pg_temp.report('00000000-0000-0000-0000-00000000000b', 'white', 'draw', 21::smallint, 7::smallint, 4::smallint);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false);
select public.respond_to_match((select max(id) from public.match_requests), true);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);

do $$
declare
  m record;
begin
  select * into m from public.matches order by id desc limit 1;
  assert m.dgt_option = 21 and m.custom_base_minutes = 7 and m.custom_extra_seconds = 4,
    'custom Fischer time kept';
  begin
    perform pg_temp.report('00000000-0000-0000-0000-00000000000b', 'white', 'win', 21::smallint, 7::smallint);
    raise exception 'custom Fischer without increment should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform pg_temp.report('00000000-0000-0000-0000-00000000000b', 'white', 'win', 8::smallint);
    raise exception 'custom time without minutes should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform pg_temp.report('00000000-0000-0000-0000-00000000000b', 'white', 'win', 9::smallint, 7::smallint);
    raise exception 'fixed preset with custom time should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform pg_temp.report('00000000-0000-0000-0000-00000000000b', 'white', 'win', 8::smallint, 0::smallint);
    raise exception 'zero minutes should fail';
  exception when sqlstate '22023' then null;
  end;
end $$;

-- Ana plays black against Cy and loses: Cy (white) gains.
select pg_temp.play('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000c', 'black', 'loss');
-- Draw with Bo, Ana as black.
select pg_temp.play('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000b', 'black', 'draw');

do $$
declare
  m record;
begin
  select * into m from public.matches order by id desc limit 1;
  assert m.player1_id = '00000000-0000-0000-0000-00000000000b' and m.player1_score = 0.5
    and m.player2_score = 0.5 and m.recorded_by = m.player2_id, 'draw with colors swapped';
  assert (pg_temp.chess('Ana')).played = 4, 'games counted';
  assert (pg_temp.chess('Ana')).draws = 2, 'draws counted';
  -- Every rating is the starting rating plus its match deltas (principle II).
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
begin
  begin
    perform pg_temp.report('00000000-0000-0000-0000-00000000000a', 'white', 'win', 9::smallint);
    raise exception 'self-play should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform pg_temp.report('00000000-0000-0000-0000-00000000000b', 'green', 'win', 9::smallint);
    raise exception 'bad color should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.request_match('chess', '00000000-0000-0000-0000-00000000000b', 1, 0, true, null, 9::smallint);
    raise exception 'missing color should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.request_match('chess', '00000000-0000-0000-0000-00000000000b', 1, 1, true, 'white', 9::smallint);
    raise exception 'two winners should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform pg_temp.report('00000000-0000-0000-0000-00000000000b', 'white', 'win', 99::smallint);
    raise exception 'unknown time control should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.request_match('chess', '00000000-0000-0000-0000-00000000000b', 1, 0, true, 'white');
    raise exception 'missing time control should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform pg_temp.report(gen_random_uuid(), 'white', 'win', 9::smallint);
    raise exception 'unknown opponent should fail';
  exception when sqlstate 'P0002' then null;
  end;
end $$;

-- Members cannot touch ratings or matches directly.
do $$
begin
  begin
    update public.ratings set rating = 3000 where player_id = auth.uid();
    raise exception 'rating update should be denied';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.ratings (player_id, match_type, rating, peak_rating)
    values (auth.uid(), 'chess', 3000, 3000);
    raise exception 'rating insert should be denied';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.match_requests (match_type, player1_id, player2_id, player1_score,
      player2_score, dgt_option, requested_by)
    values ('chess', '00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000b',
            1, 0, 9, '00000000-0000-0000-0000-00000000000a');
    raise exception 'direct request insert should be denied';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.matches (match_type, player1_id, player2_id, player1_score, player2_score,
      player1_rating_before, player2_rating_before, player1_rating_delta, player2_rating_delta,
      recorded_by)
    values ('chess', '00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000b',
            1, 0, 1, 1, 400, -400, '00000000-0000-0000-0000-00000000000a');
    raise exception 'direct match insert should be denied';
  exception when insufficient_privilege then null;
  end;
end $$;

-- Display names are editable, but only on your own row.
update public.profiles set display_name = 'Ana K' where id = auth.uid();
update public.profiles set display_name = 'Bo K' where display_name = 'Bo';

do $$
begin
  assert exists (select 1 from public.profiles where display_name = 'Ana K'), 'own name saved';
  assert exists (select 1 from public.profiles where display_name = 'Bo'), 'cannot edit others';
end $$;

-- Signed-out callers can't record.
select set_config('request.jwt.claim.sub', '', false);
do $$
begin
  begin
    perform pg_temp.report('00000000-0000-0000-0000-00000000000b', 'white', 'win', 9::smallint);
    raise exception 'anonymous record should fail';
  exception when sqlstate '28000' then null;
  end;
end $$;

reset role;
\echo 'chess_elo_test: all assertions passed'
