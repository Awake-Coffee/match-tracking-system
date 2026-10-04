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
select test.request_duel(
  'chess', '00000000-0000-0000-0000-0000000000b6', 1, 0, true, 'white', 1::smallint);
select test.request_duel('backgammon', '00000000-0000-0000-0000-0000000000b6', 5, 2);
select test.request_duel('swu', '00000000-0000-0000-0000-0000000000b6', 2, 0);

-- Bo can't read a declined request afterwards, so remember the ids.
select set_config('test.ids', (select string_agg(id::text, ',' order by id)
  from test.match_requests), false);

do $$
begin
  assert (select count(*) = 3 and bool_and(status = 'pending' and responded_at is null)
    from test.match_requests), 'requests start pending in every game';
end $$;

-- The reporter can't dismiss what is still pending.
do $$
begin
  perform public.dismiss_declined_match((select max(id) from test.match_requests));
  assert false, 'dismissing a pending request should fail';
exception when sqlstate 'P0002' then null;
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b6', false);
select public.respond_to_match(id, false) from test.match_requests order by id;

-- Bo has no use for a request he declined: only Ana can still read it.
do $$
begin
  assert not exists (select 1 from test.match_requests),
    'the respondent no longer sees what they declined';
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a6', false);
do $$
begin
  assert (select count(distinct match_type) = 3
      and bool_and(status = 'declined' and responded_at is not null)
    from test.match_requests), 'requests kept as declined in every game';
  assert not exists (select 1 from test.matches
    where '00000000-0000-0000-0000-0000000000a6' in (player1_id, player2_id)),
    'declining records no result';
  assert not exists (select 1 from public.ratings
    where player_id = '00000000-0000-0000-0000-0000000000a6'
      and (rating <> public.starting_rating(match_type) or played > 0)),
    'declining moves no rating';
end $$;

-- A declined request can't be answered again, nor dismissed by the one who
-- declined it.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b6', false);
do $$
declare
  id bigint;
begin
  foreach id in array string_to_array(current_setting('test.ids'), ',')::bigint[] loop
    begin
      perform public.respond_to_match(id, true);
      assert false, 'confirming a declined request should fail';
    exception when sqlstate 'P0002' then null;
    end;
    begin
      perform public.dismiss_declined_match(id);
      assert false, 'the respondent should not dismiss a request';
    exception when sqlstate 'P0002' then null;
    end;
  end loop;
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a6', false);
select public.dismiss_declined_match(id)
  from unnest(string_to_array(current_setting('test.ids'), ',')::bigint[]) as id;

do $$
begin
  assert not exists (select 1 from test.match_requests), 'dismissing deletes the request';
end $$;

-- The reporter withdrawing a pending request still deletes it outright.
select test.request_duel('swu', '00000000-0000-0000-0000-0000000000b6', 2, 1);
select public.respond_to_match((select max(id) from test.match_requests), false);
do $$
begin
  assert not exists (select 1 from test.match_requests), 'withdrawing deletes the request';
end $$;

-- Dismissing needs a signed-in member.
select set_config('request.jwt.claim.sub', '', false);
do $$
begin
  perform public.dismiss_declined_match(1);
  assert false, 'dismissing needs sign-in';
exception when sqlstate '28000' then null;
end $$;

rollback;
\echo 'decline_test: all assertions passed'
