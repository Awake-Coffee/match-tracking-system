-- Star Wars: Unlimited points (specs/007-swu-points). SWU stops using FIDE:
-- every SWU ladder is a points table. Everyone starts at 0 and never drops
-- below it.
--   * Premier, Eternal and Limited: a best of one is +1 for a win, -1 for a
--     loss; a best of three +3 / -1. A draw (1-1) is 0.
--   * Trilogy: +3 / -1.
--   * Twin Suns (3 or 4 players): once a player is knocked out the final
--     round is played. The first one out loses 1; the one with the most HP
--     at the end of the final round wins 2; everyone else gains 1 if still
--     alive at the end, 0 if knocked out during the final round.
-- Results and requests say whether an SWU duel was a best of one or three.
-- Existing SWU results are re-scored in the order they were played.

create or replace function public.starting_rating(match_type public.match_type)
returns integer
language sql
immutable
strict
set search_path = ''
as $$
  select case match_type when 'backgammon' then 1500 when 'swu' then 0 else 1000 end;
$$;

alter table public.match_requests add column best_of smallint check (best_of in (1, 3));
alter table public.matches add column best_of smallint check (best_of in (1, 3));

-- Twin Suns is the only free-for-all. A player's score there is how they
-- finished: 0 first out, 1 knocked out during the final round, 2 alive at
-- the end of it, 3 the winner (most HP at the end).
comment on column public.match_players.score is
  'The side''s score: chess 1, 0 or 0.5; backgammon points; SWU games won; '
  'Twin Suns 0 first out, 1 out in the final round, 2 survived, 3 winner.';

-- Points an SWU result is worth to a player who scored [p_score] against a
-- best opponent score of [p_best_opponent_score], before the floor at 0.
create function public.swu_points(
  p_format text,
  p_best_of smallint,
  p_score numeric,
  p_best_opponent_score numeric
) returns integer
language sql
immutable
set search_path = ''
as $$
  select case
    when p_format = 'free_for_all' then
      case p_score when 0 then -1 when 1 then 0 when 2 then 1 when 3 then 2 end
    when p_score > p_best_opponent_score then case p_best_of when 1 then 1 else 3 end
    when p_score < p_best_opponent_score then -1
    else 0
  end;
$$;

-- ---------------------------------------------------------------------------
-- Which results can be reported
-- ---------------------------------------------------------------------------

drop function public.invalid_result_reason(public.match_type, text, jsonb);

-- Why [players] ({player_id, side, score} each) can't end a game of this
-- mode, or null when they can. Sides are numbered from 1, teammates share a
-- score, and the scores follow the game's is_valid_score between the two
-- sides; in Twin Suns each score is how the player finished (see
-- swu_points). [p_best_of] is 1 or 3 for an SWU duel (always 3 in Trilogy)
-- and null otherwise.
create function public.invalid_result_reason(
  p_match_type public.match_type,
  p_mode text,
  p_players jsonb,
  p_best_of smallint default null
) returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  mode_format text := (
    select format from public.game_modes where match_type = p_match_type and mode = p_mode
  );
  swu_duel boolean := p_match_type = 'swu' and mode_format = 'duel';
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
    when 'free_for_all' then cardinality(side_sizes) between 3 and 4
                             and side_sizes <@ array[1]
  end) then
    return case mode_format
      when 'duel' then 'Pick one opponent'
      when 'teams' then 'Each team has two players'
      when 'box_vs_team' then 'One box against a team of 2 to 5'
      when 'free_for_all' then 'Three or four players'
    end;
  end if;

  if swu_duel and p_mode = 'trilogy' and p_best_of is distinct from 3 then
    return 'Trilogy is a best of three';
  end if;
  if swu_duel and (p_best_of is null or p_best_of not in (1, 3)) then
    return 'Say whether it was a best of one or three';
  end if;
  if not swu_duel and p_best_of is not null then
    return 'Only Star Wars: Unlimited duels are a best of one or three';
  end if;

  if mode_format = 'free_for_all' then
    if not side_scores <@ array[0, 1, 2, 3]::numeric[]
       or (select count(*) from unnest(side_scores) s where s = 3) <> 1
       or (select count(*) from unnest(side_scores) s where s = 0) <> 1 then
      return 'One winner, one player out first, and how everyone else finished';
    end if;
  elsif p_best_of = 1 then
    if (side_scores[1], side_scores[2]) not in ((1, 0), (0, 1)) then
      return 'A best of one ends 1-0';
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
  public.match_type, text, jsonb, boolean, smallint, smallint, smallint
);

