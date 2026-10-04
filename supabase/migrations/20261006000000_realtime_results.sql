-- Live updates: members see a result waiting for them as soon as the
-- opponent reports it, without reloading. The app subscribes (Realtime
-- postgres_changes) to every request change and every confirmed result;
-- Realtime only streams tables in the supabase_realtime publication, and
-- delivers a row only to members whose RLS policies let them read it.
-- Every game shares these two tables, keyed by match_type.

do $$
declare
  t text;
begin
  foreach t in array array['match_requests', 'matches'] loop
    -- Skipping tables already published keeps this safe to re-run.
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
