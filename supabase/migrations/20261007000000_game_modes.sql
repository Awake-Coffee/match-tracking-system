-- Game modes (specs/006-game-modes). Each game is played in several modes
-- (Chess960, Bughouse, Nackgammon, Twin Suns, ...), each with its own ladder,
-- and some modes have more than two players. So:
--   * game_modes lists every mode and its format (who plays whom);
--   * ratings are kept per (member, game, mode), created on a member's first
--     result in a mode instead of at sign-up;
--   * the two players of a request or result move to child tables,
--     match_request_players and match_players, one row per player with a
--     side and a score.
-- Existing rows carry over unchanged into each game's original mode.

create table public.game_modes (
  match_type  public.match_type not null,
  mode        text not null check (mode ~ '^[a-z0-9_]+$'),
  -- duel:         two sides of one player.
  -- teams:        two sides of two players (bughouse).
  -- box_vs_team:  side 1 is the box, alone; side 2 is a team of 2 to 5.
  -- free_for_all: 2 to 4 sides of one player; score = players outlasted.
  format      text not null check (format in ('duel', 'teams', 'box_vs_team', 'free_for_all')),
  primary key (match_type, mode)
);

-- Mirrored by GameMode in app/lib/domain/modes.dart.
insert into public.game_modes (match_type, mode, format) values
  ('chess', 'standard', 'duel'),
  ('chess', 'chess960', 'duel'),
  ('chess', 'king_of_the_hill', 'duel'),
  ('chess', 'three_check', 'duel'),
  ('chess', 'crazyhouse', 'duel'),
  ('chess', 'atomic', 'duel'),
  ('chess', 'antichess', 'duel'),
  ('chess', 'horde', 'duel'),
  ('chess', 'racing_kings', 'duel'),
  ('chess', 'bughouse', 'teams'),
  ('backgammon', 'standard', 'duel'),
  ('backgammon', 'nackgammon', 'duel'),
  ('backgammon', 'hypergammon', 'duel'),
  ('backgammon', 'acey_deucey', 'duel'),
  ('backgammon', 'tavli', 'duel'),
  ('backgammon', 'long_nardy', 'duel'),
  ('backgammon', 'chouette', 'box_vs_team'),
  ('swu', 'premier', 'duel'),
  ('swu', 'eternal', 'duel'),
  ('swu', 'trilogy', 'duel'),
  ('swu', 'limited', 'duel'),
  ('swu', 'twin_suns', 'free_for_all');

-- Every result so far was played in its game's original mode.
create function pg_temp.original_mode(match_type public.match_type) returns text
language sql immutable as $$
  select case match_type when 'swu' then 'premier' else 'standard' end;
$$;

-- ---------------------------------------------------------------------------
-- Ratings, per mode
-- ---------------------------------------------------------------------------

alter table public.ratings add column mode text;
update public.ratings set mode = pg_temp.original_mode(match_type);
alter table public.ratings
  alter column mode set not null,
  drop constraint ratings_pkey,
  add primary key (player_id, match_type, mode),
  add foreign key (match_type, mode) references public.game_modes;

drop index public.ratings_ladder_idx;
create index ratings_ladder_idx on public.ratings (match_type, mode, rating desc, played desc);

-- A member's standing in a mode now starts with their first result there;
-- until then the app shows the game's starting rating.
drop trigger profiles_create_ratings on public.profiles;
drop function public.create_ratings();

-- ---------------------------------------------------------------------------
-- Players of a result
-- ---------------------------------------------------------------------------

alter table public.matches add column mode text;
update public.matches set mode = pg_temp.original_mode(match_type);
alter table public.matches
  alter column mode set not null,
  add foreign key (match_type, mode) references public.game_modes;

-- Like the old player columns, player_id has no foreign key and the name is
-- a copy, so a result outlives a deleted account. Teammates share a side and
-- a score.
create table public.match_players (
  match_id       bigint not null references public.matches (id) on delete cascade,
  player_id      uuid not null,
  player_name    text not null,
  side           smallint not null check (side between 1 and 4),
  score          numeric(3, 1) not null,
  rating_before  integer not null,
  rating_delta   integer not null,
  primary key (match_id, player_id)
);

create index match_players_player_idx on public.match_players (player_id, match_id desc);

insert into public.match_players (
  match_id, player_id, player_name, side, score, rating_before, rating_delta
)
select id, player1_id, player1_name, 1, player1_score, player1_rating_before, player1_rating_delta
  from public.matches
union all
select id, player2_id, player2_name, 2, player2_score, player2_rating_before, player2_rating_delta
  from public.matches;

drop trigger matches_copy_names on public.matches;
drop function public.copy_player_names();

