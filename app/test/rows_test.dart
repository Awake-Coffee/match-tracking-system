import 'package:awake_ladder/domain/backgammon.dart';
import 'package:awake_ladder/domain/models.dart';
import 'package:awake_ladder/domain/swu.dart';
import 'package:flutter_test/flutter_test.dart';

// Rows as PostgREST returns them from the shared `matches`, `match_requests`
// and `ratings` tables: numeric scores arrive as doubles. A result keeps its
// own copy of the players' names; a request embeds their profiles.

const _ana = 'ana-id';
const _bo = 'bo-id';

Map<String, dynamic> _match(
  num player1Score,
  num player2Score, {
  Map<String, dynamic> extra = const {},
}) => {
  'id': 7,
  'player1_id': _ana,
  'player2_id': _bo,
  'player1_name': 'Ana',
  'player2_name': 'Bo',
  'player1_score': player1Score,
  'player2_score': player2Score,
  'rated': true,
  'player1_rating_before': 1000,
  'player2_rating_before': 1100,
  'player1_rating_delta': 30,
  'player2_rating_delta': -30,
  'dgt_option': null,
  'custom_base_minutes': null,
  'custom_extra_seconds': null,
  'recorded_by': _ana,
  'played_at': '2026-10-05T10:00:00+00:00',
  ...extra,
};

Map<String, dynamic> _request(num player1Score, num player2Score) => {
  'id': 3,
  'player1_id': _ana,
  'player2_id': _bo,
  'player1': {'display_name': 'Ana'},
  'player2': {'display_name': 'Bo'},
  'player1_score': player1Score,
  'player2_score': player2Score,
  'rated': false,
  'dgt_option': 21,
  'custom_base_minutes': 7,
  'custom_extra_seconds': 4,
  'requested_by': _bo,
  'created_at': '2026-10-05T10:00:00+00:00',
  'status': 'pending',
  'responded_at': null,
};

Map<String, dynamic> _rating(String matchType, int rating, {int exp = 0}) => {
  'player_id': _ana,
  'match_type': matchType,
  'rating': rating,
  'peak_rating': rating + 10,
  'played': 3,
  'wins': 1,
  'losses': 1,
  'draws': 1,
  'experience': exp,
};

void main() {
  test('a profile reads each game from its ratings', () {
    final player = Player.fromRow({
      'id': _ana,
      'display_name': 'Ana',
      'ratings': [
        _rating('swu', 1040),
        _rating('chess', 1020),
        _rating('backgammon', 1510, exp: 8),
      ],
    });

    expect(player.rating, 1020);
    expect(player.peakRating, 1030);
    expect(player.gamesPlayed, 3);
    expect(player.draws, 1);
    expect(player.backgammon.rating, 1510);
    expect(player.backgammon.experience, 8);
    expect(player.swu.rating, 1040);
    expect(player.swu.matchesPlayed, 3);
  });

  test('a game without a ratings row reads as the starting standing', () {
    final player = Player.fromRow({
      'id': _ana,
      'display_name': 'Ana',
      'ratings': [_rating('chess', 1020)],
    });

    expect(player.backgammon.rating, backgammonStartingRating);
    expect(player.swu.rating, swuStartingRating);
  });

  test('chess: player1 has white and the scores give the result', () {
    final win = ChessMatch.fromRow(_match(1.0, 0.0));
    expect(win.whiteId, _ana);
    expect(win.blackName, 'Bo');
    expect(win.result, MatchResult.white);
    expect(win.ratingAfterFor(_bo), 1070);
    expect(win.clock, isNull);

    expect(ChessMatch.fromRow(_match(0.0, 1.0)).result, MatchResult.black);
    expect(ChessMatch.fromRow(_match(0.5, 0.5)).result, MatchResult.draw);

    final request = MatchRequest.fromRow(_request(0.0, 1.0));
    expect(request.result, MatchResult.black);
    expect(request.clock.label, 'Fischer 7 min + 4 s');
    expect(request.rated, isFalse);
    expect(request.awaits(_ana), isTrue);
  });

  test('backgammon: the higher score wins and is the match length', () {
    final won = BackgammonMatch.fromRow(_match(5.0, 3.0));
    expect(won.winnerId, _ana);
    expect(won.matchLength, 5);
    expect(won.loserScore, 3);
    expect(won.deltaFor(_ana), 30);

    final lost = BackgammonMatch.fromRow(_match(1.0, 3.0));
    expect(lost.winnerId, _bo);
    expect(lost.loserName, 'Ana');
    expect(lost.scoreFor(_ana), '1-3');
    expect(lost.winnerRatingBefore, 1100);
    expect(lost.deltaFor(_bo), -30);

    final request = BackgammonMatchRequest.fromRow(_request(2.0, 7.0));
    expect(request.winnerId, _bo);
    expect(request.matchLength, 7);
    expect(request.loserScore, 2);
  });

  test('SWU: player1 reported the match', () {
    final match = SwuMatch.fromRow(_match(1.0, 2.0));
    expect(match.reporterId, _ana);
    expect(match.respondentName, 'Bo');
    expect(match.outcomeFor(_ana), Outcome.loss);
    expect(match.scoreFor(), '2-1');

    final request = SwuMatchRequest.fromRow(_request(1.0, 1.0));
    expect(request.outcomeFor(_bo), Outcome.draw);
    expect(request.awaits(_bo), isTrue);
  });
}
