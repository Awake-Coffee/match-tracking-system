-- Declining tells the reporter. A declined result stays in match_requests
-- with status = 'declined' until the reporter dismisses it, so their
-- "Waiting for ..." card turns into "... declined your game" instead of
-- vanishing. Withdrawing your own report still deletes the row, and only
-- pending requests can be confirmed, declined or withdrawn. Every game shares
-- the table, so this covers chess, backgammon and SWU alike.

alter table public.match_requests
  add column status text not null default 'pending'
    check (status in ('pending', 'declined')),
  add column responded_at timestamptz;

-- Whoever declined has no use for the row any more: only the reporter reads a
-- declined request, while both players still read a pending one.
drop policy "Players can read their pending results" on public.match_requests;
create policy "Players can read their open results"
  on public.match_requests for select
  to authenticated
  using (auth.uid() in (player1_id, player2_id) and (status = 'pending' or requested_by = auth.uid()));

-- Same as before, except that the respondent declining marks the request
-- declined (the reporter withdrawing still deletes it) and only pending
-- requests can be answered.
create or replace function public.respond_to_match(
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
  player1 public.ratings;
  player2 public.ratings;
  player1_delta integer := 0;
  player2_delta integer := 0;
  inserted public.matches;
begin
  if me is null then
    raise exception 'Sign in to confirm a result' using errcode = '28000';
  end if;

  select * into req from public.match_requests
    where id = p_request_id and me in (player1_id, player2_id) and status = 'pending'
    for update;
  if req.id is null then
    raise exception 'That result is no longer waiting for confirmation' using errcode = 'P0002';
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
    raise exception 'Your opponent has to confirm this result' using errcode = '42501';
  end if;

  -- Lock both ratings in player order so concurrent confirmations can't
  -- deadlock or lose an update.
  perform 1 from public.ratings
    where match_type = req.match_type and player_id in (req.player1_id, req.player2_id)
    order by player_id
    for update;

  select * into player1 from public.ratings
    where match_type = req.match_type and player_id = req.player1_id;
  select * into player2 from public.ratings
    where match_type = req.match_type and player_id = req.player2_id;

  if req.rated then
    player1_delta := public.rating_change(player1, player2, req.player1_score, req.player2_score);
    player2_delta := public.rating_change(player2, player1, req.player2_score, req.player1_score);

    update public.ratings r set
      rating = r.rating + s.delta,
      peak_rating = greatest(r.peak_rating, r.rating + s.delta),
      played = r.played + 1,
      wins = r.wins + (s.score > s.opponent_score)::integer,
      losses = r.losses + (s.score < s.opponent_score)::integer,
      draws = r.draws + (s.score = s.opponent_score)::integer,
      experience = r.experience + case r.match_type
        when 'backgammon' then greatest(s.score, s.opponent_score)::integer else 0 end
    from (values
      (req.player1_id, player1_delta, req.player1_score, req.player2_score),
      (req.player2_id, player2_delta, req.player2_score, req.player1_score)
    ) as s (player_id, delta, score, opponent_score)
    where r.match_type = req.match_type and r.player_id = s.player_id;
  end if;

  insert into public.matches (
    match_type, player1_id, player2_id, player1_score, player2_score, rated,
    player1_rating_before, player2_rating_before, player1_rating_delta, player2_rating_delta,
    dgt_option, custom_base_minutes, custom_extra_seconds, recorded_by
  ) values (
    req.match_type, req.player1_id, req.player2_id, req.player1_score, req.player2_score, req.rated,
    player1.rating, player2.rating, player1_delta, player2_delta,
    req.dgt_option, req.custom_base_minutes, req.custom_extra_seconds, req.requested_by
  ) returning * into inserted;

  return inserted;
end;
$$;

-- The reporter clears a declined result from their Ladder tab. Only the
-- reporter can, and only once it is declined; a pending one is withdrawn
-- through respond_to_match instead.
create function public.dismiss_declined_match(p_request_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in to dismiss a result' using errcode = '28000';
  end if;
  delete from public.match_requests
    where id = p_request_id and requested_by = auth.uid() and status = 'declined';
  if not found then
    raise exception 'That result is not waiting to be dismissed' using errcode = 'P0002';
  end if;
end;
$$;

revoke execute on function public.dismiss_declined_match(bigint) from public, anon;
grant execute on function public.dismiss_declined_match(bigint) to authenticated;
