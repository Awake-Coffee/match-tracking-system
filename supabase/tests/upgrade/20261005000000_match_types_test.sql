-- Checks that the rows from upgrade/20261005000000_match_types_seed.sql
-- carried over to the match_type schema unchanged. Each block raises on
-- failure.
\set ON_ERROR_STOP on

do $$
declare
  ana uuid := '00000000-0000-0000-0000-000000000001';
  bo uuid := '00000000-0000-0000-0000-000000000002';
  cy uuid := '00000000-0000-0000-0000-000000000003';
begin
  assert (select count(*) from public.ratings) = 9, 'one rating per member per game';
  assert (select (rating, peak_rating, played, wins, losses, draws, experience)
    from public.ratings where player_id = ana and match_type = 'chess')
    = (1021, 1030, 3, 1, 1, 1, 0), 'chess standing kept';
  assert (select (rating, peak_rating, played, wins, losses, draws, experience)
    from public.ratings where player_id = ana and match_type = 'backgammon')
    = (1510, 1522, 2, 1, 1, 0, 8), 'backgammon standing and experience kept';
  assert (select (rating, peak_rating, played, wins, losses, draws, experience)
    from public.ratings where player_id = cy and match_type = 'swu')
    = (1002, 1020, 3, 1, 1, 1, 0), 'SWU standing kept';
  assert (select (rating, peak_rating, played)
    from public.ratings where player_id = bo and match_type = 'backgammon')
    = (1500, 1500, 0), 'untouched games keep their starting rating';

  assert not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'profiles'
      and column_name not in ('id', 'display_name', 'created_at', 'updated_at')
  ), 'profiles keep only the member''s own fields';
  assert not exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name like any (array['backgammon_%', 'swu_%'])
  ), 'per-game tables are gone';
end $$;

-- Results, in the order they were played.
do $$
declare
  ana uuid := '00000000-0000-0000-0000-000000000001';
  bo uuid := '00000000-0000-0000-0000-000000000002';
  cy uuid := '00000000-0000-0000-0000-000000000003';
  rows text[] := array(
    select format('%s %s-%s %s-%s %s %s/%s %s/%s %s %s %s %s',
      match_type, player1_id = ana, player2_id = ana, player1_score, player2_score, rated,
      player1_rating_before, player2_rating_before, player1_rating_delta, player2_rating_delta,
      coalesce(dgt_option::text, '-'),
      coalesce(custom_base_minutes::text, '-') || '+' || coalesce(custom_extra_seconds::text, '-'),
      recorded_by = player1_id, to_char(played_at at time zone 'UTC', 'HH24'))
    from public.matches order by id);
begin
  assert cardinality(rows) = 7, 'every result carried over';
  -- Chess: white is player 1. Backgammon and SWU: the reporter is.
  assert rows[1] = 'chess t-f 0.0-1.0 t 1000/1000 -20/20 - -+- t 10', rows[1];
  assert rows[2] = 'backgammon t-f 5.0-3.0 t 1500/1500 22/-22 - -+- t 11', rows[2];
  assert rows[3] = 'swu f-f 1.0-2.0 t 1000/1000 -20/20 - -+- t 12', rows[3];
  assert rows[4] = 'chess f-t 0.5-0.5 t 1020/980 -1/1 21 7+4 f 13', rows[4];
  assert rows[5] = 'backgammon t-f 1.0-3.0 t 1522/1478 -12/18 - -+- t 14', rows[5];
  assert rows[6] = 'chess t-f 1.0-0.0 f 981/1000 0/0 10 -+- f 15', rows[6];
  assert rows[7] = 'swu f-f 1.0-1.0 f 1020/980 0/0 - -+- t 16', rows[7];
  assert (select player1_id from public.matches where id = 3) = cy, 'SWU reporter is player 1';
end $$;

-- Pending requests carry over and can still be answered.
do $$
declare
  ana uuid := '00000000-0000-0000-0000-000000000001';
  bo uuid := '00000000-0000-0000-0000-000000000002';
  cy uuid := '00000000-0000-0000-0000-000000000003';
  rows text[] := array(
    select format('%s %s %s %s-%s %s %s %s+%s',
      match_type, player1_id = ana, requested_by = ana, player1_score, player2_score, rated,
      coalesce(dgt_option::text, '-'), coalesce(custom_base_minutes::text, '-'),
      coalesce(custom_extra_seconds::text, '-'))
    from public.match_requests order by id);
begin
  assert cardinality(rows) = 3, 'every request carried over';
  assert rows[1] = 'backgammon t t 2.0-7.0 t - -+-', rows[1];
  assert rows[2] = 'chess f t 0.0-1.0 f 21 7+4', rows[2];
  assert rows[3] = 'swu f f 1.0-0.0 t - -+-', rows[3];
end $$;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', false);
select public.respond_to_match((select id from public.match_requests where match_type = 'backgammon'), true);

do $$
declare
  m public.matches := (select m from public.matches m order by id desc limit 1);
begin
  assert m.match_type = 'backgammon' and m.player1_score = 2 and m.player2_score = 7
    and m.player1_rating_before = 1510 and m.player2_rating_before = 1500
    and m.player1_rating_delta < 0 and m.player2_rating_delta > 0,
    'a carried-over request is rated from the carried-over ratings';
  assert (select (rating, played, losses, experience) from public.ratings
    where player_id = m.player1_id and match_type = 'backgammon')
    = (1510 + m.player1_rating_delta, 3, 2, 15), 'loser''s standing moves on';
end $$;

reset role;

-- Members who join after the upgrade get a rating in every game.
insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000000004', 'di@up.example');

do $$
begin
  assert (select count(*) from public.ratings
    where player_id = '00000000-0000-0000-0000-000000000004'
      and rating = public.starting_rating(match_type)) = 3, 'new member rated in every game';
end $$;

\echo 'match_types upgrade_test: all assertions passed'
