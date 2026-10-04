-- Declining tells the reporter. A declined result stays in its request table
-- with status = 'declined' until the reporter dismisses it, so their
-- "Waiting for ..." card turns into "... declined your game" instead of
-- vanishing. Withdrawing your own report still deletes the row, and only
-- pending requests can be confirmed, declined or withdrawn.

alter table public.match_requests
  add column status text not null default 'pending'
    check (status in ('pending', 'declined')),
  add column responded_at timestamptz;
alter table public.backgammon_match_requests
  add column status text not null default 'pending'
    check (status in ('pending', 'declined')),
  add column responded_at timestamptz;
alter table public.swu_match_requests
  add column status text not null default 'pending'
    check (status in ('pending', 'declined')),
  add column responded_at timestamptz;

-- Whoever declined has no use for the row any more: only the reporter reads a
-- declined request, while both players still read a pending one.
drop policy "Players can read their pending games" on public.match_requests;
create policy "Players can read their open games"
  on public.match_requests for select
  to authenticated
  using (auth.uid() in (white_id, black_id) and (status = 'pending' or requested_by = auth.uid()));

drop policy "Players can read their pending matches" on public.backgammon_match_requests;
create policy "Players can read their open matches"
  on public.backgammon_match_requests for select
  to authenticated
  using (auth.uid() in (winner_id, loser_id) and (status = 'pending' or requested_by = auth.uid()));

drop policy "Players can read their pending matches" on public.swu_match_requests;
create policy "Players can read their open matches"
  on public.swu_match_requests for select
  to authenticated
  using (auth.uid() in (reporter_id, respondent_id) and (status = 'pending' or reporter_id = auth.uid()));

-- Same as before, except that the respondent declining marks the request
-- declined (the reporter withdrawing still deletes it) and only pending
-- requests can be answered.
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
    where id = p_request_id and me in (white_id, black_id) and status = 'pending'
    for update;
  if req.id is null then
    raise exception 'That game is no longer waiting for confirmation' using errcode = 'P0002';
  end if;

  if not p_accept then
    if req.requested_by = me then
      delete from public.match_requests where id = req.id;
    else
      update public.match_requests
        set status = 'declined', responded_at = now()
        where id = req.id;
    end if;
    return null;
  end if;
  delete from public.match_requests where id = req.id;
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
    where id = p_request_id and me in (winner_id, loser_id) and status = 'pending'
    for update;
  if req.id is null then
    raise exception 'That match is no longer waiting for confirmation' using errcode = 'P0002';
  end if;

  if not p_accept then
    if req.requested_by = me then
      delete from public.backgammon_match_requests where id = req.id;
    else
      update public.backgammon_match_requests
        set status = 'declined', responded_at = now()
        where id = req.id;
    end if;
    return null;
  end if;
  delete from public.backgammon_match_requests where id = req.id;
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
    where id = p_request_id and me in (reporter_id, respondent_id) and status = 'pending'
    for update;
  if req.id is null then
    raise exception 'That match is no longer waiting for confirmation' using errcode = 'P0002';
  end if;

  if not p_accept then
    if req.reporter_id = me then
      delete from public.swu_match_requests where id = req.id;
    else
      update public.swu_match_requests
        set status = 'declined', responded_at = now()
        where id = req.id;
    end if;
    return null;
  end if;
  delete from public.swu_match_requests where id = req.id;
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

-- The reporter clears a declined result from their Ladder tab. Only the
-- reporter can, and only once it is declined; a pending one is withdrawn
-- through respond_to_*_match instead.
create function public.dismiss_declined_chess_match(p_request_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in to dismiss a game' using errcode = '28000';
  end if;
  delete from public.match_requests
    where id = p_request_id and requested_by = auth.uid() and status = 'declined';
  if not found then
    raise exception 'That game is not waiting to be dismissed' using errcode = 'P0002';
  end if;
end;
$$;

create function public.dismiss_declined_backgammon_match(p_request_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in to dismiss a match' using errcode = '28000';
  end if;
  delete from public.backgammon_match_requests
    where id = p_request_id and requested_by = auth.uid() and status = 'declined';
  if not found then
    raise exception 'That match is not waiting to be dismissed' using errcode = 'P0002';
  end if;
end;
$$;

create function public.dismiss_declined_swu_match(p_request_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in to dismiss a match' using errcode = '28000';
  end if;
  delete from public.swu_match_requests
    where id = p_request_id and reporter_id = auth.uid() and status = 'declined';
  if not found then
    raise exception 'That match is not waiting to be dismissed' using errcode = 'P0002';
  end if;
end;
$$;

revoke execute on function public.dismiss_declined_chess_match(bigint) from public, anon;
grant execute on function public.dismiss_declined_chess_match(bigint) to authenticated;
revoke execute on function public.dismiss_declined_backgammon_match(bigint) from public, anon;
grant execute on function public.dismiss_declined_backgammon_match(bigint) to authenticated;
revoke execute on function public.dismiss_declined_swu_match(bigint) from public, anon;
grant execute on function public.dismiss_declined_swu_match(bigint) to authenticated;
