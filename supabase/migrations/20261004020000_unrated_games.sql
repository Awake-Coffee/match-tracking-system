-- Unrated results (specs/004-unrated-games). A player can report a chess
-- game, backgammon match or SWU match as unrated: it is confirmed like any
-- other result and kept in history, but no rating, peak, record or
-- experience moves, and its stored deltas are zero.

alter table public.matches
  add column rated boolean not null default true,
  add constraint matches_unrated_delta_check
    check (rated or (white_rating_delta = 0 and black_rating_delta = 0));
alter table public.match_requests
  add column rated boolean not null default true;

alter table public.backgammon_matches
  add column rated boolean not null default true,
  add constraint backgammon_matches_unrated_delta_check
    check (rated or (winner_rating_delta = 0 and loser_rating_delta = 0));
alter table public.backgammon_match_requests
  add column rated boolean not null default true;

alter table public.swu_matches
  add column rated boolean not null default true,
  add constraint swu_matches_unrated_delta_check
    check (rated or (reporter_rating_delta = 0 and respondent_rating_delta = 0));
alter table public.swu_match_requests
  add column rated boolean not null default true;

-- Chess --------------------------------------------------------------------

drop function public.request_chess_match(uuid, text, text, smallint, smallint, smallint);

-- Same as before, plus whether the game is rated.
create function public.request_chess_match(
  p_opponent_id uuid,
  p_my_color text,
  p_my_result text,
  p_dgt_option smallint,
  p_custom_base_minutes smallint default null,
  p_custom_extra_seconds smallint default null,
  p_rated boolean default true
) returns public.match_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  inserted public.match_requests;
begin
  if me is null then
    raise exception 'Sign in to record a game' using errcode = '28000';
  end if;
  if p_opponent_id is null or p_opponent_id = me then
    raise exception 'Choose an opponent other than yourself' using errcode = '22023';
  end if;
  if p_my_color not in ('white', 'black') then
    raise exception 'Color must be white or black' using errcode = '22023';
  end if;
  if p_my_result not in ('win', 'loss', 'draw') then
    raise exception 'Result must be win, loss or draw' using errcode = '22023';
  end if;
  if p_dgt_option is null or p_dgt_option not between 1 and 36 then
    raise exception 'Pick the time control you played' using errcode = '22023';
  end if;
  if not public.clock_setting_valid(p_dgt_option, p_custom_base_minutes, p_custom_extra_seconds)
     or p_custom_base_minutes not between 1 and 600
     or p_custom_extra_seconds not between 0 and 3600 then
    raise exception 'Set the custom time you played' using errcode = '22023';
  end if;
  if p_rated is null then
    raise exception 'Say whether the game is rated' using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles where id = p_opponent_id) then
    raise exception 'Opponent not found' using errcode = 'P0002';
  end if;

  insert into public.match_requests (
    white_id, black_id, result, dgt_option, custom_base_minutes,
    custom_extra_seconds, requested_by, rated
  ) values (
    case p_my_color when 'white' then me else p_opponent_id end,
    case p_my_color when 'white' then p_opponent_id else me end,
    case
      when p_my_result = 'draw' then 'draw'
      when p_my_result = 'win' then p_my_color
      else case p_my_color when 'white' then 'black' else 'white' end
    end,
    p_dgt_option,
    p_custom_base_minutes,
    p_custom_extra_seconds,
    me,
    p_rated
  ) returning * into inserted;

  return inserted;
end;
$$;

-- Same as before, but an unrated game is stored with zero deltas and leaves
-- both profiles alone.
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
  white_delta integer := 0;
  black_delta integer := 0;
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

  if req.rated then
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
  end if;

  insert into public.matches (
    white_id, black_id, result, white_rating_before, black_rating_before,
    white_rating_delta, black_rating_delta, recorded_by, dgt_option,
    custom_base_minutes, custom_extra_seconds, rated
  ) values (
    req.white_id, req.black_id, req.result, white.rating, black.rating,
    white_delta, black_delta, req.requested_by, req.dgt_option,
    req.custom_base_minutes, req.custom_extra_seconds, req.rated
  ) returning * into inserted;

  return inserted;
end;
$$;

-- Backgammon ---------------------------------------------------------------

drop function public.request_backgammon_match(uuid, smallint, smallint, smallint);

