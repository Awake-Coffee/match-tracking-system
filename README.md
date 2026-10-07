# Awake Ladder

Internal chess, backgammon and Star Wars: Unlimited ladders for Awake
Coffee. Members sign in, report games they played (chess on the café's DGT
2500 clocks, backgammon as matches to N points, SWU as best-of-one or
best-of-three matches), and ratings move once the other players confirm the result. Each
game has its own look; a switch at the top of every screen moves between
them. Each game is played in several modes (Chess960, Bughouse, Nackgammon,
Chouette, Twin Suns, ...), and every mode has its own rating and ladder.

- **App**: Flutter web (`app/`). Chess uses the "Counter" design (the café's
  letterboard, light or dark with the system setting), backgammon "Baize",
  Star Wars: Unlimited "Holotable".
- **Installable**: the app is a PWA (`app/web/manifest.json`, `app/web/sw.js`).
  On phones a banner offers to add it to the home screen: the browser's own
  install dialog on Android, the Share-sheet steps on iPhone. Settings offers
  it again after "Not now".
- **Backend**: Supabase auth + Postgres (`supabase/migrations/`). Ratings are
  computed in database functions, so clients can't tamper with them. All
  games share one schema keyed by a `match_type` enum and a `mode`:
  `game_modes`, `ratings` (one row per member per mode played),
  `match_requests` / `match_request_players`, `matches` / `match_players`,
  and the `request_match` / `respond_to_match` RPCs.
  Full specs: [`specs/005-match-types/spec.md`](specs/005-match-types/spec.md),
  [`specs/006-game-modes/spec.md`](specs/006-game-modes/spec.md).
- **Chess rating**: FIDE rules (expected-score table, 400-point rule, K = 40 for the
  first 30 games, then 20, 10 for good once 2400 is reached). Everyone
  starts at 1000.
  Full spec: [`specs/001-chess-elo-tracking/spec.md`](specs/001-chess-elo-tracking/spec.md).
- **Backgammon rating**: FIBS formula, which weighs match length and moves
  newcomers faster. Everyone starts at 1500.
  Full spec: [`specs/002-backgammon-ladder/spec.md`](specs/002-backgammon-ladder/spec.md).
- **Star Wars: Unlimited points**: everyone starts at 0 and never drops
  below it. Premier, Eternal and Limited: a best of one is +1 for a win, -1
  for a loss; a best of three +3 / -1; a draw 0. Trilogy: +3 / -1. Twin
  Suns (3 or 4 players): first out -1, out during the final round 0,
  survived it +1, most HP at its end +2.
  Full spec: [`specs/007-swu-points/spec.md`](specs/007-swu-points/spec.md)
  (first version: [`specs/003-star-wars-unlimited/spec.md`](specs/003-star-wars-unlimited/spec.md)).
- **Game modes**: every mode is its own ladder. Bughouse (2 v 2), Chouette
  (a box against a team) and Twin Suns (3 or 4 players, scored by how each
  finished) count once every other player confirms. In chess and backgammon
  each player's change is the average of the game's two-player change
  against every opponent.
  Full spec: [`specs/006-game-modes/spec.md`](specs/006-game-modes/spec.md).
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

Chess's and backgammon's game modes (Chess960, bughouse, Nackgammon,
chouette, ...) are built but hidden from members for now: their Ladder tab
opens the standard ladder, and none of their screens offers a mode. Star
Wars: Unlimited shows its modes. Add `GAME_MODES=true` to `.env` (or to the
Vercel project's environment) to show them too. The flags live in
`app/lib/features.dart`; they hide UI only, so data and routes are unchanged.

```
make run    # release build on http://localhost:8080 (fast first load)
make dev    # debug build with hot reload
make test   # Flutter tests + SQL tests (needs Postgres binaries on PATH)
```

Sign-up confirmation and password-reset emails link back to the host the
member used: confirmations to `/`, reset links to `/reset-password`. Supabase
only allows the Site URL and Redirect URLs in `supabase/auth.json`, which are
deployed with the migrations (see below). Each host is listed with a `/**`
wildcard, which covers `/reset-password`; a host listed without one needs
`<host>/reset-password` added too.

## Database changes

Add a new file in `supabase/migrations/`, cover it in a

`supabase/tests/*_test.sql` file and run `make test`. Merging to `main`
applies it to production.

## CI/CD

All of it lives in `.github/workflows/ci.yml`:

- **Every PR and push to `main`**: Flutter analyze and tests, the SQL tests,
  and on PRs a dry run listing the migrations that would be applied to
  production. Vercel deploys a preview of every PR branch.
- **Pushes to `main`** (or run by hand), once the tests pass: builds the app
  and uploads it to Vercel without serving it, runs `supabase db push`, sets
  the auth Site URL and Redirect URLs from `supabase/auth.json`, then promotes
  the new app. The live app never runs against a schema it doesn't know, so
  Vercel's own deploys of `main` are off (`vercel.json`).

The deploy needs these repository settings (Settings → Secrets and
variables → Actions):

| Name | Kind | Value |
| --- | --- | --- |
| `SUPABASE_DB_URL` | secret | Session pooler connection string (Supabase → Connect), with the database password filled in |
| `SUPABASE_ACCESS_TOKEN` | secret | Personal access token from supabase.com/dashboard/account/tokens |
| `SUPABASE_PROJECT_REF` | variable | The `<project-ref>` in `https://<project-ref>.supabase.co` |
| `VERCEL_TOKEN` | secret | Token from vercel.com/account/tokens, scoped to the team |
| `VERCEL_ORG_ID` | variable | Team ID (`team_…`) |
| `VERCEL_PROJECT_ID` | variable | Project ID (`prj_…`) |

## Build

```
cd app && flutter build web --release --dart-define-from-file=../.env
```

The static site lands in `app/build/web/`.

Vercel previews and the production deploy both build with
`scripts/vercel-build.sh` (see `vercel.json`),
which installs Flutter and passes the project's `SUPABASE_URL` and
`SUPABASE_PUBLISHABLE_KEY` environment variables to `flutter build`.
Production builds fail if either is missing.
