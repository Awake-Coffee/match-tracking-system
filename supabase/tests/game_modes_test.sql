-- Behavioural tests for game modes: a rating per mode, and results with more
-- than two players. Each block raises on failure. Rolled back so other tests
-- see an empty database.
\set ON_ERROR_STOP on
begin;

-- Which results each format accepts.
create function pg_temp.reason(p_type public.match_type, p_mode text, p_players text) returns text
language sql as $$
  select public.invalid_result_reason(p_type, p_mode, p_players::jsonb);
$$;

-- Players as [[side, score], ...]; ids are made up, only the shape counts.
create function pg_temp.shape(p_sides text) returns text
language sql as $$
  select jsonb_agg(jsonb_build_object('player_id', gen_random_uuid(), 'side', s->0, 'score', s->1))::text
  from jsonb_array_elements(p_sides::jsonb) s;
$$;

do $$
begin
  assert pg_temp.reason('chess', 'chess960', pg_temp.shape('[[1,1],[2,0]]')) is null, 'a chess960 duel';
  assert pg_temp.reason('chess', 'blitz', pg_temp.shape('[[1,1],[2,0]]')) = 'Pick a mode of this game',
    'unknown mode';
  assert pg_temp.reason('swu', 'chess960', pg_temp.shape('[[1,2],[2,0]]')) = 'Pick a mode of this game',
    'another game''s mode';
  assert pg_temp.reason('chess', 'standard', pg_temp.shape('[[1,1],[2,0],[2,0]]')) = 'Pick one opponent',
    'a duel has two players';
  assert pg_temp.reason('chess', 'bughouse', pg_temp.shape('[[1,1],[1,1],[2,0],[2,0]]')) is null,
    'bughouse two against two';
  assert pg_temp.reason('chess', 'bughouse', pg_temp.shape('[[1,1],[2,0]]')) = 'Each team has two players',
    'bughouse needs four';
  assert pg_temp.reason('chess', 'bughouse', pg_temp.shape('[[1,1],[1,0],[2,0],[2,0]]'))
    = 'Teammates share one result', 'teammates can''t split a result';
  assert pg_temp.reason('chess', 'bughouse', pg_temp.shape('[[1,1],[1,1],[2,1],[2,1]]'))
    = 'Result must be win, loss or draw', 'chess scores between the teams';
  assert pg_temp.reason('backgammon', 'chouette', pg_temp.shape('[[1,3],[2,5],[2,5]]')) is null,
    'a chouette';
  assert pg_temp.reason('backgammon', 'chouette', pg_temp.shape('[[1,3],[1,3],[2,5],[2,5]]'))
    = 'One box against a team of 2 to 5', 'one box';
  assert pg_temp.reason('backgammon', 'chouette', pg_temp.shape('[[1,3],[2,5]]'))
    = 'One box against a team of 2 to 5', 'a team of at least two';
  -- Twin Suns scores: 0 first out, 1 out in the final round, 2 survived, 3 winner.
  assert pg_temp.reason('swu', 'twin_suns', pg_temp.shape('[[1,3],[2,2],[3,1],[4,0]]')) is null,
    'twin suns for four';
  assert pg_temp.reason('swu', 'twin_suns', pg_temp.shape('[[1,3],[2,2],[3,2],[4,0]]')) is null,
    'two survivors';
  assert pg_temp.reason('swu', 'twin_suns', pg_temp.shape('[[1,0],[2,1],[3,3]]')) is null,
    'twin suns for three, in any side order';
  assert pg_temp.reason('swu', 'twin_suns', pg_temp.shape('[[1,3],[2,0]]')) = 'Three or four players',
    'not for two';
  assert pg_temp.reason('swu', 'twin_suns', pg_temp.shape('[[1,3],[2,2],[3,1],[4,0],[5,0]]'))
    = 'Three or four players', 'at most four';
  assert pg_temp.reason('swu', 'twin_suns', pg_temp.shape('[[1,3],[2,3],[3,0]]'))
    = 'One winner, one player out first, and how everyone else finished', 'one winner';
  assert pg_temp.reason('swu', 'twin_suns', pg_temp.shape('[[1,3],[2,2],[3,1]]'))
    = 'One winner, one player out first, and how everyone else finished', 'someone was out first';
  assert pg_temp.reason('swu', 'twin_suns', pg_temp.shape('[[1,3],[2,0],[3,0]]'))
    = 'One winner, one player out first, and how everyone else finished', 'only one was out first';
  assert pg_temp.reason('swu', 'twin_suns', pg_temp.shape('[[1,3],[2,4],[3,0]]'))
    = 'One winner, one player out first, and how everyone else finished', 'no other finishes';
  assert public.invalid_result_reason('swu', 'twin_suns', pg_temp.shape('[[1,3],[2,1],[3,0]]')::jsonb, 3::smallint)
    = 'Only Star Wars: Unlimited duels are a best of one or three', 'twin suns has no best of';
  assert pg_temp.reason('swu', 'twin_suns', pg_temp.shape('[[1,3],[2,0],[4,1]]')) = 'Number the sides from 1',
    'no gaps between sides';
  assert pg_temp.reason('swu', 'premier', '[{"player_id":"x","side":1}]')
    = 'Each player needs a side and a score', 'a player without a score';
