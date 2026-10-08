# Feature Specification: Star Wars: Unlimited ladder

**Feature Branch**: `003-star-wars-unlimited`
**Created**: 2026-10-04
**Status**: Implemented; rating replaced by points in
[007-swu-points](../007-swu-points/spec.md)
**Input**: "add star wars unlimited (the trading card game)"

## Clarifications

### Session 2026-10-04

- Q: Same shape as backgammon? → A (assumed): yes. A third game with its
  own design, ladder, record form and rating under the same account,
  reachable from the game switch on every signed-in screen.
- Q: What is one result? → A (assumed): a best-of-three match, the format
  of SWU Premier play. Players record how many games each of them won.
  Valid scores: 2-0, 2-1, 1-0 (time ran out after one game), 1-1 (draw)
  and the mirrors. 0-0 is rejected: nothing was played.
- Q: Which rating system? → A (assumed, open): the chess FIDE rules on the
  match result (win 1, draw 0.5, loss 0), with SWU's own rating, peak and
  match count. There is no official SWU rating; FIDE already handles
  draws, moves newcomers faster (K = 40 for the first 30 matches) and is
  tested, so no new rating math is introduced.
- Q: Does a 2-0 count more than a 2-1? → A (assumed): no. Only the match
  result is rated; the game score is stored and shown.
- Q: Starting rating? → A (assumed): 1000, like chess.
- Q: Which design? → A: Holotable (picked from five mocks and three
  hybrids): a briefing-room projection where the ladder is a route and the
  distance between players is their rating gap. Players at or above the
  starting rating are in the space arena; the route crosses a "Start 1000"
  line into the sand-colored ground arena. Recording is result first
  (won / draw / lost), then the game score. The game switch stays the
  shared picker, so chess and backgammon don't change.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Switch to Star Wars: Unlimited (Priority: P1)

A member opens the game switch and picks Star Wars: Unlimited; the whole
app swaps to its design, ladder and tabs.

**Independent Test**: From the chess ladder, switch to SWU and see the SWU
ladder ordered by SWU rating.

**Acceptance Scenarios**:

1. **Given** I'm on any chess or backgammon screen, **When** I pick SWU in
   the switch, **Then** I see the same tab of SWU in its design.
2. **Given** I have SWU matches waiting for me, **When** I'm in another
   game, **Then** the switch shows them as a badge.

### User Story 2 — Record a match (Priority: P1)

After a best-of-three one player records the opponent and the game score.
The opponent confirms, then both ratings move.

**Independent Test**: Two members at 1000 with no matches; one records a
2-1 win; after confirmation the winner is at 1020 and the loser at 980.

**Acceptance Scenarios**:

1. **Given** two newcomers at 1000, **When** a 2-1 win is confirmed,
   **Then** the winner gains 20 and the loser drops 20.
2. **Given** a 1-1 result, **When** it's confirmed between equal ratings,
   **Then** neither rating moves and both get a draw.
3. **Given** I pick opponent and score, **When** I review before saving,
   **Then** I see how many points each of us will gain or lose.
4. **Given** 0-0, 2-2, 3-0 or any score above two games, **Then**
   recording is rejected.
5. The confirmation, withdraw and decline rules of 001 apply unchanged.

### User Story 3 — Profile and history (Priority: P2)

Profiles and the club history show SWU matches with game scores and
rating changes, separate from chess and backgammon.

**Acceptance Scenarios**:

1. **Given** a player with SWU matches, **When** I open their profile on
   the SWU side, **Then** I see SWU rating, W/L/D, peak, rating over time
   and recent matches newest first.
2. **Given** a player without SWU matches, **Then** they show at 1000 with
   0 matches.

### Edge Cases

- A draw needs equal games won (1-1); 1-0 is a win.
- A player on other ladders only still appears on the SWU ladder at 1000
  with 0 matches.

## Requirements *(mandatory)*

- **FR-201**: SWU MUST be reachable from the game switch with its own
  design, ladder, record form, history and profile pages under `/swu`.
- **FR-202**: The SWU ladder MUST be ordered by SWU rating (ties: more
  matches played, then name).
- **FR-203**: Members MUST be able to record a match: opponent, games they
  won and games the opponent won (each 0-2, one to three games in total).
  The opponent MUST confirm before it's rated.
- **FR-204**: Ratings MUST be computed server-side with
  `public.fide_rating_change` on the match result, using the SWU rating,
  matches played and peak of each player.
- **FR-205**: Each SWU match MUST store both pre-match ratings and both
  deltas (constitution II).
- **FR-206**: The app MUST preview the rating change before saving with
  the same formula as the server.
- **FR-207**: Chess and backgammon ratings, matches and designs MUST NOT
  change.

### Key Entities

- **Profile**: gains SWU rating, peak, matches, wins, losses and draws.
- **SWU match request / match**: the reporter, the respondent (who
  confirms), games each won, when; the rated match adds pre-match ratings
  and deltas.

## Success Criteria *(mandatory)*

- **SC-201**: Recording a match takes two choices and one confirmation.
- **SC-202**: Previews match the saved result in 100% of matches.
- **SC-203**: The SWU design passes WCAG AA contrast for body text.

## Out of Scope

- Leaders, bases and aspects played (a per-leader win rate is the obvious
  follow-up once members ask for it).
- Twin Suns and other multiplayer formats.
- Weighting best-of-one or 2-0 results differently.

## Constitution impact

Principle VI becomes "chess, backgammon and Star Wars: Unlimited"
(constitution 1.3.0). The FIDE math is shared as a pure function; tables
and RPCs stay per game.
