# Feature Specification: Game modes

**Feature Branch**: `feat/game-modes`
**Created**: 2026-10-05
**Status**: Implemented
**Input**: "lets add multiple gamemodes for each, chess has 960 king of the
hill etc, swu has the 1v1 1v1v1v1 or others im not sure, explore different
game modes for each and add them"

## Clarifications

### Session 2026-10-05

- Q: Does a mode share its game's rating? → A: no. Every mode is its own
  ladder with its own rating, like Lichess.
- Q: Multiplayer modes now or later? → A: now: Twin Suns (free-for-all),
  Bughouse (2v2) and Chouette (box against a team).
- Q: Screens? → A (picked from mocks): the record form picks the mode
  from a menu with its rules and the member's rating there; a game's Ladder
  tab lists its modes as cards (the member's modes first) and each card
  opens that mode's ladder; multiplayer results show who has confirmed;
  history labels each result with its mode.
- Q (assumed): who has to confirm a multiplayer result? → A: every other
  player; one decline declines it. Nobody's rating moves without their
  consent, as with duels.
- Q (assumed): how is a free-for-all scored? → A: by finishing order. A
  player's score is how many players they outlasted, so players knocked out
  together tie.

## Modes

| Game | Modes | Format |
| --- | --- | --- |
| Chess | Standard, Chess960, King of the Hill, Three-check, Crazyhouse, Atomic, Antichess, Horde, Racing Kings | duel |
| Chess | Bughouse | teams (2 v 2) |
| Backgammon | Standard, Nackgammon, Hypergammon, Acey-deucey, Tavli, Long Nardy | duel |
| Backgammon | Chouette | box (1) v team (2 to 5) |
| SWU | Premier, Eternal, Trilogy, Limited | duel |
| SWU | Twin Suns | free-for-all (2 to 4) |

Scores keep each game's rules: chess 1, 0 or ½; backgammon points to N (the
winner's score is the match length); SWU games won in a best of three.
Every chess mode is played on a DGT 2500 clock. Colours are kept for chess
duels only (side 1 has white).

## Requirements

- **FR-601**: `game_modes` MUST list every mode and its format; ratings,
  requests and results MUST name one.
- **FR-602**: A member MUST have a separate rating per mode, starting at
  the game's starting rating with their first result in it.
- **FR-603**: A result MUST list its players with a side and a score;
  teammates share a score. `invalid_result_reason` MUST be the single rule
  for which results each format accepts, enforced by `request_match`.
- **FR-604**: A player's rating change MUST be the average of the game's
  pairwise change (FIDE, or FIBS for backgammon) against every player on
  another side. For two players this is exactly the duel rule.
- **FR-605**: A result MUST count only once every other player has
  confirmed; one decline declines it and tells the reporter who declined.
- **FR-606**: Existing ratings, results and requests MUST carry over
  unchanged into each game's original mode (Standard; Premier for SWU),
  covered by an upgrade test.

## Key Entities

- **game_modes**: (match_type, mode) → format.
- **ratings**: (player, match_type, mode) → rating, peak, played, wins,
  losses, draws, experience (backgammon). Only the winner of a free-for-all
  wins; everyone else loses.
- **matches + match_players**: the result (mode, rated, clock, who
  reported it) and one row per player: side, score, rating before, delta,
  and a copy of their name.
- **match_requests + match_request_players**: the report (status,
  declined_by) and one row per player: side, score, confirmed.

## Adding a mode

Insert it into `game_modes` and add it to `GameMode` in
`app/lib/domain/modes.dart`. A new format also needs its rule in
`invalid_result_reason` (SQL and Dart) and a record form.

## Constitution impact

Principles II and VI are amended (1.5.0): each player row of a result
stores that player's rating before and delta, and the games are played in
modes, each with its own ladder, with results of two or more players.
