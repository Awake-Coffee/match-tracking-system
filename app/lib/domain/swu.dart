/// Rating every member starts with on a Star Wars: Unlimited ladder.
const swuStartingRating = 1000;

/// Whether a best of three can end with these games won: 2-0, 2-1, 1-0 when
/// time runs out, or 1-1. Mirrors `public.is_valid_score` for 'swu'.
bool isSwuScore(int gamesA, int gamesB) =>
    gamesA >= 0 &&
    gamesA <= 2 &&
    gamesB >= 0 &&
    gamesB <= 2 &&
    gamesA + gamesB >= 1 &&
    gamesA + gamesB <= 3;
