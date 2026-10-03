-- Behavioural tests for the chess Elo migration. Each block raises on failure.
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

-- Sign-up creates profiles at 1000 and de-duplicates display names.
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', 'ana@example.com', '{"display_name":"Ana"}'),
  ('00000000-0000-0000-0000-00000000000b', 'bo@example.com',  '{"display_name":"Bo"}'),
  ('00000000-0000-0000-0000-00000000000c', 'cy@example.com',  '{}'),
  ('00000000-0000-0000-0000-00000000000d', 'ana2@example.com', '{"display_name":"ana"}');

do $$
begin
  assert (select count(*) from public.profiles where rating = 1000) = 4, 'everyone starts at 1000';
  assert (select display_name from public.profiles where id = '00000000-0000-0000-0000-00000000000c') = 'cy',
    'falls back to email local part';
  assert (select display_name from public.profiles where id = '00000000-0000-0000-0000-00000000000d') = 'ana 2',
    'duplicate names get a suffix';
end $$;

-- A game reported by p_by and confirmed by its opponent, through the
-- authenticated role like the app does. Leaves the caller as p_by.
create function pg_temp.play(p_by uuid, p_opponent uuid, p_color text, p_result text)
returns void language plpgsql as $$
declare
  req_id bigint;
begin
  perform set_config('request.jwt.claim.sub', p_by::text, false);
  select id into req_id from public.request_chess_match(p_opponent, p_color, p_result, 10::smallint);
  perform set_config('request.jwt.claim.sub', p_opponent::text, false);
  perform public.respond_to_chess_match(req_id, true);
  perform set_config('request.jwt.claim.sub', p_by::text, false);
end $$;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);

-- A reported game waits for the opponent: nothing moves until they accept.
select public.request_chess_match('00000000-0000-0000-0000-00000000000b', 'white', 'win', 10::smallint);

do $$
declare
  req_id bigint := (select id from public.match_requests order by id desc limit 1);
begin
  assert (select count(*) from public.matches) = 0, 'no match before confirmation';
  assert (select rating from public.profiles where display_name = 'Ana') = 1000, 'rating waits';
  begin
    perform public.respond_to_chess_match(req_id, true);
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
    perform public.respond_to_chess_match((select max(id) from public.match_requests), true);
    raise exception 'outsider should not confirm';
  exception when sqlstate 'P0002' then null;
  end;
end $$;

-- Bo accepts: ratings move and the request is gone.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false);
select public.respond_to_chess_match((select id from public.match_requests order by id desc limit 1), true);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);

do $$
begin
  assert (select rating from public.profiles where display_name = 'Ana') = 1020, 'winner +20';
  assert (select rating from public.profiles where display_name = 'Bo') = 980, 'loser -20';
  assert (select peak_rating from public.profiles where display_name = 'Ana') = 1020, 'peak rises';
  assert (select peak_rating from public.profiles where display_name = 'Bo') = 1000, 'peak stays';
  assert (select wins from public.profiles where display_name = 'Ana') = 1, 'win counted';
  assert (select losses from public.profiles where display_name = 'Bo') = 1, 'loss counted';
  assert (select result from public.matches order by id desc limit 1) = 'white', 'result stored from white';
  assert (select dgt_option from public.matches order by id desc limit 1) = 10, 'time control kept';
  assert (select recorded_by from public.matches order by id desc limit 1) = auth.uid(), 'reporter kept';
  assert (select count(*) from public.match_requests) = 0, 'request consumed';
end $$;

-- Declining or withdrawing drops the request without rating anything.
select public.request_chess_match('00000000-0000-0000-0000-00000000000b', 'white', 'win', 9::smallint);
select public.respond_to_chess_match((select max(id) from public.match_requests), false);
select public.request_chess_match('00000000-0000-0000-0000-00000000000b', 'white', 'win', 9::smallint);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false);
select public.respond_to_chess_match((select max(id) from public.match_requests), false);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);

do $$
begin
  assert (select count(*) from public.match_requests) = 0, 'withdrawn and declined requests are gone';
  assert (select count(*) from public.matches) = 1, 'declined games are not rated';
  assert (select rating from public.profiles where display_name = 'Ana') = 1020, 'rating unchanged';
end $$;

-- Custom presets carry the time actually set on the clock.
select public.request_chess_match('00000000-0000-0000-0000-00000000000b', 'white', 'draw', 21::smallint, 7::smallint, 4::smallint);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false);
select public.respond_to_chess_match((select max(id) from public.match_requests), true);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);

do $$
declare
  m record;
begin
  select * into m from public.matches order by id desc limit 1;
  assert m.dgt_option = 21 and m.custom_base_minutes = 7 and m.custom_extra_seconds = 4,
    'custom Fischer time kept';
  begin
    perform public.request_chess_match('00000000-0000-0000-0000-00000000000b', 'white', 'win', 21::smallint, 7::smallint);
    raise exception 'custom Fischer without increment should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.request_chess_match('00000000-0000-0000-0000-00000000000b', 'white', 'win', 8::smallint);
    raise exception 'custom time without minutes should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.request_chess_match('00000000-0000-0000-0000-00000000000b', 'white', 'win', 9::smallint, 7::smallint);
    raise exception 'fixed preset with custom time should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.request_chess_match('00000000-0000-0000-0000-00000000000b', 'white', 'win', 8::smallint, 0::smallint);
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
  assert m.white_id = '00000000-0000-0000-0000-00000000000b' and m.result = 'draw', 'draw with colors swapped';
  assert (select games_played from public.profiles where display_name = 'Ana') = 4, 'games counted';
  -- Every profile's rating is 1000 plus its match deltas (principle II).
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
begin
  begin
    perform public.request_chess_match('00000000-0000-0000-0000-00000000000a', 'white', 'win', 9::smallint);
    raise exception 'self-play should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.request_chess_match('00000000-0000-0000-0000-00000000000b', 'green', 'win', 9::smallint);
    raise exception 'bad color should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.request_chess_match('00000000-0000-0000-0000-00000000000b', 'white', 'win', 99::smallint);
    raise exception 'unknown time control should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.request_chess_match(gen_random_uuid(), 'white', 'win', 9::smallint);
    raise exception 'unknown opponent should fail';
  exception when sqlstate 'P0002' then null;
  end;
end $$;

-- Members cannot touch ratings or matches directly.
do $$
begin
  begin
    update public.profiles set rating = 3000 where id = auth.uid();
    raise exception 'rating update should be denied';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.match_requests (white_id, black_id, result, dgt_option, requested_by)
    values ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000b', 'white', 9,
            '00000000-0000-0000-0000-00000000000a');
    raise exception 'direct request insert should be denied';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.matches (white_id, black_id, result, white_rating_before, black_rating_before, white_rating_delta, black_rating_delta, recorded_by)
    values ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000b', 'white', 1, 1, 400, -400,
            '00000000-0000-0000-0000-00000000000a');
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
    perform public.request_chess_match('00000000-0000-0000-0000-00000000000b', 'white', 'win', 9::smallint);
    raise exception 'anonymous record should fail';
  exception when sqlstate '28000' then null;
  end;
end $$;

reset role;
\echo 'chess_elo_test: all assertions passed'
