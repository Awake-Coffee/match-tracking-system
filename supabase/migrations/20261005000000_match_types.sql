-- One schema for every game (specs/005-match-types). Each game used to have
-- its own rating columns on profiles, its own request and result tables and
-- its own pair of RPCs, all nearly identical. Now a match_type tells the
-- games apart in one ratings table, one match_requests table, one matches
-- table and one pair of RPCs. Each game keeps its own score rules and rating
-- math. Existing ratings, results and pending requests carry over as is.

create type public.match_type as enum ('chess', 'backgammon', 'swu');

-- Rating every member starts with in each game. Mirrored by the
-- startingRating constants in app/lib/domain.
create function public.starting_rating(match_type public.match_type)
returns integer
language sql
immutable
strict
set search_path = ''
as $$
  select case match_type when 'backgammon' then 1500 else 1000 end;
$$;

-- Whether a result can end a game of this type. Scores are from either
-- side; a draw is an equal score.
--   chess:      1-0, 0-1 or ½-½.
--   backgammon: the winner's score is the match length (1 to 25), the
--               loser's is below it.
--   swu:        games won in a best of three: 2-0, 2-1, 1-0, 1-1.
create function public.is_valid_score(
  match_type public.match_type,
  score_a numeric,
  score_b numeric
) returns boolean
language sql
immutable
set search_path = ''
as $$
  select coalesce(case match_type
    when 'chess' then
      (score_a, score_b) in ((1, 0), (0, 1), (0.5, 0.5))
    when 'backgammon' then
      score_a = trunc(score_a) and score_b = trunc(score_b)
      and greatest(score_a, score_b) between 1 and 25
      and least(score_a, score_b) >= 0
      and score_a <> score_b
    when 'swu' then
      score_a = trunc(score_a) and score_b = trunc(score_b)
      and score_a between 0 and 2 and score_b between 0 and 2
      and score_a + score_b between 1 and 3
  end, false);
$$;

-- ---------------------------------------------------------------------------
-- Ratings
-- ---------------------------------------------------------------------------

create table public.ratings (
  player_id    uuid not null references public.profiles (id) on delete cascade,
  match_type   public.match_type not null,
  rating       integer not null,
  peak_rating  integer not null,
  played       integer not null default 0 check (played >= 0),
  wins         integer not null default 0 check (wins >= 0),
  losses       integer not null default 0 check (losses >= 0),
  draws        integer not null default 0 check (draws >= 0),
  -- FIBS experience (backgammon only): the summed lengths of every match.
  experience   integer not null default 0 check (experience >= 0),
  primary key (player_id, match_type),
  check (played = wins + losses + draws),
  check (peak_rating >= rating),
  check (match_type = 'backgammon' or experience = 0)
);

create index ratings_ladder_idx on public.ratings (match_type, rating desc, played desc);

insert into public.ratings (
  player_id, match_type, rating, peak_rating, played, wins, losses, draws, experience
)
select id, 'chess'::public.match_type, rating, peak_rating, games_played, wins, losses, draws, 0
  from public.profiles
union all
select id, 'backgammon', bg_rating, bg_peak_rating, bg_matches_played, bg_wins, bg_losses, 0,
       bg_experience
  from public.profiles
union all
select id, 'swu', swu_rating, swu_peak_rating, swu_matches_played, swu_wins, swu_losses,
       swu_draws, 0
  from public.profiles;

alter table public.profiles
  drop column rating,
  drop column peak_rating,
  drop column games_played,
  drop column wins,
  drop column losses,
  drop column draws,
  drop column bg_rating,
  drop column bg_peak_rating,
  drop column bg_matches_played,
  drop column bg_wins,
  drop column bg_losses,
  drop column bg_experience,
  drop column swu_rating,
  drop column swu_peak_rating,
  drop column swu_matches_played,
  drop column swu_wins,
  drop column swu_losses,
  drop column swu_draws;

-- Every member gets a starting rating in every game.
create function public.create_ratings()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.ratings (player_id, match_type, rating, peak_rating)
  select new.id, t, public.starting_rating(t), public.starting_rating(t)
    from unnest(enum_range(null::public.match_type)) as t;
  return new;
end;
$$;

create trigger profiles_create_ratings
  after insert on public.profiles
  for each row execute function public.create_ratings();

revoke execute on function public.create_ratings() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Requests and results
-- ---------------------------------------------------------------------------

