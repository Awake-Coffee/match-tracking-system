-- SWU results and requests rated with FIDE, so
-- upgrade/20261008000000_swu_points_test.sql can check how they are
-- re-scored with points.
\set ON_ERROR_STOP on

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000021', 'ana@points.example', '{"display_name":"Ana"}'),
  ('00000000-0000-0000-0000-000000000022', 'bo@points.example',  '{"display_name":"Bo"}'),
  ('00000000-0000-0000-0000-000000000023', 'cy@points.example',  '{"display_name":"Cy"}'),
  ('00000000-0000-0000-0000-000000000024', 'di@points.example',  '{"display_name":"Di"}');

-- FIDE standings; Cy has a Premier rating but no results.
insert into public.ratings (player_id, match_type, mode, rating, peak_rating, played, wins, losses, draws) values
  ('00000000-0000-0000-0000-000000000021', 'swu', 'premier', 1001, 1020, 3, 1, 1, 1),
  ('00000000-0000-0000-0000-000000000022', 'swu', 'premier', 999, 1001, 3, 1, 1, 1),
  ('00000000-0000-0000-0000-000000000023', 'swu', 'premier', 1000, 1000, 0, 0, 0, 0),
  ('00000000-0000-0000-0000-000000000021', 'swu', 'twin_suns', 1020, 1020, 1, 1, 0, 0),
  ('00000000-0000-0000-0000-000000000022', 'swu', 'twin_suns', 1007, 1007, 1, 0, 1, 0),
  ('00000000-0000-0000-0000-000000000023', 'swu', 'twin_suns', 987, 1000, 1, 0, 1, 0),
  ('00000000-0000-0000-0000-000000000024', 'swu', 'twin_suns', 987, 1000, 1, 0, 1, 0),
  ('00000000-0000-0000-0000-000000000021', 'chess', 'standard', 1020, 1020, 1, 1, 0, 0);

-- Premier, inserted out of order so the replay has to follow played_at:
-- Ana beats Bo 2-1, Bo beats Ana 2-0, an unrated one, then a 1-1 draw.
insert into public.matches (id, match_type, mode, rated, recorded_by, played_at)
overriding system value values
  (101, 'swu', 'premier', true, '00000000-0000-0000-0000-000000000022', '2026-10-07 11:00Z'),
  (102, 'swu', 'premier', true, '00000000-0000-0000-0000-000000000021', '2026-10-07 10:00Z'),
  (103, 'swu', 'premier', false, '00000000-0000-0000-0000-000000000021', '2026-10-07 12:00Z'),
  (104, 'swu', 'premier', true, '00000000-0000-0000-0000-000000000021', '2026-10-07 13:00Z'),
  -- Twin Suns, scored by players outlasted: Ana won, Bo second, Cy and Di
  -- out together.
  (105, 'swu', 'twin_suns', true, '00000000-0000-0000-0000-000000000021', '2026-10-07 14:00Z'),
  (106, 'chess', 'standard', true, '00000000-0000-0000-0000-000000000021', '2026-10-07 09:00Z');

insert into public.match_players (match_id, player_id, side, score, rating_before, rating_delta) values
  (101, '00000000-0000-0000-0000-000000000022', 1, 2, 980, 21),
  (101, '00000000-0000-0000-0000-000000000021', 2, 0, 1020, -21),
  (102, '00000000-0000-0000-0000-000000000021', 1, 2, 1000, 20),
  (102, '00000000-0000-0000-0000-000000000022', 2, 1, 1000, -20),
  (103, '00000000-0000-0000-0000-000000000021', 1, 2, 999, 0),
  (103, '00000000-0000-0000-0000-000000000022', 2, 0, 1001, 0),
  (104, '00000000-0000-0000-0000-000000000021', 1, 1, 999, 2),
  (104, '00000000-0000-0000-0000-000000000022', 2, 1, 1001, -2),
  (105, '00000000-0000-0000-0000-000000000021', 1, 3, 1000, 20),
  (105, '00000000-0000-0000-0000-000000000022', 2, 2, 1000, 7),
  (105, '00000000-0000-0000-0000-000000000023', 3, 0, 1000, -13),
  (105, '00000000-0000-0000-0000-000000000024', 4, 0, 1000, -13),
  (106, '00000000-0000-0000-0000-000000000021', 1, 1, 1000, 20),
  (106, '00000000-0000-0000-0000-000000000022', 2, 0, 1000, -20);

-- Open reports: a Premier one, a Twin Suns for three that still fits, and a
-- Twin Suns for two that no longer does.
insert into public.match_requests (id, match_type, mode, requested_by, created_at)
overriding system value values
  (201, 'swu', 'premier', '00000000-0000-0000-0000-000000000021', '2026-10-07 15:00Z'),
  (202, 'swu', 'twin_suns', '00000000-0000-0000-0000-000000000021', '2026-10-07 15:00Z'),
  (203, 'swu', 'twin_suns', '00000000-0000-0000-0000-000000000021', '2026-10-07 15:00Z');

insert into public.match_request_players (request_id, player_id, side, score, confirmed) values
  (201, '00000000-0000-0000-0000-000000000021', 1, 2, true),
  (201, '00000000-0000-0000-0000-000000000023', 2, 0, false),
  (202, '00000000-0000-0000-0000-000000000021', 1, 2, true),
  (202, '00000000-0000-0000-0000-000000000022', 2, 1, false),
  (202, '00000000-0000-0000-0000-000000000023', 3, 0, false),
  (203, '00000000-0000-0000-0000-000000000021', 1, 1, true),
  (203, '00000000-0000-0000-0000-000000000022', 2, 0, false);

-- Di's account is deleted: her result stays, her standing goes.
delete from auth.users where id = '00000000-0000-0000-0000-000000000024';
