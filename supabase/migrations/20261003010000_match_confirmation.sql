-- Games only count once the opponent confirms them. A reported game waits in
-- match_requests until the opponent accepts (ratings move then) or either
-- player drops it. Games also record the DGT 2500 preset they were played on.

-- DGT 2500 option number (1-36, see TimeControl in app/lib/domain/models.dart).
-- Null for games recorded before this migration.
alter table public.matches
  add column dgt_option smallint check (dgt_option between 1 and 36);

create table public.match_requests (
  id            bigint generated always as identity primary key,
  white_id      uuid not null references public.profiles (id) on delete cascade,
  black_id      uuid not null references public.profiles (id) on delete cascade,
  result        text not null check (result in ('white', 'black', 'draw')),
  dgt_option    smallint not null check (dgt_option between 1 and 36),
  requested_by  uuid not null references public.profiles (id) on delete cascade,
  created_at    timestamptz not null default now(),
  check (white_id <> black_id),
  check (requested_by in (white_id, black_id))
);

create index match_requests_white_idx on public.match_requests (white_id);
create index match_requests_black_idx on public.match_requests (black_id);

drop function public.record_chess_match(uuid, text, text);

-- The caller reports a game they played; it waits for the opponent.
-- p_my_color: 'white' | 'black'. p_my_result: 'win' | 'loss' | 'draw'.
create or replace function public.request_chess_match(
  p_opponent_id uuid,
  p_my_color text,
  p_my_result text,
  p_dgt_option smallint
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
  if not exists (select 1 from public.profiles where id = p_opponent_id) then
    raise exception 'Opponent not found' using errcode = 'P0002';
  end if;

  insert into public.match_requests (white_id, black_id, result, dgt_option, requested_by)
  values (
    case p_my_color when 'white' then me else p_opponent_id end,
    case p_my_color when 'white' then p_opponent_id else me end,
    case
      when p_my_result = 'draw' then 'draw'
      when p_my_result = 'win' then p_my_color
      else case p_my_color when 'white' then 'black' else 'white' end
    end,
    p_dgt_option,
    me
  ) returning * into inserted;

  return inserted;
end;
$$;

-- The opponent accepts (rates the game, returns the match) or either player
-- drops the request (returns null). Ratings use the values at acceptance.
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
    rating_delta, recorded_by, dgt_option
  ) values (
    req.white_id, req.black_id, req.result, white_rating, black_rating,
    delta, req.requested_by, req.dgt_option
  ) returning * into inserted;

  return inserted;
end;
$$;

alter table public.match_requests enable row level security;

create policy "Players can read their pending games"
  on public.match_requests for select
  to authenticated
  using (auth.uid() in (white_id, black_id));

revoke all on public.match_requests from anon, authenticated;
grant select on public.match_requests to authenticated;

revoke execute on function public.request_chess_match(uuid, text, text, smallint) from public, anon;
grant execute on function public.request_chess_match(uuid, text, text, smallint) to authenticated;
revoke execute on function public.respond_to_chess_match(bigint, boolean) from public, anon;
grant execute on function public.respond_to_chess_match(bigint, boolean) to authenticated;