-- The caller reports a result they played in; it waits for every other
-- player. [p_players] lists everyone, the caller included, as
-- {player_id, side, score} (see invalid_result_reason). In a chess duel side
-- 1 has white. Chess also takes the DGT 2500 preset, plus the custom time
-- for custom presets; other games take neither. An SWU duel takes whether
-- it was a best of one or three.
create function public.request_match(
  p_match_type public.match_type,
  p_mode text,
  p_players jsonb,
  p_rated boolean default true,
  p_dgt_option smallint default null,
  p_custom_base_minutes smallint default null,
  p_custom_extra_seconds smallint default null,
  p_best_of smallint default null
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
  reason := public.invalid_result_reason(p_match_type, p_mode, p_players, p_best_of);
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
    match_type, mode, rated, dgt_option, custom_base_minutes, custom_extra_seconds, best_of,
    requested_by
  ) values (
    p_match_type, p_mode, p_rated, p_dgt_option, p_custom_base_minutes, p_custom_extra_seconds,
    p_best_of, me
  ) returning * into inserted;

  insert into public.match_request_players (request_id, player_id, side, score, confirmed)
  select inserted.id, (e->>'player_id')::uuid, (e->>'side')::smallint, (e->>'score')::numeric,
         e->>'player_id' = me::text
    from jsonb_array_elements(p_players) e;

  return inserted;
end;
$$;