-- Same as before, plus whether the match is rated.
create function public.request_backgammon_match(
  p_opponent_id uuid,
  p_match_length smallint,
  p_my_score smallint,
  p_opponent_score smallint,
  p_rated boolean default true
) returns public.backgammon_match_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  inserted public.backgammon_match_requests;
begin
  if me is null then
    raise exception 'Sign in to record a match' using errcode = '28000';
  end if;
  if p_opponent_id is null or p_opponent_id = me then
    raise exception 'Choose an opponent other than yourself' using errcode = '22023';
  end if;
  if p_match_length is null or p_match_length not between 1 and 25 then
    raise exception 'Pick the match length' using errcode = '22023';
  end if;
  if p_my_score is null or p_opponent_score is null
     or greatest(p_my_score, p_opponent_score) <> p_match_length
     or least(p_my_score, p_opponent_score) not between 0 and p_match_length - 1 then
    raise exception 'The winner''s score must equal the match length' using errcode = '22023';
  end if;
  if p_rated is null then
    raise exception 'Say whether the match is rated' using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles where id = p_opponent_id) then
    raise exception 'Opponent not found' using errcode = 'P0002';
  end if;

  insert into public.backgammon_match_requests (
    winner_id, loser_id, match_length, loser_score, requested_by, rated
  ) values (
    case when p_my_score = p_match_length then me else p_opponent_id end,
    case when p_my_score = p_match_length then p_opponent_id else me end,
    p_match_length,
    least(p_my_score, p_opponent_score),
    me,
    p_rated
  ) returning * into inserted;

  return inserted;
end;
$$;

-- Same as before, but an unrated match is stored with zero deltas and leaves
-- both profiles (experience included) alone.
create or replace function public.respond_to_backgammon_match(
  p_request_id bigint,
  p_accept boolean
) returns public.backgammon_matches
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  req public.backgammon_match_requests;
  winner public.profiles;
  loser public.profiles;
  winner_delta integer := 0;
  loser_delta integer := 0;
  inserted public.backgammon_matches;
begin
  if me is null then
    raise exception 'Sign in to confirm a match' using errcode = '28000';
  end if;

  select * into req from public.backgammon_match_requests
    where id = p_request_id and me in (winner_id, loser_id)
    for update;
  if req.id is null then
    raise exception 'That match is no longer waiting for confirmation' using errcode = 'P0002';
  end if;

  delete from public.backgammon_match_requests where id = req.id;
  if not p_accept then
    return null;
  end if;
  if req.requested_by = me then
    raise exception 'Your opponent has to confirm this match' using errcode = '42501';
  end if;

  -- Same lock order as chess, so a chess and a backgammon confirmation for
  -- the same players can't deadlock either.
  perform 1 from public.profiles
    where id in (req.winner_id, req.loser_id)
    order by id
    for update;

  select * into winner from public.profiles where id = req.winner_id;
  select * into loser from public.profiles where id = req.loser_id;

  if req.rated then
    winner_delta := public.fibs_rating_change(
      winner.bg_rating, winner.bg_experience, loser.bg_rating, req.match_length, true);
    loser_delta := public.fibs_rating_change(
      loser.bg_rating, loser.bg_experience, winner.bg_rating, req.match_length, false);

    update public.profiles set
      bg_rating = bg_rating + winner_delta,
      bg_peak_rating = greatest(bg_peak_rating, bg_rating + winner_delta),
      bg_matches_played = bg_matches_played + 1,
      bg_wins = bg_wins + 1,
      bg_experience = bg_experience + req.match_length
    where id = req.winner_id;

    update public.profiles set
      bg_rating = bg_rating + loser_delta,
      bg_matches_played = bg_matches_played + 1,
      bg_losses = bg_losses + 1,
      bg_experience = bg_experience + req.match_length
    where id = req.loser_id;
  end if;

  insert into public.backgammon_matches (
    winner_id, loser_id, match_length, loser_score, winner_rating_before,
    loser_rating_before, winner_rating_delta, loser_rating_delta, recorded_by, rated
  ) values (
    req.winner_id, req.loser_id, req.match_length, req.loser_score, winner.bg_rating,
    loser.bg_rating, winner_delta, loser_delta, req.requested_by, req.rated
  ) returning * into inserted;

  return inserted;
end;
$$;

-- Star Wars: Unlimited -----------------------------------------------------

drop function public.request_swu_match(uuid, smallint, smallint);

