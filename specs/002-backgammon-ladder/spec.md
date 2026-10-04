# Feature Specification: Backgammon ladder

**Feature Branch**: `002-backgammon-ladder`
**Created**: 2026-10-03
**Status**: Implemented
**Input**: "Add backgammon. There should be two totally different
interfaces, switchable from the same app. Give me 5 distinct designs."

## Clarifications

### Session 2026-10-03

- Q: What does "two totally different interfaces" mean? → A (assumed):
  chess keeps Roast pawns; backgammon gets its own design, its own ladder
  and its own record form. One account, one display name, two ratings.
  A switch is visible on every signed-in screen.
- Q: What does "5 distinct designs" mean? → A (assumed): five candidate
  designs for the backgammon interface, each with its own way of
  switching games. One is picked and shipped (same as 001: a single
  design per game, no picker).
- Q: Which rating system? → A (assumed): FIBS, the de facto backgammon
  standard, because it accounts for match length (a 1-point match is far
  luckier than an 11-point match). Chess keeps FIDE.
- Q: Starting rating? → A (assumed, open): 1500, the FIBS convention.
- Q: Which match lengths? → A (assumed, open): 1, 3, 5, 7, 9 and 11
  points in the app, 5 preselected; the database accepts 1 to 25.

### Session 2026-10-04

- Q: Which of the five designs? → A: Baize: a green felt table where the
  backgammon ladder is a race of board points, and the switch is the
  two halves of a folding board.
- Q: Same leaderboard for both games? → A: No. People have a different
  rating in each game, so each game has its own ladder, sorted by that
  game's rating.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Switch between chess and backgammon (Priority: P1)

A member who plays both games opens the app and moves between the chess
ladder and the backgammon ladder with one tap. Each game looks and feels
like its own app.

**Independent Test**: From the chess ladder, switch to backgammon and see
the backgammon ladder, ordered by backgammon rating.

**Acceptance Scenarios**:

1. **Given** I'm on any chess screen, **When** I tap the switch, **Then** I
   see the backgammon ladder in the backgammon design.
2. **Given** I'm on a tab (e.g. History), **When** I switch games,
   **Then** I see the same tab of the other game.
3. **Given** I'm signed in, **When** I switch games, **Then** my display
   name is the same and each ladder shows its own rating.

### User Story 2 — Record a backgammon match (Priority: P1)

After a match at the café one player records it: opponent, match length
and final score. The opponent confirms it, then both ratings update.

**Independent Test**: Two members at 1500 record a 5-point match won 5–3;
after confirmation the winner gains and the loser loses the FIBS amount.

**Acceptance Scenarios**:

1. **Given** two players at 1500 with no experience, **When** one wins a
   5-point match, **Then** the winner gains 4·√5·0.5·5 ≈ 22 points and the
   loser drops 22.
2. **Given** I pick opponent, length and score, **When** I review before
   saving, **Then** I see how many points each of us will gain or lose.
3. **Given** a final score where nobody reached the match length, **Then**
   recording is rejected.
4. The confirmation, withdraw and decline rules of 001 (scenarios 4–7)
   apply unchanged.

### User Story 3 — Backgammon profile and history (Priority: P2)

Profiles and the club history show backgammon matches with lengths,
scores and rating changes, separate from chess.

**Acceptance Scenarios**:

1. **Given** a player with backgammon matches, **When** I open their
   profile on the backgammon side, **Then** I see backgammon rating, W/L,
   peak, rating over time and recent matches newest first.
2. **Given** a player with no backgammon matches, **Then** the backgammon
   side shows them at the starting rating with 0 matches.

### Edge Cases

- Backgammon has no draws; the record form offers no draw.
- A player on one ladder only still appears on the other at the starting
  rating with 0 matches.
- Very lopsided pairings: FIBS has no cap; the favorite gains little,
  the underdog gains a lot.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-101**: The app MUST offer chess and backgammon from the same
  account, with a game switch on every signed-in screen.
- **FR-102**: Each game MUST have its own design; switching games swaps
  the whole look (colors, type, ladder layout, navigation).
- **FR-103**: Each game MUST have its own ladder, ordered by that game's
  rating (ties: more results played, then name).
- **FR-104**: Members MUST be able to record a backgammon match: opponent,
  match length and final score (winner's score equals the length). The
  opponent MUST confirm it before it is rated.
- **FR-105**: Ratings MUST be computed server-side with the FIBS formula:
  for rating difference D and match length N, the underdog's win
  probability is 1 / (10^(D·√N / 2000) + 1); the winner gains and the
  loser loses 4·√N·(1 − P(winner wins)), each times their own experience
  multiplier max(1, 5 − experience / 100), experience being the sum of
  match lengths played. Rounded half up, each player separately.
- **FR-106**: Each backgammon match MUST store both pre-match ratings and
  both deltas (constitution II).
- **FR-107**: The app MUST preview the rating change before saving, using
  the same formula as the server.
- **FR-108**: Chess ratings, matches and the chess design MUST NOT change.

### Key Entities

- **Profile**: unchanged identity; gains backgammon rating, peak,
  matches, wins, losses and experience.
- **Backgammon match request / match**: players, match length, final
  score, who recorded it and when; the rated match adds pre-match ratings
  and deltas.

## Success Criteria *(mandatory)*

- **SC-101**: Switching games takes one tap from any signed-in screen.
  Pending results of the other game are badged on the switch.
- **SC-102**: Recording a match takes three choices and one confirmation.
- **SC-103**: Previews match the saved result in 100% of matches.
- **SC-104**: Both designs pass WCAG AA contrast for body text.

## Out of Scope

- Game-by-game score entry, doubling cube history, gammon statistics.
- Running a match clock or dice in-app.
- Games other than chess and backgammon.

## Constitution impact

Principle VI is amended to "chess and backgammon" (constitution 1.2.0),
keeping the rule against speculative multi-game abstractions.