end $$;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000e1', 'a@modes.example', '{"display_name":"Mode A"}'),
  ('00000000-0000-0000-0000-0000000000e2', 'b@modes.example', '{"display_name":"Mode B"}'),
  ('00000000-0000-0000-0000-0000000000e3', 'c@modes.example', '{"display_name":"Mode C"}'),
  ('00000000-0000-0000-0000-0000000000e4', 'd@modes.example', '{"display_name":"Mode D"}'),
  ('00000000-0000-0000-0000-0000000000e5', 'e@modes.example', '{"display_name":"Mode E"}');

-- Players as [[member letter, side, score], ...].
create function pg_temp.players(p_sides text) returns jsonb
language sql as $$
  select jsonb_agg(jsonb_build_object(
    'player_id', '00000000-0000-0000-0000-0000000000e' || (position(s->>0 in 'ABCDE')),
    'side', s->1, 'score', s->2))
  from jsonb_array_elements(p_sides::jsonb) s;
$$;

create function pg_temp.as_member(p_letter text) returns void
language sql as $$
  select set_config('request.jwt.claim.sub',
    '00000000-0000-0000-0000-0000000000e' || position(p_letter in 'ABCDE'), false);
$$;

create function pg_temp.standing(p_letter text, p_type public.match_type, p_mode text)
returns public.ratings
language sql as $$
  select r from public.ratings r
  where r.player_id = ('00000000-0000-0000-0000-0000000000e' || position(p_letter in 'ABCDE'))::uuid
    and r.match_type = p_type and r.mode = p_mode;
$$;

set role authenticated;

-- A chess960 game is rated on its own ladder.
select pg_temp.as_member('A');
select public.request_match('chess', 'chess960', pg_temp.players('[["A",1,1],["B",2,0]]'), true, 9::smallint);
select pg_temp.as_member('B');
select public.respond_to_match((select max(id) from public.match_requests), true);

do $$
begin
  assert (pg_temp.standing('A', 'chess', 'chess960')).rating = 1020
    and (pg_temp.standing('B', 'chess', 'chess960')).rating = 980, 'chess960 rated with FIDE';
  assert pg_temp.standing('A', 'chess', 'standard') is null, 'standard chess untouched';
  assert (select mode from public.matches order by id desc limit 1) = 'chess960', 'result keeps its mode';
end $$;

-- Twin Suns for four: D is out first, C is knocked out in the final round, B
-- survives it and A ends it with the most HP. Every other player has to
-- confirm before anything is rated.
select pg_temp.as_member('A');
select public.request_match('swu', 'twin_suns',
  pg_temp.players('[["A",1,3],["B",2,2],["C",3,1],["D",4,0]]'));

do $$
begin
  begin
    perform public.respond_to_match((select max(id) from public.match_requests), true);
    raise exception 'the reporter should not confirm their own result';
  exception when sqlstate '42501' then null;
  end;
end $$;

select pg_temp.as_member('B');
do $$
begin
  assert public.respond_to_match((select max(id) from public.match_requests), true) is null,
    'one confirmation of three rates nothing';
  assert (select array_agg(confirmed order by side) from public.match_request_players
    where request_id = (select max(id) from public.match_requests)) = array[true, true, false, false],
    'B and the reporter confirmed';
end $$;

select pg_temp.as_member('E');
do $$
begin
  assert (select count(*) from public.match_requests) = 0
    and (select count(*) from public.match_request_players) = 0, 'outsiders see nothing';
end $$;

select pg_temp.as_member('C');
do $$
begin
  assert (select count(*) from public.match_request_players) = 4, 'every player sees who plays';
end $$;
select public.respond_to_match((select max(id) from public.match_requests), true);
select pg_temp.as_member('D');
select public.respond_to_match((select max(id) from public.match_requests), true);

do $$
declare
  m public.matches := (select m from public.matches m order by id desc limit 1);
begin
  assert m.mode = 'twin_suns' and m.recorded_by = '00000000-0000-0000-0000-0000000000e1',
    'rated once everyone confirmed';
  -- Winner +2, survivor +1, out in the final round 0; D's -1 stops at 0.
  assert (select array_agg(format('%s %s %s', player_name, rating_before, rating_delta) order by side)
    from public.match_players where match_id = m.id)
    = array['Mode A 0 2', 'Mode B 0 1', 'Mode C 0 0', 'Mode D 0 0'],
    'twin suns points, never below 0';
  assert (select array_agg(format('%s-%s-%s', wins, losses, draws) order by player_id)
    from public.ratings where match_type = 'swu' and mode = 'twin_suns')
    = array['1-0-0', '0-1-0', '0-1-0', '0-1-0'], 'only the winner wins';
  assert (select count(*) from public.match_requests) = 0, 'request consumed';