-- Same as before, plus whether the match is rated.
create function public.request_swu_match(
  p_opponent_id uuid,
  p_my_games smallint,
  p_opponent_games smallint,
  p_rated boolean default true
) returns public.swu_match_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  inserted public.swu_match_requests;
begin
  if me is null then
    raise exception 'Sign in to record a match' using errcode = '28000';
  end if;
  if p_opponent_id is null or p_opponent_id = me then
    raise exception 'Choose an opponent other than yourself' using errcode = '22023';
  end if;
  if not public.is_swu_score(p_my_games, p_opponent_games) then
    raise exception 'A best of three ends 2-0, 2-1, 1-0 or 1-1' using errcode = '22023';
  end if;
  if p_rated is null then
    raise exception 'Say whether the match is rated' using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles where id = p_opponent_id) then
    raise exception 'Opponent not found' using errcode = 'P0002';
  end if;

  insert into public.swu_match_requests (
    reporter_id, respondent_id, reporter_games, respondent_games, rated
  ) values (me, p_opponent_id, p_my_games, p_opponent_games, p_rated)
  returning * into inserted;

  return inserted;
end;
$$;

-- Same as before, but an unrated match is stored with zero deltas and leaves
-- both profiles alone.
create or replace function public.respond_to_swu_match(
  p_request_id bigint,
  p_accept boolean
) returns public.swu_matches
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  req public.swu_match_requests;
  reporter public.profiles;
  respondent public.profiles;
  reporter_score numeric;
  reporter_delta integer := 0;
  respondent_delta integer := 0;
  inserted public.swu_matches;
begin
  if me is null then
    raise exception 'Sign in to confirm a match' using errcode = '28000';
  end if;

  select * into req from public.swu_match_requests
    where id = p_request_id and me in (reporter_id, respondent_id)
    for update;
  if req.id is null then
    raise exception 'That match is no longer waiting for confirmation' using errcode = 'P0002';
  end if;

  delete from public.swu_match_requests where id = req.id;
  if not p_accept then
    return null;
  end if;
  if req.reporter_id = me then
    raise exception 'Your opponent has to confirm this match' using errcode = '42501';
  end if;

  -- Same lock order as the other games, so confirmations across games for
  -- the same players can't deadlock.
  perform 1 from public.profiles
    where id in (req.reporter_id, req.respondent_id)
    order by id
    for update;

  select * into reporter from public.profiles where id = req.reporter_id;
  select * into respondent from public.profiles where id = req.respondent_id;

  if req.rated then
    reporter_score := case sign(req.reporter_games - req.respondent_games)
      when 1 then 1 when -1 then 0 else 0.5 end;
    reporter_delta := public.fide_rating_change(
      reporter.swu_rating, reporter.swu_matches_played, reporter.swu_peak_rating,
      respondent.swu_rating, reporter_score);
    respondent_delta := public.fide_rating_change(
      respondent.swu_rating, respondent.swu_matches_played, respondent.swu_peak_rating,
      reporter.swu_rating, 1 - reporter_score);

    update public.profiles set
      swu_rating = swu_rating + reporter_delta,
      swu_peak_rating = greatest(swu_peak_rating, swu_rating + reporter_delta),
      swu_matches_played = swu_matches_played + 1,
      swu_wins = swu_wins + (reporter_score = 1)::integer,
      swu_losses = swu_losses + (reporter_score = 0)::integer,
      swu_draws = swu_draws + (reporter_score = 0.5)::integer
    where id = req.reporter_id;

    update public.profiles set
      swu_rating = swu_rating + respondent_delta,
      swu_peak_rating = greatest(swu_peak_rating, swu_rating + respondent_delta),
      swu_matches_played = swu_matches_played + 1,
      swu_wins = swu_wins + (reporter_score = 0)::integer,
      swu_losses = swu_losses + (reporter_score = 1)::integer,
      swu_draws = swu_draws + (reporter_score = 0.5)::integer
    where id = req.respondent_id;
  end if;

  insert into public.swu_matches (
    reporter_id, respondent_id, reporter_games, respondent_games,
    reporter_rating_before, respondent_rating_before,
    reporter_rating_delta, respondent_rating_delta, rated
  ) values (
    req.reporter_id, req.respondent_id, req.reporter_games, req.respondent_games,
    reporter.swu_rating, respondent.swu_rating, reporter_delta, respondent_delta, req.rated
  ) returning * into inserted;

  return inserted;
end;
$$;

revoke execute on function public.request_chess_match(uuid, text, text, smallint, smallint, smallint, boolean) from public, anon;
grant execute on function public.request_chess_match(uuid, text, text, smallint, smallint, smallint, boolean) to authenticated;
revoke execute on function public.request_backgammon_match(uuid, smallint, smallint, smallint, boolean) from public, anon;
grant execute on function public.request_backgammon_match(uuid, smallint, smallint, smallint, boolean) to authenticated;
revoke execute on function public.request_swu_match(uuid, smallint, smallint, boolean) from public, anon;
grant execute on function public.request_swu_match(uuid, smallint, smallint, boolean) to authenticated;
