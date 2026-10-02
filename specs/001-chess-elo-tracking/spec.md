# Feature Specification: Chess Elo ladder

**Feature Branch**: `001-chess-elo-tracking`
**Created**: 2026-10-02
**Status**: Implemented
**Input**: "Match tracking for Awake Coffee's tabletop games. For now it
should only support internal chess Elo: everyone starts at 1000 and the
Elo is built from the games played afterwards. Everyone has a profile
with Supabase auth. Build 5 designs."

## Clarifications

### Session 2026-10-02

- Q: Which Elo parameters? → A: Classic Elo, logistic curve with a
  400-point scale, K = 32 for everyone, starting rating 1000.
- Q: How are points rounded? → A: The winner's delta is rounded to the
  nearest integer and the loser receives exactly the negative, so the
  ladder is zero-sum and the total rating never drifts.
- Q: Who may record a match? → A: Any signed-in member, but only for a
  game they played in. They choose the opponent, the color they played
  and the result.
- Q: Can matches be edited or deleted? → A: Not in this release. A
  mistaken result is corrected by playing (or recording) a new game;
  admins can fix data directly in Supabase.
- Q: What does "5 designs" mean? → A: Five complete visual themes for the
  same app. Every member picks the one they like in Settings, and the
  choice is saved to their profile.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Join the ladder (Priority: P1)

A regular at Awake Coffee creates an account with email and password and
a display name. They land on the ladder with a rating of 1000.

**Why this priority**: Nothing else works without an identity.

**Independent Test**: Sign up, see yourself on the ladder at 1000 with
0 games.

**Acceptance Scenarios**:

1. **Given** no account, **When** I sign up with email, password and
   display name, **Then** a profile is created with rating 1000 and 0
   games.
2. **Given** an account, **When** I sign in, **Then** I see the ladder
   and my own row is highlighted.
3. **Given** I'm signed in, **When** I sign out, **Then** I return to the
   sign-in screen and ladder data is no longer visible.

### User Story 2 — Record a game (Priority: P1)

After a game at the café, one of the two players records it: opponent,
the color they played, and the result. Both ratings update at once.

**Why this priority**: This is the core loop that builds the ladder.

**Independent Test**: Two members at 1000 record a win for one; the
winner shows 1016 and the loser 984.

**Acceptance Scenarios**:

1. **Given** two players at 1000, **When** white wins, **Then** white is
   1016 and black is 984.
2. **Given** two players at 1000, **When** the game is a draw, **Then**
   both stay at 1000.
3. **Given** I pick an opponent and a result, **When** I review before
   saving, **Then** I see how many points each of us will gain or lose.
4. **Given** I'm not one of the players, **When** I try to record the
   game through the API, **Then** it is rejected.
5. **Given** I choose myself as opponent, **Then** recording is rejected.

### User Story 3 — See profiles and history (Priority: P2)

Members open any profile to see current rating, record (wins, losses,
draws), rating over time, and recent games with the points won or lost.

**Independent Test**: After three recorded games, a profile shows
3 games, a correct W/L/D split, and a rating line with 4 points
(start + 3 games).

**Acceptance Scenarios**:

1. **Given** a player with games, **When** I open their profile, **Then**
   I see rating, W/L/D, peak rating and their last games newest first.
2. **Given** the match log, **When** I open History, **Then** I see all
   recent games across the club with each player's rating change.

### User Story 4 — Choose a design (Priority: P3)

A member picks one of five designs in Settings. The whole app re-skins
immediately and the choice follows them to other devices.

**Independent Test**: Switch designs, reload, sign in on a second
browser — the same design is applied.

**Acceptance Scenarios**:

1. **Given** Settings, **When** I tap a design, **Then** the app re-skins
   without reloading.
2. **Given** I chose a design, **When** I sign in elsewhere, **Then** the
   same design loads.

### Edge Cases

- Display name already taken at sign-up → a numeric suffix is added and
  the member can rename themselves in Settings.
- Two games recorded at the same moment involving the same player →
  rows are locked in a consistent order, so both apply sequentially and
  no update is lost.
- Very lopsided pairings (e.g. 1400 vs 900) → the favorite gains at
  least 0 and at most 32; deltas are clamped by the formula itself.
- Rating going below 0 is mathematically possible only after hundreds of
  losses; no floor is applied.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Members MUST be able to sign up, sign in and sign out with
  Supabase Auth (email + password).
- **FR-002**: Every auth user MUST have exactly one profile, created
  automatically at sign-up with rating 1000.
- **FR-003**: Members MUST be able to record a chess game they played,
  specifying opponent, own color (white/black) and result
  (win/loss/draw).
- **FR-004**: The system MUST compute the rating change server-side with
  K = 32 and update both players and the match log atomically.
- **FR-005**: Rating changes MUST be zero-sum per game.
- **FR-006**: Each match MUST store both players' pre-game ratings and
  the applied delta.
- **FR-007**: The app MUST show a ladder sorted by rating (ties broken
  by more games played, then name).
- **FR-008**: The app MUST show a profile per member with rating, W/L/D,
  peak rating, rating history and recent games.
- **FR-009**: The app MUST show a club-wide match history, newest first.
- **FR-010**: Members MUST be able to change their display name and
  design; they MUST NOT be able to change ratings or counters directly.
- **FR-011**: The app MUST ship five designs and persist each member's
  choice on their profile.
- **FR-012**: The app MUST preview the rating change before a game is
  saved, using the same formula as the server.

### Key Entities

- **Profile**: one per member; display name, rating, games, wins,
  losses, draws, chosen design.
- **Match**: one chess game; white, black, result, pre-game ratings,
  delta, who recorded it and when.

## Success Criteria *(mandatory)*

- **SC-001**: A new member can sign up and appear on the ladder in under
  one minute.
- **SC-002**: Recording a game takes three choices and one confirmation.
- **SC-003**: The sum of all ratings always equals 1000 × number of
  members.
- **SC-004**: Rating previews match the saved result in 100% of games.
- **SC-005**: All five designs pass WCAG AA contrast for body text.

## Out of Scope

- Games other than chess, tournaments, pairings, clocks.
- Opponent confirmation of results, editing or deleting games.
- Provisional K-factors or rating floors.
