# Awake Coffee Match Tracking — Constitution

## Core Principles

### I. Ratings are server-authoritative
Rating changes are computed inside Postgres (Supabase) by a single
`SECURITY DEFINER` function. Clients never send ratings, deltas or
win/loss counters; they only report who played and how it ended. The
client-side Elo implementation exists solely to *preview* a result and
must produce the same numbers as the database.

### II. Every rating point is traceable
A player's rating in a mode is that game's starting rating plus the sum of
the deltas of the results they played in that mode. Each result stores
every player's rating before it and the delta applied to them, so any
rating can be audited and the full history replayed.

### III. Secure by default (RLS everywhere)
Every table has Row Level Security enabled. Authenticated members can
read the ladder; they can only edit cosmetic fields of their own
profile. Writes to ratings and matches happen exclusively through
audited RPCs.

### IV. Test the math first
The FIDE formula, K-factors and rounding are covered by unit
tests in Dart and by SQL tests against a real Postgres before any UI
depends on them.

### V. Design is a swappable layer
Screens read colors, type, shape and leaderboard layout from a
`DesignSpec`. No screen hardcodes a color or font. Adding a design must
not require touching screen logic. Each game has its own design (chess:
Counter, light or dark with the system setting; backgammon: Baize; Star
Wars: Unlimited: Holotable).

### VI. Start narrow
Chess, backgammon and Star Wars: Unlimited are supported, each in the
modes listed in `game_modes`; every mode has its own ladder. The games
share one `ratings` table (per member, game and mode), one pair of request
and result tables with a row per player, and one pair of RPCs, told apart
by a `match_type` and a `mode`. Each game keeps its own score rules, rating
math and UI: chess FIDE, backgammon FIBS, and SWU a points table that starts
at 0 and never goes below it. In chess and backgammon a result of more than
two players averages the game's pairwise change against every opponent. No speculative
abstractions are built for games or modes that aren't played yet.

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

**Version**: 1.6.0 | **Ratified**: 2026-10-02 | **Last Amended**: 2026-10-07