-- The per-game functions return the old tables, so they go first.
drop function public.request_chess_match(uuid, text, text, smallint, smallint, smallint, boolean);
drop function public.respond_to_chess_match(bigint, boolean);
drop function public.request_backgammon_match(uuid, smallint, smallint, smallint, boolean);
drop function public.respond_to_backgammon_match(bigint, boolean);
drop function public.request_swu_match(uuid, smallint, smallint, boolean);
drop function public.respond_to_swu_match(bigint, boolean);

-- The new tables reuse the chess tables' names, so the old rows wait in
-- temporary tables while the old tables are replaced.
create temporary table old_chess_requests as table public.match_requests;
create temporary table old_chess_matches as table public.matches;
create temporary table old_backgammon_requests as table public.backgammon_match_requests;
create temporary table old_backgammon_matches as table public.backgammon_matches;
create temporary table old_swu_requests as table public.swu_match_requests;
create temporary table old_swu_matches as table public.swu_matches;

drop table public.match_requests;
drop table public.matches;
drop table public.backgammon_match_requests;
drop table public.backgammon_matches;
drop table public.swu_match_requests;
drop table public.swu_matches;
drop function public.is_swu_score(integer, integer);

-- Chess: player1 has white. Other games: player1 reported the result.
-- The DGT 2500 preset and custom time are chess only.
create table public.match_requests (
  id                    bigint generated always as identity primary key,
  match_type            public.match_type not null,
  player1_id            uuid not null references public.profiles (id) on delete cascade,
  player2_id            uuid not null references public.profiles (id) on delete cascade,
  player1_score         numeric(3, 1) not null,
  player2_score         numeric(3, 1) not null,
  rated                 boolean not null default true,
  dgt_option            smallint check (dgt_option between 1 and 36),
  custom_base_minutes   smallint check (custom_base_minutes between 1 and 600),
  custom_extra_seconds  smallint check (custom_extra_seconds between 0 and 3600),
  requested_by          uuid not null references public.profiles (id) on delete cascade,
  created_at            timestamptz not null default now(),
  check (player1_id <> player2_id),
  check (public.is_valid_score(match_type, player1_score, player2_score)),
  check ((match_type = 'chess') = (dgt_option is not null)),
  check (public.clock_setting_valid(dgt_option, custom_base_minutes, custom_extra_seconds)),
  check (requested_by = player1_id or (match_type = 'chess' and requested_by = player2_id))
);

create index match_requests_player1_idx on public.match_requests (player1_id);
create index match_requests_player2_idx on public.match_requests (player2_id);

-- Same sides as match_requests. Chess games recorded before time controls
-- were tracked have no DGT preset.
create table public.matches (
  id                     bigint generated always as identity primary key,
  match_type             public.match_type not null,
  player1_id             uuid not null references public.profiles (id) on delete restrict,
  player2_id             uuid not null references public.profiles (id) on delete restrict,
  player1_score          numeric(3, 1) not null,
  player2_score          numeric(3, 1) not null,
  rated                  boolean not null default true,
  player1_rating_before  integer not null,
  player2_rating_before  integer not null,
  player1_rating_delta   integer not null,
  player2_rating_delta   integer not null,
  dgt_option             smallint check (dgt_option between 1 and 36),
  custom_base_minutes    smallint check (custom_base_minutes between 1 and 600),
  custom_extra_seconds   smallint check (custom_extra_seconds between 0 and 3600),
  recorded_by            uuid not null references public.profiles (id) on delete restrict,
  played_at              timestamptz not null default now(),
  check (player1_id <> player2_id),
  check (public.is_valid_score(match_type, player1_score, player2_score)),
  check (match_type = 'chess' or dgt_option is null),
  check (public.clock_setting_valid(dgt_option, custom_base_minutes, custom_extra_seconds)),
  check (recorded_by = player1_id or (match_type = 'chess' and recorded_by = player2_id)),
  check (rated or (player1_rating_delta = 0 and player2_rating_delta = 0))
);

create index matches_played_at_idx on public.matches (match_type, played_at desc);
create index matches_player1_idx on public.matches (player1_id, played_at desc);
create index matches_player2_idx on public.matches (player2_id, played_at desc);