-- A player confirms (returns the rated result once everyone has, null while
-- others still have to), declines (returns null; the reporter is told), or
-- the reporter withdraws (returns null). Ratings use the values at the last
-- confirmation. In chess and backgammon each player's change is the average
-- of what the game's rating_change gives them against every player on
-- another side; for two players that is exactly rating_change. In SWU it is
-- swu_points, kept from taking a rating below 0. An unrated result is
-- stored with zero deltas and leaves every rating alone.
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
  mode_format text;
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

  mode_format := (
    select format from public.game_modes where match_type = req.match_type and mode = req.mode
  );

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
    match_type, mode, rated, dgt_option, custom_base_minutes, custom_extra_seconds, best_of,
    recorded_by
  ) values (
    req.match_type, req.mode, req.rated,
    req.dgt_option, req.custom_base_minutes, req.custom_extra_seconds, req.best_of,
    req.requested_by
  ) returning * into inserted;

  with players as (
    select p.player_id, p.side, p.score, r as standing
      from public.match_request_players p
      join public.ratings r
        on r.player_id = p.player_id and r.match_type = req.match_type and r.mode = req.mode
     where p.request_id = req.id
  ), outcomes as (
    select me_.player_id, me_.side, me_.score, (me_.standing).rating as rating_before,
           case
             when not req.rated then 0
             when req.match_type = 'swu' then greatest(
               (me_.standing).rating
                 + public.swu_points(mode_format, req.best_of, me_.score, max(them.score)),
               0) - (me_.standing).rating
             else round(avg(public.rating_change(me_.standing, them.standing, me_.score, them.score)))::integer
           end as delta,
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

revoke execute on function public.request_match(
  public.match_type, text, jsonb, boolean, smallint, smallint, smallint, smallint
) from public, anon;
grant execute on function public.request_match(
  public.match_type, text, jsonb, boolean, smallint, smallint, smallint, smallint
) to authenticated;

-- ---------------------------------------------------------------------------
-- Existing SWU results and requests
-- ---------------------------------------------------------------------------

-- Every SWU duel so far was recorded as a best of three.
update public.matches set best_of = 3
  where match_type = 'swu' and mode <> 'twin_suns';
update public.match_requests set best_of = 3
  where match_type = 'swu' and mode <> 'twin_suns';

-- Twin Suns scores were the number of players outlasted. The sole player
-- with the most is the winner, the players with the fewest were out first,
-- and everyone else is taken to have survived the final round (the old
-- scores can't tell that from being knocked out during it). Players tied for
-- the most all survived.
create function pg_temp.twin_suns_finish(p_score numeric, p_scores numeric[])
returns numeric
language sql immutable as $$
  select case
    when p_score = (select max(s) from unnest(p_scores) s)
      then case when (select count(*) from unnest(p_scores) s where s = p_score) = 1 then 3 else 2 end
    when p_score = (select min(s) from unnest(p_scores) s) then 0
    else 2
  end;
$$;

update public.match_players p
   set score = pg_temp.twin_suns_finish(p.score, (
     select array_agg(o.score) from public.match_players o where o.match_id = p.match_id))
  from public.matches m
 where m.id = p.match_id and m.match_type = 'swu' and m.mode = 'twin_suns';

update public.match_request_players p
   set score = pg_temp.twin_suns_finish(p.score, (
     select array_agg(o.score) from public.match_request_players o where o.request_id = p.request_id))
  from public.match_requests r
 where r.id = p.request_id and r.match_type = 'swu' and r.mode = 'twin_suns';

-- Open Twin Suns reports that still don't fit (two players, or no single
-- winner) can't be confirmed any more; their reporters record them again.
delete from public.match_requests r
 where r.match_type = 'swu' and r.mode = 'twin_suns'
   and public.invalid_result_reason(r.match_type, r.mode, (
     select jsonb_agg(jsonb_build_object('player_id', p.player_id, 'side', p.side, 'score', p.score))
       from public.match_request_players p where p.request_id = r.id
   ), r.best_of) is not null;

-- Re-score every SWU result in the order it was played, so each player row
-- keeps its rating before and delta under the new rules (principle II).
-- Players whose account was deleted are replayed too, so their opponents'
-- numbers stay right.
create temporary table swu_replay (
  player_id  uuid not null,
  mode       text not null,
  rating     integer not null default 0,
  peak       integer not null default 0,
  played     integer not null default 0,
  wins       integer not null default 0,
  losses     integer not null default 0,
  draws      integer not null default 0,
  primary key (player_id, mode)
);

do $$
declare
  m public.matches;
  mode_format text;
begin
  for m in
    select * from public.matches where match_type = 'swu' order by played_at, id
  loop
    mode_format := (select format from public.game_modes where match_type = 'swu' and mode = m.mode);

    insert into swu_replay (player_id, mode)
    select player_id, m.mode from public.match_players where match_id = m.id
    on conflict do nothing;

    with players as (
      select p.player_id, p.side, p.score, s.rating
        from public.match_players p
        join swu_replay s on s.player_id = p.player_id and s.mode = m.mode
       where p.match_id = m.id
    ), outcomes as (
      select me_.player_id, me_.score, me_.rating,
             case when m.rated then greatest(
               me_.rating + public.swu_points(mode_format, m.best_of, me_.score, max(them.score)), 0
             ) - me_.rating else 0 end as delta,
             max(them.score) as best_opponent_score
        from players me_ join players them on them.side <> me_.side
       group by me_.player_id, me_.score, me_.rating
    ), audited as (
      update public.match_players p
         set rating_before = o.rating, rating_delta = o.delta
        from outcomes o
       where p.match_id = m.id and p.player_id = o.player_id
    )
    update swu_replay s set
      rating = s.rating + o.delta,
      peak = greatest(s.peak, s.rating + o.delta),
      played = s.played + 1,
      wins = s.wins + (o.score > o.best_opponent_score)::integer,
      losses = s.losses + (o.score < o.best_opponent_score)::integer,
      draws = s.draws + (o.score = o.best_opponent_score)::integer
      from outcomes o
     where m.rated and s.player_id = o.player_id and s.mode = m.mode;
  end loop;
end $$;

update public.ratings r set
  rating = coalesce(s.rating, 0),
  peak_rating = coalesce(s.peak, 0),
  played = coalesce(s.played, 0),
  wins = coalesce(s.wins, 0),
  losses = coalesce(s.losses, 0),
  draws = coalesce(s.draws, 0)
  from public.ratings x
  left join swu_replay s on s.player_id = x.player_id and s.mode = x.mode
 where x.match_type = 'swu'
   and r.player_id = x.player_id and r.match_type = x.match_type and r.mode = x.mode;

drop table swu_replay;
