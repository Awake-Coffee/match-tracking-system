import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';

/// The club's usual time controls, always offered as one-tap choices.
const defaultClocks = [
  ClockSetting(TimeControl.sudden5),
  ClockSetting(TimeControl.suddenCustom, customBaseMinutes: 10),
  ClockSetting(TimeControl.sudden25),
  ClockSetting(TimeControl.fischer5plus3),
  ClockSetting(
    TimeControl.fischerCustom,
    customBaseMinutes: 10,
    customExtraSeconds: 3,
  ),
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

/// The one-tap clocks: [defaultClocks], then the member's last used clock
/// when it isn't one of them. That's [last] (stored on this device, maybe
/// not confirmed yet), else the clock of their newest chess result in
/// [results] (newest first), so another device's clock still shows.
List<ClockSetting> clockChips({
  ClockSetting? last,
  required Iterable<GameResult> results,
}) => <ClockSetting>{
  ...defaultClocks,
  ?(last ?? results.map((r) => r.clock).nonNulls.firstOrNull),
}.toList();
