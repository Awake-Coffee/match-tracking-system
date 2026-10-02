-- Awake Coffee match tracking: chess Elo ladder.
-- Ratings are computed here and only here (constitution principle I).

-- ---------------------------------------------------------------------------
-- Profiles
-- ---------------------------------------------------------------------------

create table public.profiles (
  id            uuid primary key references auth.users (id) on delete cascade,
  display_name  text not null check (char_length(btrim(display_name)) between 2 and 32),
  rating        integer not null default 1000,
  games_played  integer not null default 0 check (games_played >= 0),
  wins          integer not null default 0 check (wins >= 0),
  losses        integer not null default 0 check (losses >= 0),
  draws         integer not null default 0 check (draws >= 0),
  design        text not null default 'chalkboard'
                check (design in ('chalkboard', 'receipt', 'crema', 'bauhaus', 'sunrise')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (games_played = wins + losses + draws)
);

create unique index profiles_display_name_key on public.profiles (lower(display_name));
create index profiles_ladder_idx on public.profiles (rating desc, games_played desc);

-- ---------------------------------------------------------------------------
-- Matches
-- ---------------------------------------------------------------------------

create table public.matches (
  id                   bigint generated always as identity primary key,
  game                 text not null default 'chess' check (game = 'chess'),
  white_id             uuid not null references public.profiles (id) on delete restrict,
  black_id             uuid not null references public.profiles (id) on delete restrict,
  result               text not null check (result in ('white', 'black', 'draw')),
  white_rating_before  integer not null,
  black_rating_before  integer not null,
  -- Points white gained (negative if white lost points). Black gets -rating_delta.
  rating_delta         integer not null,
  recorded_by          uuid not null references public.profiles (id) on delete restrict,
  played_at            timestamptz not null default now(),
  check (white_id <> black_id)
);

create index matches_played_at_idx on public.matches (played_at desc);
create index matches_white_idx on public.matches (white_id, played_at desc);
create index matches_black_idx on public.matches (black_id, played_at desc);

-- ---------------------------------------------------------------------------
-- Elo math
-- ---------------------------------------------------------------------------

-- Points player A gains against B. score is 1 (win), 0.5 (draw) or 0 (loss).
-- Mirrored exactly by app/lib/domain/elo.dart.
create or replace function public.elo_delta(
  rating_a integer,
  rating_b integer,
  score numeric,
  k integer default 32
) returns integer
language sql
immutable
strict
set search_path = ''
as $$
  select round(
    k * (score - 1 / (1 + power(10::numeric, (rating_b - rating_a) / 400.0)))
  )::integer;
$$;

-- ---------------------------------------------------------------------------
-- Profile bootstrap on sign-up
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  base_name text;
  candidate text;
  suffix integer := 1;
begin
  base_name := left(btrim(coalesce(
    nullif(btrim(new.raw_user_meta_data ->> 'display_name'), ''),
    split_part(new.email, '@', 1),
    'player'
  )), 28);
  if char_length(base_name) < 2 then
    base_name := 'player';
  end if;

  candidate := base_name;
  while exists (select 1 from public.profiles where lower(display_name) = lower(candidate)) loop
    suffix := suffix + 1;
    candidate := base_name || ' ' || suffix;
  end loop;

  insert into public.profiles (id, display_name) values (new.id, candidate);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger profiles_touch_updated_at
  before update on public.profiles
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Recording a game
-- ---------------------------------------------------------------------------

-- The caller reports a game they played. p_my_color: 'white' | 'black'.
-- p_my_result: 'win' | 'loss' | 'draw'. Returns the inserted match.
create or replace function public.record_chess_match(
  p_opponent_id uuid,
  p_my_color text,
  p_my_result text
) returns public.matches
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  v_white uuid;
  v_black uuid;
  v_result text;
  white_rating integer;
  black_rating integer;
  delta integer;
  white_score numeric;
  inserted public.matches;
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

  if p_my_color = 'white' then
    v_white := me;  v_black := p_opponent_id;
  else
    v_white := p_opponent_id;  v_black := me;
  end if;

  v_result := case
    when p_my_result = 'draw' then 'draw'
    when p_my_result = 'win' then p_my_color
    else case p_my_color when 'white' then 'black' else 'white' end
  end;

  -- Lock both rows in id order so concurrent recordings can't deadlock or
  -- lose an update.
  perform 1 from public.profiles
    where id in (v_white, v_black)
    order by id
    for update;

  select rating into white_rating from public.profiles where id = v_white;
  select rating into black_rating from public.profiles where id = v_black;
  if white_rating is null or black_rating is null then
    raise exception 'Opponent not found' using errcode = 'P0002';
  end if;

  white_score := case v_result when 'white' then 1 when 'black' then 0 else 0.5 end;
  delta := public.elo_delta(white_rating, black_rating, white_score);

  update public.profiles set
    rating = rating + delta,
    games_played = games_played + 1,
    wins = wins + (v_result = 'white')::integer,
    losses = losses + (v_result = 'black')::integer,
    draws = draws + (v_result = 'draw')::integer
  where id = v_white;

  update public.profiles set
    rating = rating - delta,
    games_played = games_played + 1,
    wins = wins + (v_result = 'black')::integer,
    losses = losses + (v_result = 'white')::integer,
    draws = draws + (v_result = 'draw')::integer
  where id = v_black;

  insert into public.matches (
    white_id, black_id, result, white_rating_before, black_rating_before,
    rating_delta, recorded_by
  ) values (
    v_white, v_black, v_result, white_rating, black_rating, delta, me
  ) returning * into inserted;

  return inserted;
end;
$$;

-- ---------------------------------------------------------------------------
-- Row Level Security & grants
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.matches enable row level security;

create policy "Members can read the ladder"
  on public.profiles for select
  to authenticated
  using (true);

create policy "Members can edit their own profile"
  on public.profiles for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

create policy "Members can read matches"
  on public.matches for select
  to authenticated
  using (true);

-- No insert/update/delete policies on matches: writes go through
-- record_chess_match only.

revoke all on public.profiles from anon, authenticated;
revoke all on public.matches from anon, authenticated;
grant select on public.profiles to authenticated;
grant update (display_name, design) on public.profiles to authenticated;
grant select on public.matches to authenticated;

revoke execute on function public.record_chess_match(uuid, text, text) from public, anon;
grant execute on function public.record_chess_match(uuid, text, text) to authenticated;
revoke execute on function public.handle_new_user() from public, anon, authenticated;
