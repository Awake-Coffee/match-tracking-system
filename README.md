# Awake Ladder

Internal chess, backgammon and Star Wars: Unlimited ladders for Awake
Coffee. Members sign in, report games they played (chess on the café's DGT
2500 clocks, backgammon as matches to N points, SWU as best-of-three
matches), and ratings move once the opponent confirms the result. Each
game has its own rating, ladder and look; a switch at the top of every
screen moves between them.

- **App**: Flutter web (`app/`). Chess uses the "Roast pawns" design,
  backgammon "Baize", Star Wars: Unlimited "Holotable".
- **Backend**: Supabase auth + Postgres (`supabase/migrations/`). Ratings are
  computed in database functions, so clients can't tamper with them. All
  games share one schema keyed by a `match_type` enum: `ratings` (one row
  per member per game), `match_requests`, `matches`, and the
  `request_match` / `respond_to_match` RPCs.
  Full spec: [`specs/005-match-types/spec.md`](specs/005-match-types/spec.md).
- **Chess rating**: FIDE rules (expected-score table, 400-point rule, K = 40 for the
  first 30 games, then 20, 10 for good once 2400 is reached). Everyone
  starts at 1000.
  Full spec: [`specs/001-chess-elo-tracking/spec.md`](specs/001-chess-elo-tracking/spec.md).
- **Backgammon rating**: FIBS formula, which weighs match length and moves
  newcomers faster. Everyone starts at 1500.
  Full spec: [`specs/002-backgammon-ladder/spec.md`](specs/002-backgammon-ladder/spec.md).
- **Star Wars: Unlimited rating**: the chess FIDE rules on the match result
  (win, draw or loss; the game score is shown but not weighted). Everyone
  starts at 1000.
  Full spec: [`specs/003-star-wars-unlimited/spec.md`](specs/003-star-wars-unlimited/spec.md).
- **Unrated games**: switch "Rated" off when recording a friendly. It is
  confirmed and kept in history but moves no rating or record.
  Full spec: [`specs/004-unrated-games/spec.md`](specs/004-unrated-games/spec.md).

## Run locally

Requires Flutter. Put the Supabase settings in a repo-root `.env`:

```
SUPABASE_URL=https://<project-ref>.supabase.co
SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
```

Without `.env` the app runs in demo mode with an in-memory ladder.

```
make run    # release build on http://localhost:8080 (fast first load)
make dev    # debug build with hot reload
make test   # Flutter tests + SQL tests (needs Postgres binaries on PATH)
```

Sign-up confirmation emails link back to the host the member signed up on,
as long as Supabase allows it: the Site URL and Redirect URLs live in
`supabase/auth.json` and are deployed with the migrations (see below).

## Database changes

Add a new file in `supabase/migrations/`, cover it in a

`supabase/tests/*_test.sql` file and run `make test`. Merging to `main`
applies it to production.

## CI/CD

- **CI** (`.github/workflows/ci.yml`, every PR and push to `main`): Flutter
  analyze and tests, the SQL tests, and on PRs a dry run listing the
  migrations that would be applied to production.
- **Deploy Supabase** (`.github/workflows/deploy-supabase.yml`, pushes to
  `main` that touch `supabase/migrations/` or `supabase/auth.json`, or run by
  hand): runs the SQL tests, `supabase db push`, then sets the auth Site URL
  and Redirect URLs from `supabase/auth.json`.
- **App**: Vercel builds and deploys every push (see Build).

The deploy needs these repository settings (Settings → Secrets and
variables → Actions):

| Name | Kind | Value |
| --- | --- | --- |
| `SUPABASE_DB_URL` | secret | Session pooler connection string (Supabase → Connect), with the database password filled in |
| `SUPABASE_ACCESS_TOKEN` | secret | Personal access token from supabase.com/dashboard/account/tokens |
| `SUPABASE_PROJECT_REF` | variable | The `<project-ref>` in `https://<project-ref>.supabase.co` |

## Build

```
cd app && flutter build web --release --dart-define-from-file=../.env
```

The static site lands in `app/build/web/`.

Vercel builds every push with `scripts/vercel-build.sh` (see `vercel.json`),
which installs Flutter and passes the project's `SUPABASE_URL` and
`SUPABASE_PUBLISHABLE_KEY` environment variables to `flutter build`.
Production builds fail if either is missing.
