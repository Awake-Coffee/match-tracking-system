-- Rows in the two-player schema, so upgrade/20261007000000_game_modes_test.sql
-- can check how they carry over to game modes.
\set ON_ERROR_STOP on

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000011', 'ana@modes.example', '{"display_name":"Ana"}'),
  ('00000000-0000-0000-0000-000000000012', 'bo@modes.example',  '{"display_name":"Bo"}');

update public.ratings set rating = 1020, peak_rating = 1020, played = 1, wins = 1
  where player_id = '00000000-0000-0000-0000-000000000011' and match_type = 'chess';
update public.ratings set rating = 980, played = 1, losses = 1
  where player_id = '00000000-0000-0000-0000-000000000012' and match_type = 'chess';

-- Ana (white) beat Bo; Bo has since been renamed, and the copy followed.
insert into public.matches (
  match_type, player1_id, player2_id, player1_score, player2_score,
  player1_rating_before, player2_rating_before, player1_rating_delta, player2_rating_delta,
  dgt_option, recorded_by, played_at
) values (
  'chess', '00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000012', 1, 0,
  1000, 1000, 20, -20, 9, '00000000-0000-0000-0000-000000000012', '2026-10-06 10:00Z'
);
update public.profiles set display_name = 'Bo Renamed' where id = '00000000-0000-0000-0000-000000000012';

-- Bo's SWU report that Ana declined, and Ana's backgammon report still
-- waiting for Bo.
insert into public.match_requests (
  match_type, player1_id, player2_id, player1_score, player2_score, requested_by,
  status, responded_at, created_at
) values
  ('swu', '00000000-0000-0000-0000-000000000012', '00000000-0000-0000-0000-000000000011', 2, 1,
   '00000000-0000-0000-0000-000000000012', 'declined', '2026-10-06 12:00Z', '2026-10-06 11:00Z'),
  ('backgammon', '00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000012', 5, 2,
   '00000000-0000-0000-0000-000000000011', 'pending', null, '2026-10-06 13:00Z');
