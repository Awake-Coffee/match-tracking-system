-- Shorthands for the SQL tests, loaded after the migrations. Most tests are
-- about duels: test.request_duel reports one from the caller's side in the
-- game's original mode (side 1 is white in chess, the reporter otherwise),
-- and the test.matches / test.match_requests views read a duel's two players
-- as player1_* / player2_* columns. Views run as the caller, so row level
-- security still applies.
create schema test;
grant usage on schema test to anon, authenticated;

create function test.request_duel(
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
language sql
as $$
  select public.request_match(
    p_match_type,
    case p_match_type when 'swu' then 'premier' else 'standard' end,
    jsonb_build_array(
      jsonb_build_object('player_id', auth.uid(),
        'side', case p_my_color when 'black' then 2 else 1 end, 'score', p_my_score),
      jsonb_build_object('player_id', p_opponent_id,
        'side', case p_my_color when 'black' then 1 else 2 end, 'score', p_opponent_score)),
    p_rated, p_dgt_option, p_custom_base_minutes, p_custom_extra_seconds);
$$;

create view test.matches with (security_invoker = true) as
select m.*,
       p1.player_id as player1_id, p2.player_id as player2_id,
       p1.score as player1_score, p2.score as player2_score,
       p1.rating_before as player1_rating_before, p2.rating_before as player2_rating_before,
       p1.rating_delta as player1_rating_delta, p2.rating_delta as player2_rating_delta,
       p1.player_name as player1_name, p2.player_name as player2_name
  from public.matches m
  join public.match_players p1 on p1.match_id = m.id and p1.side = 1
  join public.match_players p2 on p2.match_id = m.id and p2.side = 2;

create view test.match_requests with (security_invoker = true) as
select r.*,
       p1.player_id as player1_id, p2.player_id as player2_id,
       p1.score as player1_score, p2.score as player2_score
  from public.match_requests r
  join public.match_request_players p1 on p1.request_id = r.id and p1.side = 1
  join public.match_request_players p2 on p2.request_id = r.id and p2.side = 2;

grant execute on function test.request_duel to anon, authenticated;
grant select on test.matches, test.match_requests to authenticated;