alter table public.matches
  drop column player1_id,
  drop column player2_id,
  drop column player1_score,
  drop column player2_score,
  drop column player1_rating_before,
  drop column player2_rating_before,
  drop column player1_rating_delta,
  drop column player2_rating_delta,
  drop column player1_name,
  drop column player2_name;

-- Fills a new result's name copy from the player's profile, so
-- respond_to_match doesn't have to know about it.
create function public.copy_player_name()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.player_name := (select display_name from public.profiles where id = new.player_id);
  return new;
end;
$$;

create trigger match_players_copy_name before insert on public.match_players
  for each row execute function public.copy_player_name();

-- A rename shows in the history, as it did with the live join.
create or replace function public.propagate_display_name()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.match_players set player_name = new.display_name where player_id = new.id;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Players of a request
-- ---------------------------------------------------------------------------

alter table public.match_requests
  add column mode text,
  add column declined_by uuid references public.profiles (id) on delete cascade;
update public.match_requests set mode = pg_temp.original_mode(match_type);
alter table public.match_requests
  alter column mode set not null,
  add foreign key (match_type, mode) references public.game_modes;

-- The reporter is confirmed from the start; the result counts once every
-- other player has confirmed too.
create table public.match_request_players (
  request_id  bigint not null references public.match_requests (id) on delete cascade,
  player_id   uuid not null references public.profiles (id) on delete cascade,
  side        smallint not null check (side between 1 and 4),
  score       numeric(3, 1) not null,
  confirmed   boolean not null default false,
  primary key (request_id, player_id)
);

create index match_request_players_player_idx on public.match_request_players (player_id);

insert into public.match_request_players (request_id, player_id, side, score, confirmed)
select id, player1_id, 1, player1_score, requested_by = player1_id from public.match_requests
union all
select id, player2_id, 2, player2_score, requested_by = player2_id from public.match_requests;

-- The read policy names the old columns, so it goes first.
drop policy "Players can read their open results" on public.match_requests;

alter table public.match_requests
  drop column player1_id,
  drop column player2_id,
  drop column player1_score,
  drop column player2_score;

-- A request missing one of its players can never be confirmed, so it goes
-- with any of them (their account deleted).
create function public.drop_requests_of_deleted_member()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.match_requests r
    where exists (
      select 1 from public.match_request_players p
      where p.request_id = r.id and p.player_id = old.id
    );
  return old;
end;
$$;

create trigger profiles_drop_requests before delete on public.profiles
  for each row execute function public.drop_requests_of_deleted_member();

revoke execute on function public.drop_requests_of_deleted_member() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Which results can be reported
-- ---------------------------------------------------------------------------

-- Why [players] ({player_id, side, score} each) can't end a game of this
-- mode, or null when they can. Sides are numbered from 1, teammates share a
-- score, and the scores follow the game's is_valid_score between the two
-- sides; in a free-for-all each score is the number of players outlasted.
create function public.invalid_result_reason(
  p_match_type public.match_type,
  p_mode text,
  p_players jsonb
) returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  mode_format text := (
    select format from public.game_modes where match_type = p_match_type and mode = p_mode
  );
  side_sizes integer[];
  side_scores numeric[];
begin
  if mode_format is null then
    return 'Pick a mode of this game';
  end if;
  if jsonb_typeof(p_players) is distinct from 'array' or exists (
    select 1 from jsonb_array_elements(p_players) e
    where jsonb_typeof(e->'player_id') is distinct from 'string'
       or jsonb_typeof(e->'side') is distinct from 'number'
       or jsonb_typeof(e->'score') is distinct from 'number'
  ) then
    return 'Each player needs a side and a score';
  end if;
  if (select count(distinct e->>'player_id') <> count(*) from jsonb_array_elements(p_players) e) then
    return 'Each player can only play once';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_players) e
    group by e->'side' having count(distinct (e->>'score')::numeric) > 1
  ) then
    return 'Teammates share one result';
  end if;

  select array_agg(size order by side), array_agg(score order by side)
    into side_sizes, side_scores
    from (
      select (e->>'side')::numeric as side, count(*) as size, min((e->>'score')::numeric) as score
      from jsonb_array_elements(p_players) e group by 1
    ) s;
  -- n distinct whole sides all within 1..n are exactly 1..n.
  if exists (
    select 1 from jsonb_array_elements(p_players) e
    where (e->>'side')::numeric not between 1 and cardinality(side_sizes)
       or (e->>'side')::numeric <> trunc((e->>'side')::numeric)
  ) then
    return 'Number the sides from 1';
  end if;

  -- Parenthesised: plpgsql would end the condition at the case's first then.
  if not (case mode_format
    when 'duel' then side_sizes = array[1, 1]
    when 'teams' then side_sizes = array[2, 2]
    when 'box_vs_team' then cardinality(side_sizes) = 2 and side_sizes[1] = 1
                            and side_sizes[2] between 2 and 5
    when 'free_for_all' then cardinality(side_sizes) between 2 and 4
                             and side_sizes <@ array[1]
  end) then
    return case mode_format
      when 'duel' then 'Pick one opponent'
      when 'teams' then 'Each team has two players'
      when 'box_vs_team' then 'One box against a team of 2 to 5'
      when 'free_for_all' then 'Two to four players'
    end;
  end if;

  if mode_format = 'free_for_all' then
    if exists (
      select 1 from unnest(side_scores) as mine
      where mine is distinct from (select count(*) from unnest(side_scores) o where o < mine)
    ) then
      return 'Give each player their finishing place';
    end if;
  elsif not public.is_valid_score(p_match_type, side_scores[1], side_scores[2]) then
    return case p_match_type
      when 'chess' then 'Result must be win, loss or draw'
      when 'backgammon' then 'The winner''s score must equal the match length (1 to 25)'
      when 'swu' then 'A best of three ends 2-0, 2-1, 1-0 or 1-1'
    end;
  end if;
  return null;
