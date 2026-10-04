import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';

/// The time controls offered as one-tap choices to a member with no history.
const defaultClocks = [
  ClockSetting(TimeControl.fischer5plus3),
  ClockSetting(TimeControl.fischer10plus10),
  ClockSetting(TimeControl.fischer15plus10),
  ClockSetting(TimeControl.sudden5),
];

/// The member's last used clock, in the browser (or device) they recorded on,
/// so the chess form can preselect it. Pure convenience: any storage failure
/// reads as "nothing remembered" and never blocks recording a game.
abstract final class ClockMemory {
  static String _key(String memberId) => 'last_clock.$memberId';

  static Future<ClockSetting?> last(String memberId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return _decode(prefs.getString(_key(memberId)));
    } catch (_) {
      return null;
    }
  }

  static Future<void> remember(String memberId, ClockSetting clock) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(memberId), _encode(clock));
    } catch (_) {
      // Not remembering is harmless.
    }
  }

  /// "dgt option,base minutes,extra seconds", the last two empty when unset.
  static String _encode(ClockSetting c) =>
      '${c.preset.dgtOption},${c.customBaseMinutes ?? ''},'
      '${c.customExtraSeconds ?? ''}';

  static ClockSetting? _decode(String? text) {
    final parts = text?.split(',');
    if (parts == null || parts.length != 3) return null;
    final preset = TimeControl.fromDgtOption(int.tryParse(parts[0]));
    if (preset == null) return null;
    final clock = ClockSetting(
      preset,
      customBaseMinutes: int.tryParse(parts[1]),
      customExtraSeconds: int.tryParse(parts[2]),
    );
    return clock.isComplete ? clock : null;
  }
}

/// The member's most recent distinct clocks, newest first: [last] (which may
/// not have been confirmed yet), then those of their own [matches] (newest
/// first). Falls back to [defaultClocks] with no history at all.
List<ClockSetting> recentClocks({
  ClockSetting? last,
  required Iterable<ChessMatch> matches,
  int max = 4,
}) {
  final recent = <ClockSetting>{?last, for (final m in matches) ?m.clock};
  return recent.isEmpty ? defaultClocks : recent.take(max).toList();
}
