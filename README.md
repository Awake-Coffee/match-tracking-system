# Awake Chess Ladder

Internal chess Elo ladder for Awake Coffee. Members sign in, report games
they played on the café's DGT 2500 clocks, and ratings move once the
opponent confirms the result.

- **App**: Flutter web (`app/`), single "Roast pawns" design.
- **Backend**: Supabase auth + Postgres (`supabase/migrations/`). Ratings are
  computed in database functions, so clients can't tamper with them.
- **Elo**: everyone starts at 1000, K = 32, zero-sum rounding.
  Full spec: [`specs/001-chess-elo-tracking/spec.md`](specs/001-chess-elo-tracking/spec.md).

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

## Database changes

Add a new file in `supabase/migrations/`, cover it in
`supabase/tests/chess_elo_test.sql`, run `make test`, then apply it with:

```
npx supabase db push
```

## Build

```
cd app && flutter build web --release --dart-define-from-file=../.env
```

The static site lands in `app/build/web/`.