end $$;

-- A rematch: now A, with points to lose, is out first; D wins.
select pg_temp.as_member('D');
select public.request_match('swu', 'twin_suns',
  pg_temp.players('[["A",1,0],["B",2,2],["C",3,1],["D",4,3]]'));
select pg_temp.as_member('A');
select public.respond_to_match((select max(id) from public.match_requests), true);
select pg_temp.as_member('B');
select public.respond_to_match((select max(id) from public.match_requests), true);
select pg_temp.as_member('C');
select public.respond_to_match((select max(id) from public.match_requests), true);

do $$
begin
  assert (select array_agg(format('%s %s %s', player_name, rating_before, rating_delta) order by side)
    from public.match_players where match_id = (select max(id) from public.matches))
    = array['Mode A 2 -1', 'Mode B 1 1', 'Mode C 0 0', 'Mode D 0 2'], 'first out loses 1';
end $$;

-- Bughouse: A and B against C and D. B, a teammate, declines A's report.
select pg_temp.as_member('A');
select public.request_match('chess', 'bughouse',
  pg_temp.players('[["A",1,1],["B",1,1],["C",2,0],["D",2,0]]'), true, 1::smallint);
select pg_temp.as_member('C');
select public.respond_to_match((select max(id) from public.match_requests), true);
select pg_temp.as_member('B');
select public.respond_to_match((select max(id) from public.match_requests), false);

do $$
begin
  assert (select count(*) from public.match_requests) = 0, 'the decliner no longer sees it';
end $$;
select pg_temp.as_member('C');
do $$
begin
  assert (select count(*) from public.match_requests) = 0, 'nor does anyone else but the reporter';
end $$;
select pg_temp.as_member('A');
do $$
declare
  req public.match_requests := (select r from public.match_requests r);
begin
  assert req.status = 'declined'
    and req.declined_by = '00000000-0000-0000-0000-0000000000e2', 'the reporter learns who declined';
  assert pg_temp.standing('A', 'chess', 'bughouse') is null, 'nothing rated';
  begin
    perform public.respond_to_match(req.id, true);
    raise exception 'a declined result can''t be confirmed';
  exception when sqlstate 'P0002' then null;
  end;
end $$;
select public.dismiss_declined_match((select id from public.match_requests));

-- Chouette: E in the box loses 3-5 to the team of A, B and C.
select pg_temp.as_member('E');
select public.request_match('backgammon', 'chouette',
  pg_temp.players('[["E",1,3],["A",2,5],["B",2,5],["C",2,5]]'));
select pg_temp.as_member('A');
select public.respond_to_match((select max(id) from public.match_requests), true);
select pg_temp.as_member('B');
select public.respond_to_match((select max(id) from public.match_requests), true);
select pg_temp.as_member('C');
select public.respond_to_match((select max(id) from public.match_requests), true);

do $$
begin
  -- FIBS for a match to 5 between equals: 22 points.
  assert (select array_agg(format('%s %s', player_name, rating_delta) order by side, player_name)
    from public.match_players where match_id = (select max(id) from public.matches))
    = array['Mode E -22', 'Mode A 22', 'Mode B 22', 'Mode C 22'], 'box against each team member';
  assert (select array_agg(experience) from public.ratings where mode = 'chouette') = array[5, 5, 5, 5],
    'everyone gains the match length as experience';
end $$;

-- Every rating is the starting rating plus its result deltas, per mode
-- (principle II).
do $$
begin
  assert not exists (
    select 1 from public.ratings r
    where r.rating <> public.starting_rating(r.match_type) + coalesce((
      select sum(p.rating_delta) from public.match_players p join public.matches m on m.id = p.match_id
      where m.match_type = r.match_type and m.mode = r.mode and p.player_id = r.player_id
    ), 0)
  ), 'ratings replay from history';
end $$;

-- Rejections at the RPC.
select pg_temp.as_member('A');
do $$
begin
  begin
    perform public.request_match('swu', 'twin_suns', pg_temp.players('[["B",1,3],["C",2,0],["D",3,1]]'));
    raise exception 'reporting a game without yourself should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.request_match('swu', 'twin_suns', pg_temp.players('[["A",1,3],["A",2,0],["B",3,1]]'));
    raise exception 'playing twice should fail';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.request_match('chess', 'bughouse',
      pg_temp.players('[["A",1,1],["B",1,1],["C",2,0],["D",2,0]]'));
    raise exception 'bughouse without a clock should fail';
  exception when sqlstate '22023' then null;
  end;
end $$;

-- A member leaving drops the open results they're in.
select public.request_match('swu', 'twin_suns', pg_temp.players('[["A",1,3],["B",2,0],["E",3,1]]'));
reset role;
delete from auth.users where id = '00000000-0000-0000-0000-0000000000e5';
do $$
begin
  assert not exists (select 1 from public.match_requests where mode = 'twin_suns'),
    'request dropped with a player';
end $$;

rollback;
\echo 'game_modes_test: all assertions passed'
