-- Star Wars: Unlimited ladder (specs/003-star-wars-unlimited). Every member
-- gets an SWU rating next to chess and backgammon. A result is a
-- best-of-three match, rated with the chess FIDE rules on the match result.
-- Matches wait for the opponent's confirmation like the other games.

alter table public.profiles
  add column swu_rating          integer not null default 1000,
  add column swu_peak_rating     integer not null default 1000,
  add column swu_matches_played  integer not null default 0 check (swu_matches_played >= 0),
  add column swu_wins            integer not null default 0 check (swu_wins >= 0),
  add column swu_losses          integer not null default 0 check (swu_losses >= 0),
  add column swu_draws           integer not null default 0 check (swu_draws >= 0),
  add check (swu_matches_played = swu_wins + swu_losses + swu_draws),
  add check (swu_peak_rating >= swu_rating);

create index profiles_swu_ladder_idx on public.profiles (swu_rating desc, swu_matches_played desc);

-- Games won in a best of three: 2-0, 2-1, 1-0 when time runs out, 1-1 draw.
create function public.is_swu_score(games_a integer, games_b integer) returns boolean
language sql
immutable
set search_path = ''
as $$
  select coalesce(games_a between 0 and 2 and games_b between 0 and 2
    and games_a + games_b between 1 and 3, false);
$$;

-- The reporter is whoever recorded it; the respondent confirms it.
create table public.swu_match_requests (
  id                bigint generated always as identity primary key,
  reporter_id       uuid not null references public.profiles (id) on delete cascade,
  respondent_id     uuid not null references public.profiles (id) on delete cascade,
  reporter_games    smallint not null,
  respondent_games  smallint not null,
  created_at        timestamptz not null default now(),
  check (reporter_id <> respondent_id),
  check (public.is_swu_score(reporter_games, respondent_games))
);

create index swu_match_requests_reporter_idx on public.swu_match_requests (reporter_id);
create index swu_match_requests_respondent_idx on public.swu_match_requests (respondent_id);

create table public.swu_matches (
  id                          bigint generated always as identity primary key,
  reporter_id                 uuid not null references public.profiles (id) on delete restrict,
  respondent_id               uuid not null references public.profiles (id) on delete restrict,
  reporter_games              smallint not null,
  respondent_games            smallint not null,
  reporter_rating_before      integer not null,
  respondent_rating_before    integer not null,
  reporter_rating_delta       integer not null,
  respondent_rating_delta     integer not null,
  played_at                   timestamptz not null default now(),
  check (reporter_id <> respondent_id),
  check (public.is_swu_score(reporter_games, respondent_games))
);

create index swu_matches_played_at_idx on public.swu_matches (played_at desc);
create index swu_matches_reporter_idx on public.swu_matches (reporter_id, played_at desc);
create index swu_matches_respondent_idx on public.swu_matches (respondent_id, played_at desc);

-- The caller reports a match they played; it waits for the opponent.
create function public.request_swu_match(
  p_opponent_id uuid,
  p_my_games smallint,
  p_opponent_games smallint
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
  if not exists (select 1 from public.profiles where id = p_opponent_id) then
    raise exception 'Opponent not found' using errcode = 'P0002';
  end if;

  insert into public.swu_match_requests (reporter_id, respondent_id, reporter_games, respondent_games)
  values (me, p_opponent_id, p_my_games, p_opponent_games)
  returning * into inserted;

  return inserted;
end;
$$;

-- The respondent accepts (rates the match, returns it) or either player
-- drops the request (returns null). Ratings use the values at acceptance.
create function public.respond_to_swu_match(
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
  reporter_delta integer;
  respondent_delta integer;
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

  insert into public.swu_matches (
    reporter_id, respondent_id, reporter_games, respondent_games,
    reporter_rating_before, respondent_rating_before,
    reporter_rating_delta, respondent_rating_delta
  ) values (
    req.reporter_id, req.respondent_id, req.reporter_games, req.respondent_games,
    reporter.swu_rating, respondent.swu_rating, reporter_delta, respondent_delta
  ) returning * into inserted;

  return inserted;
end;
$$;

alter table public.swu_match_requests enable row level security;
alter table public.swu_matches enable row level security;

create policy "Players can read their pending matches"
  on public.swu_match_requests for select
  to authenticated
  using (auth.uid() in (reporter_id, respondent_id));

create policy "Members can read SWU matches"
  on public.swu_matches for select
  to authenticated
  using (true);

revoke all on public.swu_match_requests from anon, authenticated;
revoke all on public.swu_matches from anon, authenticated;
grant select on public.swu_match_requests to authenticated;
grant select on public.swu_matches to authenticated;

revoke execute on function public.request_swu_match(uuid, smallint, smallint) from public, anon;
grant execute on function public.request_swu_match(uuid, smallint, smallint) to authenticated;
revoke execute on function public.respond_to_swu_match(bigint, boolean) from public, anon;
grant execute on function public.respond_to_swu_match(bigint, boolean) to authenticated;
