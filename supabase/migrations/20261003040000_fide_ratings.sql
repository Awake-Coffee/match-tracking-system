-- Ratings follow the FIDE Rating Regulations (2024): the FIDE expected-score
-- table with the 400-point rule, and each player's own K-factor. Players can
-- have different K-factors, so a game is no longer zero-sum and each side's
-- change is stored separately. Games rated before this keep their deltas.

alter table public.matches rename column rating_delta to white_rating_delta;
alter table public.matches add column black_rating_delta integer;
update public.matches set black_rating_delta = -white_rating_delta;
alter table public.matches alter column black_rating_delta set not null;

-- FIDE keeps K = 10 for good once a player reaches 2400, so the peak is kept.
alter table public.profiles add column peak_rating integer not null default 1000;
update public.profiles p set peak_rating = greatest(p.rating, 1000, (
  select max(case when m.white_id = p.id
    then m.white_rating_before + m.white_rating_delta
    else m.black_rating_before + m.black_rating_delta end)
  from public.matches m where p.id in (m.white_id, m.black_id)
));
alter table public.profiles add check (peak_rating >= rating);

drop function public.elo_delta(integer, integer, numeric, integer);

-- FIDE 8.3.3. Skipped: K = 40 for juniors (no birth dates here).
create or replace function public.fide_k_factor(
  games_played integer,
  peak_rating integer
) returns integer
language sql
immutable
strict
set search_path = ''
as $$
  select case
    when games_played < 30 then 40
    when peak_rating < 2400 then 20
    else 10
  end;
$$;

-- Points a player gains. score is 1 (win), 0.5 (draw) or 0 (loss).
-- Mirrored exactly by app/lib/domain/elo.dart.
create or replace function public.fide_rating_change(
  rating integer,
  games_played integer,
  peak_rating integer,
  opponent_rating integer,
  score numeric
) returns integer
language sql
immutable
strict
set search_path = ''
as $$
  -- FIDE 8.1.2 table: one hundredth of expected score per band boundary the
  -- rating difference (capped at 400) passes. Changes round half up.
  with expected as (
    select 0.50 + sign(rating - opponent_rating) * 0.01 * (
      select count(*) from unnest(array[
        3, 10, 17, 25, 32, 39, 46, 53, 61, 68, 76, 83, 91, 98, 106, 113, 121,
        129, 137, 145, 153, 162, 170, 179, 188, 197, 206, 215, 225, 235, 245,
        256, 267, 278, 290, 302, 315, 328, 344, 357, 374, 391
      ]) as band_upper_bound
      where band_upper_bound < least(abs(rating - opponent_rating), 400)
    ) as expected_score
  )
  select floor(
    public.fide_k_factor(games_played, peak_rating) * (score - expected_score) + 0.5
  )::integer
  from expected;
$$;

-- Same as before, but each player's change is computed with their own
-- K-factor, and peaks are tracked.
create or replace function public.respond_to_chess_match(
  p_request_id bigint,
  p_accept boolean
) returns public.matches
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  req public.match_requests;
  white public.profiles;
  black public.profiles;
  white_score numeric;
  white_delta integer;
  black_delta integer;
  inserted public.matches;
begin
  if me is null then
    raise exception 'Sign in to confirm a game' using errcode = '28000';
  end if;

  select * into req from public.match_requests
    where id = p_request_id and me in (white_id, black_id)
    for update;
  if req.id is null then
    raise exception 'That game is no longer waiting for confirmation' using errcode = 'P0002';
  end if;

  delete from public.match_requests where id = req.id;
  if not p_accept then
    return null;
  end if;
  if req.requested_by = me then
    raise exception 'Your opponent has to confirm this game' using errcode = '42501';
  end if;

  -- Lock both rows in id order so concurrent confirmations can't deadlock or
  -- lose an update.
  perform 1 from public.profiles
    where id in (req.white_id, req.black_id)
    order by id
    for update;

  select * into white from public.profiles where id = req.white_id;
  select * into black from public.profiles where id = req.black_id;

  white_score := case req.result when 'white' then 1 when 'black' then 0 else 0.5 end;
  white_delta := public.fide_rating_change(
    white.rating, white.games_played, white.peak_rating, black.rating, white_score);
  black_delta := public.fide_rating_change(
    black.rating, black.games_played, black.peak_rating, white.rating, 1 - white_score);

  update public.profiles set
    rating = rating + white_delta,
    peak_rating = greatest(peak_rating, rating + white_delta),
    games_played = games_played + 1,
    wins = wins + (req.result = 'white')::integer,
    losses = losses + (req.result = 'black')::integer,
    draws = draws + (req.result = 'draw')::integer
  where id = req.white_id;

  update public.profiles set
    rating = rating + black_delta,
    peak_rating = greatest(peak_rating, rating + black_delta),
    games_played = games_played + 1,
    wins = wins + (req.result = 'black')::integer,
    losses = losses + (req.result = 'white')::integer,
    draws = draws + (req.result = 'draw')::integer
  where id = req.black_id;

  insert into public.matches (
    white_id, black_id, result, white_rating_before, black_rating_before,
    white_rating_delta, black_rating_delta, recorded_by, dgt_option,
    custom_base_minutes, custom_extra_seconds
  ) values (
    req.white_id, req.black_id, req.result, white.rating, black.rating,
    white_delta, black_delta, req.requested_by, req.dgt_option,
    req.custom_base_minutes, req.custom_extra_seconds
  ) returning * into inserted;

  return inserted;
end;
$$;