end;
$$;

-- ---------------------------------------------------------------------------
-- Recording a result
-- ---------------------------------------------------------------------------

drop function public.request_match(
  public.match_type, uuid, numeric, numeric, boolean, text, smallint, smallint, smallint
);

-- The caller reports a result they played in; it waits for every other
-- player. [p_players] lists everyone, the caller included, as
-- {player_id, side, score} (see invalid_result_reason). In a chess duel side
-- 1 has white. Chess also takes the DGT 2500 preset, plus the custom time
-- for custom presets; other games take neither.
create function public.request_match(
  p_match_type public.match_type,
  p_mode text,
  p_players jsonb,
  p_rated boolean default true,
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
  reason text;
  inserted public.match_requests;
begin
  if me is null then
    raise exception 'Sign in to record a result' using errcode = '28000';
  end if;
  if p_match_type is null then
    raise exception 'Pick the game you played' using errcode = '22023';
  end if;
  reason := public.invalid_result_reason(p_match_type, p_mode, p_players);
  if reason is not null then
    raise exception '%', reason using errcode = '22023';
  end if;
  if not exists (select 1 from jsonb_array_elements(p_players) e where e->>'player_id' = me::text) then
    raise exception 'Record a result you played in' using errcode = '22023';
  end if;
  if p_rated is null then
    raise exception 'Say whether the result is rated' using errcode = '22023';
  end if;
  if p_match_type = 'chess' then
    if p_dgt_option is null or p_dgt_option not between 1 and 36 then
      raise exception 'Pick the time control you played' using errcode = '22023';
    end if;
    if not public.clock_setting_valid(p_dgt_option, p_custom_base_minutes, p_custom_extra_seconds)
       or p_custom_base_minutes not between 1 and 600
       or p_custom_extra_seconds not between 0 and 3600 then
      raise exception 'Set the custom time you played' using errcode = '22023';
    end if;
  elsif p_dgt_option is not null or p_custom_base_minutes is not null
        or p_custom_extra_seconds is not null then
    raise exception 'Only chess has time controls' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_players) e
    where not exists (select 1 from public.profiles where id::text = e->>'player_id')
  ) then
    raise exception 'Player not found' using errcode = 'P0002';
  end if;

  insert into public.match_requests (
    match_type, mode, rated, dgt_option, custom_base_minutes, custom_extra_seconds, requested_by
  ) values (
    p_match_type, p_mode, p_rated, p_dgt_option, p_custom_base_minutes, p_custom_extra_seconds, me
  ) returning * into inserted;

  insert into public.match_request_players (request_id, player_id, side, score, confirmed)
  select inserted.id, (e->>'player_id')::uuid, (e->>'side')::smallint, (e->>'score')::numeric,
         e->>'player_id' = me::text
    from jsonb_array_elements(p_players) e;

  return inserted;
end;
$$;

-- Whether the caller plays in request [p_request_id]. Security definer so
-- the read policies can ask without recursing into each other.
create function public.is_request_player(p_request_id bigint)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.match_request_players
    where request_id = p_request_id and player_id = auth.uid()
  );
$$;

-- A player confirms (returns the rated result once everyone has, null while
-- others still have to), declines (returns null; the reporter is told), or
-- the reporter withdraws (returns null). Ratings use the values at the last
-- confirmation. Each player's change is the average of what the game's
-- rating_change gives them against every player on another side; for two
-- players that is exactly rating_change. An unrated result is stored with
-- zero deltas and leaves every rating alone.
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
  inserted public.matches;
