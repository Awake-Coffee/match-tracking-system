import 'package:awake_ladder/domain/backgammon.dart';
import 'package:awake_ladder/domain/models.dart';
import 'package:awake_ladder/domain/swu.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ladder_fixture.dart';

// Rows as PostgREST returns them: `ratings`, `matches` with their
// `match_players`, and `match_requests` with their `match_request_players`
// and each player's profile. Numeric scores arrive as doubles. A result keeps
// its own copy of the players' names; a request embeds their profiles.

const _ana = 'ana-id';
const _bo = 'bo-id';

Map<String, dynamic> _result(
  String matchType,
  String mode,
  List<(String, String, int, num, int, int)> players, {
  Map<String, dynamic> extra = const {},
}) => {
  'id': 7,
  'match_type': matchType,
  'mode': mode,
  'rated': true,
  'dgt_option': null,
  'custom_base_minutes': null,
  'custom_extra_seconds': null,
  'recorded_by': _ana,
  'played_at': '2026-10-05T10:00:00+00:00',
  'match_players': [
    for (final (id, name, side, score, before, delta) in players)
      {
        'match_id': 7,
        'player_id': id,
        'player_name': name,
        'side': side,
        'score': score,
        'rating_before': before,
        'rating_delta': delta,
      },
  ],
  ...extra,
};

Map<String, dynamic> _request(
  String matchType,
  String mode,
  List<(String, String, int, num, bool)> players, {
  Map<String, dynamic> extra = const {},
}) => {
  'id': 3,
  'match_type': matchType,
  'mode': mode,
  'rated': false,
  'dgt_option': null,
  'custom_base_minutes': null,
  'custom_extra_seconds': null,
  'requested_by': _bo,
  'created_at': '2026-10-05T10:00:00+00:00',
  'status': 'pending',
  'declined_by': null,
  'responded_at': null,
  'match_request_players': [
    for (final (id, name, side, score, confirmed) in players)
      {
        'request_id': 3,
        'player_id': id,
        'side': side,
        'score': score,
        'confirmed': confirmed,
        'profiles': {'display_name': name},
      },
  ],
  ...extra,
};

Map<String, dynamic> _rating(
  String matchType,
  String mode,
  int rating, {
  int exp = 0,
}) => {
  'player_id': _ana,
  'match_type': matchType,
  'mode': mode,
  'rating': rating,
  'peak_rating': rating + 10,
  'played': 3,
  'wins': 1,
  'losses': 1,
  'draws': 1,
  'experience': exp,
};

