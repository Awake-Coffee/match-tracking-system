-- The DGT 2500 "manual setting" presets carry the time the players actually
-- set: a base time, plus the increment/delay/byo-yomi seconds for the methods
-- that have one.

-- Whether the custom values fit the preset: custom presets need their values,
-- every other preset (or no preset) must have none.
create or replace function public.clock_setting_valid(
  dgt_option smallint,
  custom_base_minutes smallint,
  custom_extra_seconds smallint
) returns boolean
language sql
immutable
set search_path = ''
as $$
  select case
    -- Sudden death custom, hourglass custom: base time only.
    when dgt_option in (8, 33) then
      custom_base_minutes is not null and custom_extra_seconds is null
    -- Fischer, Bronstein, US delay, byo-yomi, Canadian byo-yomi custom.
    when dgt_option in (21, 23, 25, 27, 29) then
      custom_base_minutes is not null and custom_extra_seconds is not null
    else custom_base_minutes is null and custom_extra_seconds is null
  end;
$$;

alter table public.matches
  add column custom_base_minutes smallint check (custom_base_minutes between 1 and 600),
  add column custom_extra_seconds smallint check (custom_extra_seconds between 0 and 3600),
  add constraint matches_clock_setting_check
    check (public.clock_setting_valid(dgt_option, custom_base_minutes, custom_extra_seconds));

alter table public.match_requests
  add column custom_base_minutes smallint check (custom_base_minutes between 1 and 600),
  add column custom_extra_seconds smallint check (custom_extra_seconds between 0 and 3600),
  add constraint match_requests_clock_setting_check
    check (public.clock_setting_valid(dgt_option, custom_base_minutes, custom_extra_seconds));

drop function public.request_chess_match(uuid, text, text, smallint);

-- The caller reports a game they played; it waits for the opponent.
-- p_my_color: 'white' | 'black'. p_my_result: 'win' | 'loss' | 'draw'.
-- The custom values are only (and then always) given for custom presets.
create or replace function public.request_chess_match(
  p_opponent_id uuid,
  p_my_color text,
  p_my_result text,
  p_dgt_option smallint,
  p_custom_base_minutes smallint default null,
  p_custom_extra_seconds smallint default null
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
  if not exists (select 1 from public.profiles where id = p_opponent_id) then
    raise exception 'Opponent not found' using errcode = 'P0002';
  end if;

  insert into public.match_requests (
    white_id, black_id, result, dgt_option, custom_base_minutes,
    custom_extra_seconds, requested_by
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
    me
  ) returning * into inserted;

  return inserted;
end;
$$;

-- Same as before, but the custom time carries over to the rated match.
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
  white_rating integer;
  black_rating integer;
  delta integer;
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

  select rating into white_rating from public.profiles where id = req.white_id;
  select rating into black_rating from public.profiles where id = req.black_id;

  delta := public.elo_delta(
    white_rating, black_rating,
    case req.result when 'white' then 1 when 'black' then 0 else 0.5 end
  );

  update public.profiles set
    rating = rating + delta,
    games_played = games_played + 1,
    wins = wins + (req.result = 'white')::integer,
    losses = losses + (req.result = 'black')::integer,
    draws = draws + (req.result = 'draw')::integer
  where id = req.white_id;

  update public.profiles set
    rating = rating - delta,
    games_played = games_played + 1,
    wins = wins + (req.result = 'black')::integer,
    losses = losses + (req.result = 'white')::integer,
    draws = draws + (req.result = 'draw')::integer
  where id = req.black_id;

  insert into public.matches (
    white_id, black_id, result, white_rating_before, black_rating_before,
    rating_delta, recorded_by, dgt_option, custom_base_minutes, custom_extra_seconds
  ) values (
    req.white_id, req.black_id, req.result, white_rating, black_rating,
    delta, req.requested_by, req.dgt_option, req.custom_base_minutes, req.custom_extra_seconds
  ) returning * into inserted;

  return inserted;
end;
$$;

revoke execute on function public.request_chess_match(uuid, text, text, smallint, smallint, smallint) from public, anon;
grant execute on function public.request_chess_match(uuid, text, text, smallint, smallint, smallint) to authenticated;
