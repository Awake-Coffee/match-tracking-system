-- Rows in the per-game schema, so upgrade/20261005000000_match_types_test.sql
-- can check how they carry over to the match_type schema.
\set ON_ERROR_STOP on

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000001', 'ana@up.example', '{"display_name":"Ana"}'),
  ('00000000-0000-0000-0000-000000000002', 'bo@up.example',  '{"display_name":"Bo"}'),
  ('00000000-0000-0000-0000-000000000003', 'cy@up.example',  '{"display_name":"Cy"}');

update public.profiles set
  rating = 1021, peak_rating = 1030, games_played = 3, wins = 1, losses = 1, draws = 1,
  bg_rating = 1510, bg_peak_rating = 1522, bg_matches_played = 2, bg_wins = 1, bg_losses = 1,
  bg_experience = 8
where display_name = 'Ana';

update public.profiles set
  swu_rating = 1002, swu_peak_rating = 1020, swu_matches_played = 3, swu_wins = 1,
  swu_losses = 1, swu_draws = 1
where display_name = 'Cy';

-- Ana = ...01, Bo = ...02, Cy = ...03. Each game's rows are interleaved in
-- time so the carried-over ids have to follow played_at, not the old tables.
insert into public.matches (
  white_id, black_id, result, white_rating_before, black_rating_before,
  white_rating_delta, black_rating_delta, recorded_by, played_at, dgt_option,
  custom_base_minutes, custom_extra_seconds, rated
) values
  -- Before time controls were tracked.
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', 'black',
   1000, 1000, -20, 20, '00000000-0000-0000-0000-000000000001', '2026-10-01 10:00Z', null, null, null, true),
  ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'draw',
   1020, 980, -1, 1, '00000000-0000-0000-0000-000000000001', '2026-10-01 13:00Z', 21, 7, 4, true),
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000003', 'white',
   981, 1000, 0, 0, '00000000-0000-0000-0000-000000000003', '2026-10-01 15:00Z', 10, null, null, false);

insert into public.backgammon_matches (
  winner_id, loser_id, match_length, loser_score, winner_rating_before, loser_rating_before,
  winner_rating_delta, loser_rating_delta, recorded_by, played_at, rated
) values
  -- Reported by the winner, then by the loser.
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000003', 5, 3,
   1500, 1500, 22, -22, '00000000-0000-0000-0000-000000000001', '2026-10-01 11:00Z', true),
  ('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001', 3, 1,
   1478, 1522, 18, -12, '00000000-0000-0000-0000-000000000001', '2026-10-01 14:00Z', true);

insert into public.swu_matches (
  reporter_id, respondent_id, reporter_games, respondent_games, reporter_rating_before,
  respondent_rating_before, reporter_rating_delta, respondent_rating_delta, played_at, rated
) values
  ('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000002', 1, 2,
   1000, 1000, -20, 20, '2026-10-01 12:00Z', true),
  ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000003', 1, 1,
   1020, 980, 0, 0, '2026-10-01 16:00Z', false);

insert into public.match_requests (
  white_id, black_id, result, dgt_option, custom_base_minutes, custom_extra_seconds,
  requested_by, created_at, rated
) values
  -- Reported by black.
  ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'black',
   21, 7, 4, '00000000-0000-0000-0000-000000000001', '2026-10-02 10:00Z', false);

insert into public.backgammon_match_requests (
  winner_id, loser_id, match_length, loser_score, requested_by, created_at
) values
  -- Reported by the loser.
  ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 7, 2,
   '00000000-0000-0000-0000-000000000001', '2026-10-02 09:00Z');

insert into public.swu_match_requests (
  reporter_id, respondent_id, reporter_games, respondent_games, created_at
) values
  ('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001', 1, 0,
   '2026-10-02 11:00Z');