begin
  if me is null then
    raise exception 'Sign in to confirm a result' using errcode = '28000';
  end if;

  select * into req from public.match_requests
    where id = p_request_id and public.is_request_player(id) and status = 'pending'
    for update;
  if req.id is null then
    raise exception 'That result is no longer waiting for confirmation' using errcode = 'P0002';
  end if;

  if not p_accept then
    if req.requested_by = me then
      delete from public.match_requests where id = req.id;
    else
      update public.match_requests
        set status = 'declined', responded_at = now(), declined_by = me
        where id = req.id;
    end if;
    return null;
  end if;
  if req.requested_by = me then
    raise exception 'The other players have to confirm this result' using errcode = '42501';
  end if;

  update public.match_request_players set confirmed = true
    where request_id = req.id and player_id = me;
  if exists (select 1 from public.match_request_players where request_id = req.id and not confirmed) then
    return null;
  end if;

  -- First result in this mode: start from the game's starting rating.
  insert into public.ratings (player_id, match_type, mode, rating, peak_rating)
  select player_id, req.match_type, req.mode,
         public.starting_rating(req.match_type), public.starting_rating(req.match_type)
    from public.match_request_players where request_id = req.id
  on conflict do nothing;

  -- Lock every player's rating in id order so concurrent confirmations can't
  -- deadlock or lose an update.
  perform 1 from public.ratings r
    where r.match_type = req.match_type and r.mode = req.mode
      and r.player_id in (select player_id from public.match_request_players where request_id = req.id)
    order by r.player_id
    for update;

  insert into public.matches (
    match_type, mode, rated, dgt_option, custom_base_minutes, custom_extra_seconds, recorded_by
  ) values (
    req.match_type, req.mode, req.rated,
    req.dgt_option, req.custom_base_minutes, req.custom_extra_seconds, req.requested_by
  ) returning * into inserted;

  with players as (
    select p.player_id, p.side, p.score, r as standing
      from public.match_request_players p
      join public.ratings r
        on r.player_id = p.player_id and r.match_type = req.match_type and r.mode = req.mode
     where p.request_id = req.id
  ), outcomes as (
    select me_.player_id, me_.side, me_.score, (me_.standing).rating as rating_before,
           case when req.rated
             then round(avg(public.rating_change(me_.standing, them.standing, me_.score, them.score)))::integer
             else 0 end as delta,
           -- Win, draw or loss against the best player on another side.
           max(them.score) as best_opponent_score
      from players me_ join players them on them.side <> me_.side
     group by me_.player_id, me_.side, me_.score, (me_.standing).rating
  ), rated as (
    update public.ratings r set
      rating = r.rating + o.delta,
      peak_rating = greatest(r.peak_rating, r.rating + o.delta),
      played = r.played + 1,
      wins = r.wins + (o.score > o.best_opponent_score)::integer,
      losses = r.losses + (o.score < o.best_opponent_score)::integer,
      draws = r.draws + (o.score = o.best_opponent_score)::integer,
      -- FIBS experience: the match length, the winning side's score.
      experience = r.experience + case r.match_type when 'backgammon'
        then (select max(score) from players)::integer else 0 end
    from outcomes o
    where req.rated and r.player_id = o.player_id
      and r.match_type = req.match_type and r.mode = req.mode
  )
  insert into public.match_players (match_id, player_id, side, score, rating_before, rating_delta)
  select inserted.id, player_id, side, score, rating_before, delta from outcomes;

  delete from public.match_requests where id = req.id;
  return inserted;
end;
$$;

-- ---------------------------------------------------------------------------
-- Row Level Security & grants
-- ---------------------------------------------------------------------------

alter table public.game_modes enable row level security;
alter table public.match_players enable row level security;
alter table public.match_request_players enable row level security;

-- Only the RPCs read game_modes; the app has its own copy of the list.
revoke all on public.game_modes from anon, authenticated;

-- Players read their open requests; once one is declined, only its reporter
-- does (to dismiss it).
create policy "Players can read their open results"
  on public.match_requests for select
  to authenticated
  using (public.is_request_player(id) and (status = 'pending' or requested_by = auth.uid()));

create policy "Players can read who plays in their open results"
  on public.match_request_players for select
  to authenticated
  using (exists (select 1 from public.match_requests r where r.id = request_id));

create policy "Members can read who played"
  on public.match_players for select
  to authenticated
  using (true);

revoke all on public.match_players from anon, authenticated;
revoke all on public.match_request_players from anon, authenticated;
grant select on public.match_players to authenticated;
grant select on public.match_request_players to authenticated;

revoke execute on function public.request_match(
  public.match_type, text, jsonb, boolean, smallint, smallint, smallint
) from public, anon;
grant execute on function public.request_match(
  public.match_type, text, jsonb, boolean, smallint, smallint, smallint
) to authenticated;
revoke execute on function public.is_request_player(bigint) from public, anon;
grant execute on function public.is_request_player(bigint) to authenticated;

-- Live updates: a confirmation that leaves others still to confirm changes
-- only match_request_players, so the app listens to it too.
alter publication supabase_realtime add table public.match_request_players;
