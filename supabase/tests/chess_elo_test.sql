-- Behavioural tests for the chess Elo migration. Each block raises on failure.
\set ON_ERROR_STOP on

-- elo_delta matches the Dart implementation (see app/test/elo_test.dart).
do $$
begin
  assert public.elo_delta(1000, 1000, 1) = 16, 'even win';
  assert public.elo_delta(1000, 1000, 0) = -16, 'even loss';
  assert public.elo_delta(1000, 1000, 0.5) = 0, 'even draw';
  assert public.elo_delta(1200, 1000, 1) = 8, 'favourite win';
  assert public.elo_delta(1000, 1200, 1) = 24, 'upset win';
  assert public.elo_delta(1000, 1200, 0.5) = 8, 'underdog draw';
  assert public.elo_delta(1600, 1000, 1) = 1, 'huge favourite win';
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

-- Record games as Ana, through the authenticated role like the app does.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);

select public.record_chess_match('00000000-0000-0000-0000-00000000000b', 'white', 'win');

do $$
begin
  assert (select rating from public.profiles where display_name = 'Ana') = 1016, 'winner +16';
  assert (select rating from public.profiles where display_name = 'Bo') = 984, 'loser -16';
  assert (select wins from public.profiles where display_name = 'Ana') = 1, 'win counted';
  assert (select losses from public.profiles where display_name = 'Bo') = 1, 'loss counted';
  assert (select result from public.matches order by id desc limit 1) = 'white', 'result stored from white';
end $$;

-- Ana plays black against Cy and loses: Cy (white) gains.
select public.record_chess_match('00000000-0000-0000-0000-00000000000c', 'black', 'loss');
-- Draw with Bo, Ana as black.
select public.record_chess_match('00000000-0000-0000-0000-00000000000b', 'black', 'draw');

do $$
declare
  m record;
begin
  select * into m from public.matches order by id desc limit 1;
  assert m.white_id = '00000000-0000-0000-0000-00000000000b' and m.result = 'draw', 'draw with colors swapped';
  assert (select sum(rating) from public.profiles) = 4000, 'ladder is zero-sum';
  assert (select games_played from public.profiles where display_name = 'Ana') = 3, 'games counted';
  -- Every profile's rating is 1000 plus its match deltas (principle II).
  assert not exists (
    select 1 from public.profiles p
    where p.rating <> 1000 + coalesce((
      select sum(case when x.white_id = p.id then x.rating_delta else -x.rating_delta end)
      from public.matches x where p.id in (x.white_id, x.black_id)
    ), 0)
  ), 'ratings replay from history';
end $$;

-- Rejections.
do $$
begin
  begin
    perform public.record_chess_match('00000000-0000-0000-0000-00000000000a', 'white', 'win');
    raise exception 'self-play should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.record_chess_match('00000000-0000-0000-0000-00000000000b', 'green', 'win');
    raise exception 'bad color should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.record_chess_match(gen_random_uuid(), 'white', 'win');
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
    insert into public.matches (white_id, black_id, result, white_rating_before, black_rating_before, rating_delta, recorded_by)
    values ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000b', 'white', 1, 1, 400,
            '00000000-0000-0000-0000-00000000000a');
    raise exception 'direct match insert should be denied';
  exception when insufficient_privilege then null;
  end;
end $$;

-- Cosmetic fields are editable, but only on your own row.
update public.profiles set design = 'bauhaus', display_name = 'Ana K' where id = auth.uid();
update public.profiles set design = 'receipt' where display_name = 'Bo';

do $$
begin
  assert (select design from public.profiles where display_name = 'Ana K') = 'bauhaus', 'own design saved';
  assert (select design from public.profiles where display_name = 'Bo') = 'chalkboard', 'cannot edit others';
end $$;

-- Signed-out callers can't record.
select set_config('request.jwt.claim.sub', '', false);
do $$
begin
  begin
    perform public.record_chess_match('00000000-0000-0000-0000-00000000000b', 'white', 'win');
    raise exception 'anonymous record should fail';
  exception when sqlstate '28000' then null;
  end;
end $$;

reset role;
\echo 'chess_elo_test: all assertions passed'
