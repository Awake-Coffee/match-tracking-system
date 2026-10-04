# Feature Specification: One schema for every game

**Feature Branch**: `005-match-types`
**Created**: 2026-10-05
**Status**: Implemented
**Input**: "The database is a lil fucked at the moment, we have different
tables for different games that are pretty similar, optimize it with a
match_type"

## Clarifications

### Session 2026-10-05

- Q: What gets merged? → A (assumed): everything that was copied per game.
  The six request and result tables become `match_requests` and `matches`,
  the 18 per-game rating columns on `profiles` become one `ratings` row per
  member per game, and the six request/respond RPCs become
  `request_match` and `respond_to_match`. A `match_type` enum
  (`chess`, `backgammon`, `swu`) tells the games apart.
- Q: How is a result stored for games that score differently? → A
  (assumed): as two scores, `player1_score` and `player2_score`. The higher
  one wins and equal is a draw: chess 1-0, 0-1 or ½-½; backgammon points
  (the winner's score is the match length); SWU games won.
- Q: Who is player 1? → A: in chess, white. In backgammon and SWU, whoever
  reported the result.
- Q: What about chess-only details? → A: the DGT preset and custom time stay
  as nullable columns that only chess rows may fill.
- Q: What happens to existing data? → A: every rating, result and pending
  request carries over unchanged (same ratings, deltas, timestamps, rated
  flags). Result ids are renumbered in the order results were played.
- Q: Does the app change? → A: no visible change. Each game keeps its own
  ladder, forms, rating math and design.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-501**: The database MUST define a `match_type` enum, and each
  rating, request and result MUST carry one.
- **FR-502**: Every member MUST have one `ratings` row per match type,
  created at sign-up with that game's starting rating.
- **FR-503**: `is_valid_score(match_type, a, b)` MUST be the single rule
  for which scores can end a game, enforced on both tables and by
  `request_match`.
- **FR-504**: `respond_to_match` MUST rate a result with its game's rules
  (FIDE for chess and SWU, FIBS for backgammon) and keep the existing
  confirmation, decline, withdraw and unrated behaviour.
- **FR-505**: The migration MUST carry every existing row over unchanged,
  covered by an upgrade test that seeds the old schema.

### Key Entities

- **ratings**: (player, match_type) → rating, peak, played, wins, losses,
  draws, experience (backgammon only).
- **match_requests / matches**: match_type, player1/player2, their scores,
  rated, the chess clock, who reported it; results also store both ratings
  before and both deltas.

## Adding a game

Add a value to `match_type`, its starting rating to `starting_rating`, its
scores to `is_valid_score`, and its rating rule to `rating_change` if it
isn't FIDE. Existing members need a `ratings` row for the new type.

## Constitution impact

Principle VI is amended (1.4.0): games share one ratings table, one pair of
result tables and one pair of RPCs, keyed by `match_type`. Principles I–III
hold: ratings are still computed server-side, each result still stores both
ratings before and both deltas, and all writes still go through the RPCs.