-- Carry the old rows over, oldest first so ids stay in order.
insert into public.match_requests (
  match_type, player1_id, player2_id, player1_score, player2_score, rated,
  dgt_option, custom_base_minutes, custom_extra_seconds, requested_by, created_at
)
select * from (
  select 'chess'::public.match_type, white_id, black_id,
         case result when 'white' then 1 when 'black' then 0 else 0.5 end,
         case result when 'black' then 1 when 'white' then 0 else 0.5 end,
         rated, dgt_option, custom_base_minutes, custom_extra_seconds, requested_by, created_at
    from old_chess_requests
  union all
  select 'backgammon', requested_by,
         case requested_by when winner_id then loser_id else winner_id end,
         case requested_by when winner_id then match_length else loser_score end,
         case requested_by when winner_id then loser_score else match_length end,
         rated, null, null, null, requested_by, created_at
    from old_backgammon_requests
  union all
  select 'swu', reporter_id, respondent_id, reporter_games, respondent_games,
         rated, null, null, null, reporter_id, created_at
    from old_swu_requests
) as old
order by created_at;

insert into public.matches (
  match_type, player1_id, player2_id, player1_score, player2_score, rated,
  player1_rating_before, player2_rating_before, player1_rating_delta, player2_rating_delta,
  dgt_option, custom_base_minutes, custom_extra_seconds, recorded_by, played_at
)
select * from (
  select 'chess'::public.match_type, white_id, black_id,
         case result when 'white' then 1 when 'black' then 0 else 0.5 end,
         case result when 'black' then 1 when 'white' then 0 else 0.5 end,
         rated, white_rating_before, black_rating_before, white_rating_delta, black_rating_delta,
         dgt_option, custom_base_minutes, custom_extra_seconds, recorded_by, played_at
    from old_chess_matches
  union all
  select 'backgammon', recorded_by,
         case recorded_by when winner_id then loser_id else winner_id end,
         case recorded_by when winner_id then match_length else loser_score end,
         case recorded_by when winner_id then loser_score else match_length end,
         rated,
         case recorded_by when winner_id then winner_rating_before else loser_rating_before end,
         case recorded_by when winner_id then loser_rating_before else winner_rating_before end,
         case recorded_by when winner_id then winner_rating_delta else loser_rating_delta end,
         case recorded_by when winner_id then loser_rating_delta else winner_rating_delta end,
         null, null, null, recorded_by, played_at
    from old_backgammon_matches
  union all
  select 'swu', reporter_id, respondent_id, reporter_games, respondent_games, rated,
         reporter_rating_before, respondent_rating_before,
         reporter_rating_delta, respondent_rating_delta,
         null, null, null, reporter_id, played_at
    from old_swu_matches
) as old
order by played_at;

drop table old_chess_requests;
drop table old_chess_matches;
drop table old_backgammon_requests;
drop table old_backgammon_matches;
drop table old_swu_requests;
drop table old_swu_matches;

-- ---------------------------------------------------------------------------
-- Rating math
-- ---------------------------------------------------------------------------

