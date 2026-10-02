# Awake Coffee Match Tracking — Constitution

## Core Principles

### I. Ratings are server-authoritative
Rating changes are computed inside Postgres (Supabase) by a single
`SECURITY DEFINER` function. Clients never send ratings, deltas or
win/loss counters; they only report who played and how it ended. The
client-side Elo implementation exists solely to *preview* a result and
must produce the same numbers as the database.

### II. Every rating point is traceable
A player's rating is the starting rating (1000) plus the sum of the
deltas of the matches they played. Each match row stores both players'
ratings before the game and the delta applied, so any rating can be
audited and the full history replayed.

### III. Secure by default (RLS everywhere)
Every table has Row Level Security enabled. Authenticated members can
read the ladder; they can only edit cosmetic fields of their own
profile. Writes to ratings and matches happen exclusively through
audited RPCs.

### IV. Test the math first
The Elo formula, rounding and zero-sum guarantee are covered by unit
tests in Dart and by SQL tests against a real Postgres before any UI
depends on them.

### V. Design is a swappable layer
Screens read colors, type, shape and leaderboard layout from a
`DesignSpec`. No screen hardcodes a color or font. Adding a design must
not require touching screen logic.

### VI. Start narrow
Only chess is supported today. The schema keeps a `game` column so other
tabletop games can be added later, but no speculative multi-game
abstractions are built now.

## Technology Constraints

- Client: Flutter (web first, mobile-ready), deployed to Vercel as a
  static build.
- Backend: Supabase (Postgres, Auth, RLS). Schema changes ship as
  numbered SQL migrations in `supabase/migrations`.
- Styling: design tokens follow Tailwind's naming and scales; HTML
  prototypes of the designs are built with Tailwind.
- Secrets: only the Supabase URL and publishable (anon) key reach the
  client, via `--dart-define`. The service-role key never leaves Supabase.

## Development Workflow

Spec Kit flow: `constitution → specify → clarify → plan → tasks →
implement`. Each feature lives in `specs/NNN-name/` with `spec.md`,
`plan.md`, `research.md`, `data-model.md`, `contracts/`, `quickstart.md`
and `tasks.md`. `flutter analyze`, `flutter test` and the SQL tests must
pass before merging.

## Governance

This constitution overrides conflicting practice. Amendments are made by
PR that updates this file, bumps the version and explains the migration
path for existing data.

**Version**: 1.0.0 | **Ratified**: 2026-10-02 | **Last Amended**: 2026-10-02
