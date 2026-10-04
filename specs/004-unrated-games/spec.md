# Feature Specification: Unrated games

**Feature Branch**: `add-unrated-games`
**Created**: 2026-10-04
**Status**: Implemented
**Input**: "Create an option for unrated games"

## Clarifications

### Session 2026-10-04

- Q: Which games? → A (assumed): all three. Chess games, backgammon
  matches and SWU matches can each be recorded as unrated.
- Q: What does unrated mean? → A (assumed): a friendly. The result is
  confirmed like any other and kept in history, but nothing on either
  player's profile moves: no rating, peak, played count, wins, losses,
  draws or backgammon experience. The next rated result is rated as if the
  friendly never happened.
- Q: Who decides? → A (assumed): the reporter picks it with a "Rated"
  switch (on by default). The opponent sees "Unrated" on the pending card
  before confirming, so declining is how they disagree.
- Q: Where do unrated results show? → A (assumed): in History and on
  profiles' recent results, marked "Unrated" in place of the rating
  changes. They are left off the rating-over-time line, which has nothing
  to plot for them.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Record a friendly (Priority: P1)

After a casual game, a member records it with "Rated" off. The opponent
confirms; both ratings stay where they were and the game shows in history.

**Independent Test**: Two members at 1000 with no games; one records an
unrated win; after confirmation both are still at 1000 with 0 games, and
History lists the game as unrated.

**Acceptance Scenarios**:

1. **Given** I turn "Rated" off on the record form, **Then** the preview
   says neither rating changes.
2. **Given** I send an unrated result, **Then** the pending card on both
   sides says "Unrated".
3. **Given** my opponent confirms an unrated result, **Then** neither
   profile changes and the result is listed with "Unrated" in place of the
   rating changes.
4. Confirmation, withdraw and decline work as for rated results.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-401**: Every record form MUST offer a "Rated" switch, on by default.
- **FR-402**: Each request and result table MUST store whether the result
  is rated; results reported without saying so are rated.
- **FR-403**: Confirming an unrated result MUST store it with both
  players' current ratings and zero deltas, and MUST NOT change any
  profile column. The database MUST reject an unrated result with a
  non-zero delta.
- **FR-404**: Pending cards, History and profiles MUST mark unrated
  results; the rating line MUST only plot rated ones.

### Key Entities

- **Request / match (each game)**: gains `rated` (boolean, default true).

## Constitution impact

None. Clients still only report what happened (now including whether it
counts), ratings are still computed server-side, and principle II holds:
unrated rows carry zero deltas, so every rating still replays from history.