void main() {
  test('a profile reads each mode from its ratings', () {
    final player = Player.fromRow({
      'id': _ana,
      'display_name': 'Ana',
      'ratings': [
        _rating('swu', 'premier', 1040),
        _rating('swu', 'twin_suns', 990),
        _rating('chess', 'standard', 1020),
        _rating('backgammon', 'standard', 1510, exp: 8),
      ],
    });

    expect(player.chess.rating, 1020);
    expect(player.chess.peakRating, 1030);
    expect(player.chess.played, 3);
    expect(player.chess.draws, 1);
    expect(player.backgammon.rating, 1510);
    expect(player.backgammon.experience, 8);
    expect(player.swu.rating, 1040);
    expect(player.standingIn(GameMode.twinSuns).rating, 990);
    expect(player.mostPlayedIn(MatchType.swu), GameMode.premier);
  });

  test('a mode without a ratings row reads as the starting standing', () {
    final player = Player.fromRow({
      'id': _ana,
      'display_name': 'Ana',
      'ratings': [_rating('chess', 'standard', 1020)],
    });

    expect(player.backgammon.rating, backgammonStartingRating);
    expect(player.swu.rating, swuStartingRating);
    expect(player.standingIn(GameMode.chess960).rating, 1000);
    expect(player.standingIn(GameMode.chess960).played, 0);
  });

  test('chess: side 1 has white and the scores give the result', () {
    final win = GameResult.fromRow(
      _result(
        'chess',
        'chess960',
        [(_bo, 'Bo', 2, 0.0, 1100, -30), (_ana, 'Ana', 1, 1.0, 1000, 30)],
        extra: {'dgt_option': 10},
      ),
    );
    expect(win.mode, GameMode.chess960);
    expect(win.seats.first.name, 'Ana', reason: 'seats in side order');
    expect(win.colorOf(_ana), PieceColor.white);
    expect(win.outcomeFor(_ana), Outcome.win);
    expect(win.ratingAfterFor(_bo), 1070);
    expect(win.clock?.label, 'Fischer 5 min + 3 s');

    final request = ResultRequest.fromRow(
      _request(
        'chess',
        'standard',
        [(_ana, 'Ana', 1, 0.5, false), (_bo, 'Bo', 2, 0.5, true)],
        extra: {
          'dgt_option': 21,
          'custom_base_minutes': 7,
          'custom_extra_seconds': 4,
        },
      ),
    );
    expect(request.outcomeFor(_ana), Outcome.draw);
    expect(request.clock!.label, 'Fischer 7 min + 4 s');
    expect(request.rated, isFalse);
    expect(request.awaits(_ana), isTrue);
    expect(request.awaits(_bo), isFalse);
    expect(request.reporterName, 'Bo');
  });

  test('backgammon: the higher score wins and is the match length', () {
    final lost = GameResult.fromRow(
      _result('backgammon', 'nackgammon', [
        (_ana, 'Ana', 1, 1.0, 1000, -30),
        (_bo, 'Bo', 2, 3.0, 1100, 30),
      ]),
    );
    expect(lost.outcomeFor(_bo), Outcome.win);
    expect(lost.matchLength, 3);
    expect(lost.scoreFor(_ana), '1-3');
    expect(lost.scoreFor(), '3-1');
    expect(lost.deltaFor(_bo), 30);
  });

  test('twin suns: places follow the players outlasted, ties share', () {
    final result = GameResult.fromRow(
      _result('swu', 'twin_suns', [
        ('a', 'A', 1, 3.0, 1000, 20),
        ('b', 'B', 2, 2.0, 1000, 7),
        ('c', 'C', 3, 0.0, 1000, -13),
        ('d', 'D', 4, 0.0, 1000, -13),
      ]),
    );
    expect(
      [for (final s in result.seats) result.placeOf(s.playerId)],
      [1, 2, 3, 3],
    );
    expect(result.outcomeFor('a'), Outcome.win);
    expect(result.outcomeFor('b'), Outcome.loss);
    expect(result.opponentsOf('b').length, 3);
  });

  test('a request waits for every player who has not confirmed', () {
    final request = ResultRequest.fromRow(
      _request('chess', 'bughouse', [
        (_bo, 'Bo', 1, 1.0, true),
        (_ana, 'Ana', 1, 1.0, false),
        ('cy', 'Cy', 2, 0.0, true),
        ('di', 'Di', 2, 0.0, false),
      ]),
    );
    expect(request.teammatesOf(_ana).single.name, 'Bo');
    expect([for (final s in request.waitingOn) s.name], ['Ana', 'Di']);
    expect(request.awaits('cy'), isFalse);
  });

  test('a declined request row keeps its status, time and decliner', () {
    final r = ResultRequest.fromRow(
      _request(
        'swu',
        'premier',
        [(_bo, 'Bo', 1, 2.0, true), (_ana, 'Ana', 2, 0.0, false)],
        extra: {
          'status': 'declined',
          'declined_by': _ana,
          'responded_at': '2026-10-04T12:30:00+00:00',
        },
      ),
    );
    expect(r.status, RequestStatus.declined);
    expect(
      r.respondedAt!.isAtSameMomentAs(DateTime.utc(2026, 10, 4, 12, 30)),
      isTrue,
    );
    expect(r.respondedAt!.isUtc, isFalse, reason: 'shown in local time');
    expect(r.declinedBy, _ana);
    expect(r.declinedFor(_bo), isTrue);
    expect(r.awaits(_ana), isFalse);
  });
}
