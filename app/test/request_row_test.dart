import 'package:awake_ladder/domain/backgammon.dart';
import 'package:awake_ladder/domain/models.dart';
import 'package:awake_ladder/domain/swu.dart';
import 'package:flutter_test/flutter_test.dart';

/// A declined `match_requests` row as PostgREST returns it: Ana (player1)
/// reported it, Bo declined. Catches a column-name typo the demo path never
/// sees.
Map<String, dynamic> _declined(
  num player1Score,
  num player2Score, {
  int? dgtOption,
}) => {
  'id': 7,
  'player1_id': 'ana',
  'player2_id': 'bo',
  'player1': {'display_name': 'Ana'},
  'player2': {'display_name': 'Bo'},
  'player1_score': player1Score,
  'player2_score': player2Score,
  'rated': true,
  'dgt_option': dgtOption,
  'custom_base_minutes': null,
  'custom_extra_seconds': null,
  'requested_by': 'ana',
  'created_at': '2026-10-04T09:00:00+00:00',
  'status': 'declined',
  'responded_at': '2026-10-04T12:30:00+00:00',
};

final _respondedAt = DateTime.utc(2026, 10, 4, 12, 30);

void main() {
  test('a declined chess request row keeps its status and time', () {
    final r = MatchRequest.fromRow(_declined(1.0, 0.0, dgtOption: 1));
    expect(r.status, RequestStatus.declined);
    expect(r.respondedAt!.isAtSameMomentAs(_respondedAt), isTrue);
    expect(r.respondedAt!.isUtc, isFalse, reason: 'shown in local time');
    expect(r.declinedFor('ana'), isTrue);
    expect(r.awaits('bo'), isFalse);
  });

  test('a declined backgammon request row keeps its status and time', () {
    final r = BackgammonMatchRequest.fromRow(_declined(5.0, 2.0));
    expect(r.status, RequestStatus.declined);
    expect(r.respondedAt!.isAtSameMomentAs(_respondedAt), isTrue);
    expect(r.declinedFor('ana'), isTrue);
    expect(r.awaits('bo'), isFalse);
  });

  test('a declined SWU request row keeps its status and time', () {
    final r = SwuMatchRequest.fromRow(_declined(2.0, 0.0));
    expect(r.status, RequestStatus.declined);
    expect(r.respondedAt!.isAtSameMomentAs(_respondedAt), isTrue);
    expect(r.declinedFor('ana'), isTrue);
    expect(r.awaits('bo'), isFalse);
  });

  test('a pending request row has no response time', () {
    final r = SwuMatchRequest.fromRow({
      ..._declined(2.0, 1.0),
      'status': 'pending',
      'responded_at': null,
    });
    expect(r.status, RequestStatus.pending);
    expect(r.respondedAt, isNull);
    expect(r.awaits('bo'), isTrue);
  });
}
