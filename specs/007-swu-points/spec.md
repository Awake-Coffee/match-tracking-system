# Feature Specification: Star Wars: Unlimited points

**Feature Branch**: `007-swu-points`
**Created**: 2026-10-07
**Status**: Implemented
**Input**: "for swu, do this. Punctaj rule model: player starts with 0, value
cannot be below 0. Match type reporting adds value to score (initially 0).
Premier: best of 1 win +1 / loss -1, best of 3 win +3 / loss -1. Trilogy win
+3 / loss -1. Eternal same as Premier. Twin Suns, 3/4 players: 1 gets
eliminated, setting up the final round; first eliminated player -1; 1 winner,
the one with most HP at end of final round, +2; rest of players +1 if alive at
end of round, +0 if killed during final round."

## Clarifications

### Session 2026-10-07

- Q: Does SWU keep FIDE? → A: no. Every SWU ladder (one per mode, as in
  006) is a points table. Everyone starts at 0; a result adds its points.
  A rating never drops below 0: a loss at 0 stays at 0, and the stored
  change is the one applied (0), so ratings still replay from history.
- Q: Best of one or three? → A: an SWU duel now says which it was. Best of
  one ends 1-0; best of three 2-0, 2-1, 1-0 (on time) or 1-1.
- Q (assumed): a 1-1 draw? → A: 0 for both.
- Q (assumed): Limited? → A: same as Premier and Eternal.
- Q: Trilogy? → A: always a best of three, +3 / -1.
- Q: Twin Suns? → A: 3 or 4 players. Each player's finish is recorded:
  first out (-1), out during the final round (0), survived the final round
  (+1), winner, most HP at the end of the final round (+2). Exactly one
  winner and one first out. Only the winner counts a win; everyone else a
  loss.
- Q (assumed): existing SWU data? → A: re-scored with points in the order
  played. Earlier duels were best of three. Earlier Twin Suns results were
  scored by players outlasted: the sole leader is the winner, those with
  the fewest were first out, everyone else survived (the old scores can't
  tell surviving from being knocked out in the final round). Open Twin Suns
  reports that no longer fit (two players, no single winner) are dropped.

## Points

| Mode | Win | Draw | Loss |
| --- | --- | --- | --- |
| Premier, Eternal, Limited · best of one | +1 | — | -1 |
| Premier, Eternal, Limited · best of three | +3 | 0 | -1 |
| Trilogy | +3 | 0 | -1 |

| Twin Suns finish | Points | Stored score |
| --- | --- | --- |
| Winner (most HP at the end of the final round) | +2 | 3 |
| Survived the final round | +1 | 2 |
| Knocked out during the final round | 0 | 1 |
| First out | -1 | 0 |

## Requirements

- **FR-701**: SWU ratings MUST start at 0 and never go below 0.
- **FR-702**: Each SWU result MUST add its points (tables above), computed
  server-side by `public.swu_points` in `respond_to_match`.
- **FR-703**: An SWU duel request and result MUST store `best_of` (1 or 3;
  3 in Trilogy); other results store none. `invalid_result_reason` MUST
  enforce it.
- **FR-704**: The record form MUST ask best of one or three (not in
  Trilogy) and, in Twin Suns, how each player finished; the preview MUST
  match the server.
- **FR-705**: Chess and backgammon ratings MUST NOT change.
- **FR-706**: Existing SWU results MUST be re-scored in order, each player
  row keeping its rating before and applied delta (principle II), covered
  by an upgrade test.

## Constitution impact

Principle VI: SWU no longer reuses the FIDE math; it keeps its own points
table (constitution 1.6.0).
