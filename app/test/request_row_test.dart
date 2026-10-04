import 'package:awake_ladder/domain/backgammon.dart';
import 'package:awake_ladder/domain/models.dart';
import 'package:awake_ladder/domain/swu.dart';
import 'package:flutter_test/flutter_test.dart';

/// Columns every request table shares, as PostgREST returns them for a
/// declined request. Catches a column-name typo the demo path never sees.
const _declined = {
  'id': 7,
  'rated': true,
  'created_at': '2026-10-04T09:00:00+00:00',
  'status': 'declined',
  'responded_at': '2026-10-04T12:30:00+00:00',
};

final _respondedAt = DateTime.utc(2026, 10, 4, 12, 30);

void main() {
  test('a declined chess request row keeps its status and time', () {
    final r = MatchRequest.fromRow({
      ..._declined,
      'white_id': 'ana',
      'black_id': 'bo',
      'white': {'display_name': 'Ana'},
      'black': {'display_name': 'Bo'},
      'result': 'white',
      'dgt_option': 1,
      'requested_by': 'ana',
    });
    expect(r.status, RequestStatus.declined);
    expect(r.respondedAt!.isAtSameMomentAs(_respondedAt), isTrue);
    expect(r.respondedAt!.isUtc, isFalse, reason: 'shown in local time');
    expect(r.declinedFor('ana'), isTrue);
    expect(r.awaits('bo'), isFalse);
  });

  test('a declined backgammon request row keeps its status and time', () {
    final r = BackgammonMatchRequest.fromRow({
      ..._declined,
      'winner_id': 'ana',
      'loser_id': 'bo',
      'winner': {'display_name': 'Ana'},
      'loser': {'display_name': 'Bo'},
      'match_length': 5,
      'loser_score': 2,
      'requested_by': 'ana',
    });
    expect(r.status, RequestStatus.declined);
    expect(r.respondedAt!.isAtSameMomentAs(_respondedAt), isTrue);
    expect(r.declinedFor('ana'), isTrue);
    expect(r.awaits('bo'), isFalse);
  });

  test('a declined SWU request row keeps its status and time', () {
    final r = SwuMatchRequest.fromRow({
      ..._declined,
      'reporter_id': 'ana',
      'respondent_id': 'bo',
      'reporter': {'display_name': 'Ana'},
      'respondent': {'display_name': 'Bo'},
      'reporter_games': 2,
      'respondent_games': 0,
    });
    expect(r.status, RequestStatus.declined);
    expect(r.respondedAt!.isAtSameMomentAs(_respondedAt), isTrue);
    expect(r.declinedFor('ana'), isTrue);
    expect(r.awaits('bo'), isFalse);
  });

  test('a pending request row has no response time', () {
    final r = SwuMatchRequest.fromRow({
      ..._declined,
      'status': 'pending',
      'responded_at': null,
      'reporter_id': 'ana',
      'respondent_id': 'bo',
      'reporter': {'display_name': 'Ana'},
      'respondent': {'display_name': 'Bo'},
      'reporter_games': 2,
      'respondent_games': 1,
    });
    expect(r.status, RequestStatus.pending);
    expect(r.respondedAt, isNull);
    expect(r.awaits('bo'), isTrue);
  });
}
