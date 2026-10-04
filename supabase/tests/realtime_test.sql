-- The tables the app listens to for live updates are streamed by Realtime.
\set ON_ERROR_STOP on
begin;

do $$
declare
  t text;
begin
  foreach t in array array[
    'match_requests', 'backgammon_match_requests', 'swu_match_requests',
    'matches', 'backgammon_matches', 'swu_matches'
  ] loop
    assert exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ), format('%s is in the supabase_realtime publication', t);
  end loop;
end $$;

rollback;
\echo 'realtime_test: all assertions passed'
