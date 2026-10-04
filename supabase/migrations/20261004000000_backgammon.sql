-- Backgammon ladder (specs/002-backgammon-ladder). Every member gets a
-- backgammon rating next to their chess one, rated with the FIBS formula
-- because it accounts for match length. Matches wait for the opponent's
-- confirmation exactly like chess games.

alter table public.profiles
  add column bg_rating          integer not null default 1500,
  add column bg_peak_rating     integer not null default 1500,
  add column bg_matches_played  integer not null default 0 check (bg_matches_played >= 0),
  add column bg_wins            integer not null default 0 check (bg_wins >= 0),
  add column bg_losses          integer not null default 0 check (bg_losses >= 0),
  -- FIBS experience: the summed lengths of every match played.
  add column bg_experience      integer not null default 0 check (bg_experience >= 0),
  add check (bg_matches_played = bg_wins + bg_losses),
  add check (bg_peak_rating >= bg_rating);

create index profiles_bg_ladder_idx on public.profiles (bg_rating desc, bg_matches_played desc);

-- The winner's score is always the match length, so only the loser's is kept.
create table public.backgammon_match_requests (
  id            bigint generated always as identity primary key,
  winner_id     uuid not null references public.profiles (id) on delete cascade,
  loser_id      uuid not null references public.profiles (id) on delete cascade,
  match_length  smallint not null check (match_length between 1 and 25),
  loser_score   smallint not null check (loser_score >= 0 and loser_score < match_length),
  requested_by  uuid not null references public.profiles (id) on delete cascade,
  created_at    timestamptz not null default now(),
  check (winner_id <> loser_id),
  check (requested_by in (winner_id, loser_id))
);

create index backgammon_match_requests_winner_idx on public.backgammon_match_requests (winner_id);
create index backgammon_match_requests_loser_idx on public.backgammon_match_requests (loser_id);

create table public.backgammon_matches (
  id                    bigint generated always as identity primary key,
  winner_id             uuid not null references public.profiles (id) on delete restrict,
  loser_id              uuid not null references public.profiles (id) on delete restrict,
  match_length          smallint not null check (match_length between 1 and 25),
  loser_score           smallint not null check (loser_score >= 0 and loser_score < match_length),
  winner_rating_before  integer not null,
  loser_rating_before   integer not null,
  winner_rating_delta   integer not null,
  loser_rating_delta    integer not null,
  recorded_by           uuid not null references public.profiles (id) on delete restrict,
  played_at             timestamptz not null default now(),
  check (winner_id <> loser_id)
);

create index backgammon_matches_played_at_idx on public.backgammon_matches (played_at desc);
create index backgammon_matches_winner_idx on public.backgammon_matches (winner_id, played_at desc);
create index backgammon_matches_loser_idx on public.backgammon_matches (loser_id, played_at desc);

-- Points a player gains from a match to match_length points (FIBS):
-- 4·√N·K·(score − P(win)) with P(win) = 1 / (1 + 10^((opponent − rating)·√N / 2000))
-- and K = max(1, 5 − experience / 100), so newcomers move faster. Rounds half
-- up. Doubles throughout so app/lib/domain/backgammon.dart matches exactly.
create or replace function public.fibs_rating_change(
  rating integer,
  experience integer,
  opponent_rating integer,
  match_length integer,
  won boolean
) returns integer
language sql
immutable
strict
set search_path = ''
as $$
  select floor(
    4 * sqrt(match_length::double precision)
      * greatest(1, 5 - experience / 100::double precision)
      * ((case when won then 1 else 0 end) - 1 / (1 + power(
          10::double precision,
          (opponent_rating - rating) * sqrt(match_length::double precision) / 2000
        )))
    + 0.5
  )::integer;
$$;

-- The caller reports a match they played; it waits for the opponent.
create or replace function public.request_backgammon_match(
  p_opponent_id uuid,
  p_match_length smallint,
  p_my_score smallint,
  p_opponent_score smallint
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
  if not exists (select 1 from public.profiles where id = p_opponent_id) then
    raise exception 'Opponent not found' using errcode = 'P0002';
  end if;

  insert into public.backgammon_match_requests (
    winner_id, loser_id, match_length, loser_score, requested_by
  ) values (
    case when p_my_score = p_match_length then me else p_opponent_id end,
    case when p_my_score = p_match_length then p_opponent_id else me end,
    p_match_length,
    least(p_my_score, p_opponent_score),
    me
  ) returning * into inserted;

  return inserted;
end;
$$;

-- The opponent accepts (rates the match, returns it) or either player drops
-- the request (returns null). Ratings use the values at acceptance.
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
  winner_delta integer;
  loser_delta integer;
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

  insert into public.backgammon_matches (
    winner_id, loser_id, match_length, loser_score, winner_rating_before,
    loser_rating_before, winner_rating_delta, loser_rating_delta, recorded_by
  ) values (
    req.winner_id, req.loser_id, req.match_length, req.loser_score, winner.bg_rating,
    loser.bg_rating, winner_delta, loser_delta, req.requested_by
  ) returning * into inserted;

  return inserted;
end;
$$;

alter table public.backgammon_match_requests enable row level security;
alter table public.backgammon_matches enable row level security;

create policy "Players can read their pending matches"
  on public.backgammon_match_requests for select
  to authenticated
  using (auth.uid() in (winner_id, loser_id));

create policy "Members can read backgammon matches"
  on public.backgammon_matches for select
  to authenticated
  using (true);

revoke all on public.backgammon_match_requests from anon, authenticated;
revoke all on public.backgammon_matches from anon, authenticated;
grant select on public.backgammon_match_requests to authenticated;
grant select on public.backgammon_matches to authenticated;

revoke execute on function public.request_backgammon_match(uuid, smallint, smallint, smallint) from public, anon;
grant execute on function public.request_backgammon_match(uuid, smallint, smallint, smallint) to authenticated;
revoke execute on function public.respond_to_backgammon_match(bigint, boolean) from public, anon;
grant execute on function public.respond_to_backgammon_match(bigint, boolean) to authenticated;
