-- Declining tells the reporter: the request stays as 'declined' until the
-- reporter dismisses it, in every game. Each block raises on failure. Rolled
-- back so other tests see an empty database.
\set ON_ERROR_STOP on
begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000a6', 'ana@decline.example', '{"display_name":"Decline Ana"}'),
  ('00000000-0000-0000-0000-0000000000b6', 'bo@decline.example',  '{"display_name":"Decline Bo"}');

set role authenticated;

-- Ana reports one result in each game; Bo declines them all.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a6', false);
select public.request_chess_match(
  '00000000-0000-0000-0000-0000000000b6', 'white', 'win', 1::smallint, null, null, true);
select public.request_backgammon_match(
  '00000000-0000-0000-0000-0000000000b6', 5::smallint, 5::smallint, 2::smallint, true);
select public.request_swu_match(
  '00000000-0000-0000-0000-0000000000b6', 2::smallint, 0::smallint, true);

-- Bo can't read a declined request afterwards, so remember the ids.
select set_config('test.chess_id', (select max(id) from public.match_requests)::text, false),
       set_config('test.bg_id', (select max(id) from public.backgammon_match_requests)::text, false),
       set_config('test.swu_id', (select max(id) from public.swu_match_requests)::text, false);

do $$
begin
  assert (select bool_and(status = 'pending' and responded_at is null) from public.match_requests),
    'chess request starts pending';
  assert (select bool_and(status = 'pending' and responded_at is null) from public.backgammon_match_requests),
    'backgammon request starts pending';
  assert (select bool_and(status = 'pending' and responded_at is null) from public.swu_match_requests),
    'SWU request starts pending';
end $$;

-- The reporter can't dismiss what is still pending.
do $$
begin
  perform public.dismiss_declined_chess_match((select max(id) from public.match_requests));
  assert false, 'dismissing a pending chess request should fail';
exception when sqlstate 'P0002' then null;
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b6', false);
select public.respond_to_chess_match((select max(id) from public.match_requests), false);
select public.respond_to_backgammon_match((select max(id) from public.backgammon_match_requests), false);
select public.respond_to_swu_match((select max(id) from public.swu_match_requests), false);

-- Bo has no use for a request he declined: only Ana can still read it.
do $$
begin
  assert not exists (select 1 from public.match_requests)
    and not exists (select 1 from public.backgammon_match_requests)
    and not exists (select 1 from public.swu_match_requests),
    'the respondent no longer sees what they declined';
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a6', false);
do $$
begin
  assert (select count(*) = 1 and bool_and(status = 'declined' and responded_at is not null)
    from public.match_requests), 'chess request kept as declined';
  assert (select count(*) = 1 and bool_and(status = 'declined' and responded_at is not null)
    from public.backgammon_match_requests), 'backgammon request kept as declined';
  assert (select count(*) = 1 and bool_and(status = 'declined' and responded_at is not null)
    from public.swu_match_requests), 'SWU request kept as declined';
  assert not exists (select 1 from public.matches where white_id = '00000000-0000-0000-0000-0000000000a6')
    and not exists (select 1 from public.backgammon_matches where winner_id = '00000000-0000-0000-0000-0000000000a6')
    and not exists (select 1 from public.swu_matches where reporter_id = '00000000-0000-0000-0000-0000000000a6'),
    'declining records no result';
  assert (select rating = 1000 and bg_rating = 1500 and swu_rating = 1000 and games_played = 0
    from public.profiles where display_name = 'Decline Ana'), 'declining moves no rating';
end $$;

-- A declined request can't be answered again, by either player.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b6', false);
do $$
begin
  perform public.respond_to_chess_match(current_setting('test.chess_id')::bigint, true);
  assert false, 'confirming a declined chess request should fail';
exception when sqlstate 'P0002' then null;
end $$;
do $$
begin
  perform public.respond_to_backgammon_match(current_setting('test.bg_id')::bigint, true);
  assert false, 'confirming a declined backgammon request should fail';
exception when sqlstate 'P0002' then null;
end $$;
do $$
begin
  perform public.respond_to_swu_match(current_setting('test.swu_id')::bigint, true);
  assert false, 'confirming a declined SWU request should fail';
exception when sqlstate 'P0002' then null;
end $$;

-- Only the reporter can dismiss it.
do $$
begin
  perform public.dismiss_declined_chess_match(current_setting('test.chess_id')::bigint);
  assert false, 'the respondent should not dismiss a chess request';
exception when sqlstate 'P0002' then null;
end $$;
do $$
begin
  perform public.dismiss_declined_swu_match(current_setting('test.swu_id')::bigint);
  assert false, 'the respondent should not dismiss an SWU request';
exception when sqlstate 'P0002' then null;
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a6', false);
select public.dismiss_declined_chess_match(current_setting('test.chess_id')::bigint);
select public.dismiss_declined_backgammon_match(current_setting('test.bg_id')::bigint);
select public.dismiss_declined_swu_match(current_setting('test.swu_id')::bigint);

do $$
begin
  assert not exists (select 1 from public.match_requests)
    and not exists (select 1 from public.backgammon_match_requests)
    and not exists (select 1 from public.swu_match_requests), 'dismissing deletes the request';
end $$;

-- The reporter withdrawing a pending request still deletes it outright.
select public.request_chess_match(
  '00000000-0000-0000-0000-0000000000b6', 'white', 'win', 1::smallint, null, null, true);
select public.respond_to_chess_match((select max(id) from public.match_requests), false);
do $$
begin
  assert not exists (select 1 from public.match_requests), 'withdrawing deletes the request';
end $$;

-- Dismissing needs a signed-in member.
select set_config('request.jwt.claim.sub', '', false);
do $$
begin
  perform public.dismiss_declined_chess_match(1);
  assert false, 'dismissing needs sign-in';
exception when sqlstate '28000' then null;
end $$;

rollback;
\echo 'decline_test: all assertions passed'