-- Points a player gains from a result, with their game's rules: FIBS for
-- backgammon (the match length is the winner's score), FIDE on the result
-- for chess and SWU.
create function public.rating_change(
  me public.ratings,
  opponent public.ratings,
  my_score numeric,
  opponent_score numeric
) returns integer
language sql
immutable
strict
set search_path = ''
as $$
  select case me.match_type
    when 'backgammon' then public.fibs_rating_change(
      me.rating, me.experience, opponent.rating,
      greatest(my_score, opponent_score)::integer, my_score > opponent_score)
    else public.fide_rating_change(
      me.rating, me.played, me.peak_rating, opponent.rating,
      case sign(my_score - opponent_score) when 1 then 1 when -1 then 0 else 0.5 end)
  end;
$$;

-- ---------------------------------------------------------------------------
-- Recording a result
-- ---------------------------------------------------------------------------

-- The caller reports a result they played; it waits for the opponent.
-- Scores follow is_valid_score (chess: 1, 0 or 0.5 each). Chess also takes
-- the caller's color ('white' | 'black') and the DGT 2500 preset, plus the
-- custom time for custom presets; other games take neither.
create function public.request_match(
  p_match_type public.match_type,
  p_opponent_id uuid,
  p_my_score numeric,
  p_opponent_score numeric,
  p_rated boolean default true,
  p_my_color text default null,
  p_dgt_option smallint default null,
  p_custom_base_minutes smallint default null,
  p_custom_extra_seconds smallint default null
) returns public.match_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  is_chess boolean := p_match_type = 'chess';
  i_am_player1 boolean := not is_chess or p_my_color = 'white';
  inserted public.match_requests;
begin
  if me is null then
    raise exception 'Sign in to record a result' using errcode = '28000';
  end if;
  if p_match_type is null then
    raise exception 'Pick the game you played' using errcode = '22023';
  end if;
  if p_opponent_id is null or p_opponent_id = me then
    raise exception 'Choose an opponent other than yourself' using errcode = '22023';
  end if;
  if not public.is_valid_score(p_match_type, p_my_score, p_opponent_score) then
    raise exception '%', case p_match_type
      when 'chess' then 'Result must be win, loss or draw'
      when 'backgammon' then 'The winner''s score must equal the match length (1 to 25)'
      when 'swu' then 'A best of three ends 2-0, 2-1, 1-0 or 1-1'
    end using errcode = '22023';
  end if;
  if p_rated is null then
    raise exception 'Say whether the result is rated' using errcode = '22023';
  end if;
  if is_chess then
    if p_my_color is null or p_my_color not in ('white', 'black') then
      raise exception 'Color must be white or black' using errcode = '22023';
    end if;
    if p_dgt_option is null or p_dgt_option not between 1 and 36 then
      raise exception 'Pick the time control you played' using errcode = '22023';
    end if;
    if not public.clock_setting_valid(p_dgt_option, p_custom_base_minutes, p_custom_extra_seconds)
       or p_custom_base_minutes not between 1 and 600
       or p_custom_extra_seconds not between 0 and 3600 then
      raise exception 'Set the custom time you played' using errcode = '22023';
    end if;
  elsif p_my_color is not null or p_dgt_option is not null
        or p_custom_base_minutes is not null or p_custom_extra_seconds is not null then
    raise exception 'Only chess has colors and time controls' using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles where id = p_opponent_id) then
    raise exception 'Opponent not found' using errcode = 'P0002';
  end if;

  insert into public.match_requests (
    match_type, player1_id, player2_id, player1_score, player2_score, rated,
    dgt_option, custom_base_minutes, custom_extra_seconds, requested_by
  ) values (
    p_match_type,
    case when i_am_player1 then me else p_opponent_id end,
    case when i_am_player1 then p_opponent_id else me end,
    case when i_am_player1 then p_my_score else p_opponent_score end,
    case when i_am_player1 then p_opponent_score else p_my_score end,
    p_rated,
    p_dgt_option,
    p_custom_base_minutes,
    p_custom_extra_seconds,
    me
  ) returning * into inserted;

  return inserted;
end;
$$;

-- The opponent accepts (rates the result, returns it) or either player drops
-- the request (returns null). Ratings use the values at acceptance. An
-- unrated result is stored with zero deltas and leaves both ratings alone.
create function public.respond_to_match(
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
    where id = p_request_id and me in (player1_id, player2_id)
    for update;
  if req.id is null then
    raise exception 'That result is no longer waiting for confirmation' using errcode = 'P0002';
  end if;

  delete from public.match_requests where id = req.id;
  if not p_accept then
    return null;
  end if;
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

-- ---------------------------------------------------------------------------
-- Row Level Security & grants
-- ---------------------------------------------------------------------------

alter table public.ratings enable row level security;
alter table public.match_requests enable row level security;
alter table public.matches enable row level security;

create policy "Members can read the ladders"
  on public.ratings for select
  to authenticated
  using (true);

create policy "Players can read their pending results"
  on public.match_requests for select
  to authenticated
  using (auth.uid() in (player1_id, player2_id));

create policy "Members can read results"
  on public.matches for select
  to authenticated
  using (true);

-- No write policies: ratings and results change through respond_to_match,
-- requests through request_match.
revoke all on public.ratings from anon, authenticated;
revoke all on public.match_requests from anon, authenticated;
revoke all on public.matches from anon, authenticated;
grant select on public.ratings to authenticated;
grant select on public.match_requests to authenticated;
grant select on public.matches to authenticated;

revoke execute on function public.request_match(
  public.match_type, uuid, numeric, numeric, boolean, text, smallint, smallint, smallint
) from public, anon;
grant execute on function public.request_match(
  public.match_type, uuid, numeric, numeric, boolean, text, smallint, smallint, smallint
) to authenticated;
revoke execute on function public.respond_to_match(bigint, boolean) from public, anon;
grant execute on function public.respond_to_match(bigint, boolean) to authenticated;
