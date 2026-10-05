import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/clock_memory.dart';
import '../../domain/models.dart';

/// The DGT 2500 time control a chess game was played on: the usual clocks
/// and the member's last one as one-tap chips (that one preselected), every
/// preset in a menu, and the time the players set for a custom preset.
/// Reports the chosen preset, and the setting once it's complete (null until
/// then).
class ClockPicker extends StatefulWidget {
  const ClockPicker({
    super.key,
    required this.meId,
    required this.ownGames,
    required this.onChanged,
  });

  final String meId;

  /// The member's own games, newest first.
  final List<GameResult> ownGames;
  final void Function(TimeControl? preset, ClockSetting? clock) onChanged;

  @override
  State<ClockPicker> createState() => _ClockPickerState();
}

class _ClockPickerState extends State<ClockPicker> {
  TimeControl? _timeControl;
  int? _customBaseMinutes;
  int? _customExtraSeconds;

  late List<ClockSetting> _chips = clockChips(results: widget.ownGames);
  bool _showAllClocks = false;

  /// Bumped when a chip sets the clock, so the full list re-reads it.
  int _clockEpoch = 0;

  @override
  void initState() {
    super.initState();
    _loadLastClock();
  }

  /// Preselects the member's last clock, and gives it a chip,
  /// as soon as local storage has it.
  Future<void> _loadLastClock() async {
    final last = await ClockMemory.last(widget.meId);
    if (!mounted || last == null) return;
    _update(() {
      // A choice made while this loaded wins, and keeps its chip.
      _chips = clockChips(last: _clock ?? last, results: widget.ownGames);
      if (_timeControl == null) _choose(last);
    });
  }

  /// Applies [change] and tells the form what is chosen now.
  void _update(VoidCallback change) {
    setState(change);
    widget.onChanged(_timeControl, _clock);
  }

  void _choose(ClockSetting clock) {
    _timeControl = clock.preset;
    _customBaseMinutes = clock.customBaseMinutes;
    _customExtraSeconds = clock.customExtraSeconds;
    _clockEpoch++;
  }

  /// The chosen time control, or null until it (and any custom time) is set.
  ClockSetting? get _clock {
    final preset = _timeControl;
    if (preset == null) return null;
    final clock = preset.custom
        ? ClockSetting(
            preset,
            customBaseMinutes: _customBaseMinutes,
            customExtraSeconds: preset.extraName == null
                ? null
                : _customExtraSeconds,
          )
        : ClockSetting(preset);
    return clock.isComplete ? clock : null;
  }

  @override
  Widget build(BuildContext context) {
    final clock = _clock;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in _chips)
              ChoiceChip(
                label: Text(c.label),
                selected: c == clock,
                onSelected: (_) => _update(() => _choose(c)),
              ),
            ChoiceChip(
              label: const Text('More…'),
              selected: _showAllClocks,
              onSelected: (v) => setState(() => _showAllClocks = v),
            ),
          ],
        ),
        // The full list also stays open while the choice has no chip, so the
        // clock that will be sent (or the preset its custom time belongs to)
        // is always on screen.
        if (_showAllClocks ||
            (_timeControl != null && !_chips.contains(clock))) ...[
          const SizedBox(height: 12),
          DropdownMenu<TimeControl>(
            key: ValueKey(_clockEpoch),
            initialSelection: _timeControl,
            expandedInsets: EdgeInsets.zero,
            hintText: 'All DGT 2500 presets',
            menuHeight: 360,
            onSelected: (t) => _update(() {
              _timeControl = t;
              _customBaseMinutes = null;
              _customExtraSeconds = null;
            }),
            dropdownMenuEntries: [
              for (final t in TimeControl.values)
                DropdownMenuEntry(
                  value: t,
                  label: t.label,
                  trailingIcon: Text('${t.dgtOption}'),
                ),
            ],
          ),
        ],
        if (_timeControl case final preset? when preset.custom) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _NumberField(
                  label: 'Minutes each',
                  value: _customBaseMinutes,
                  onChanged: (v) => _update(() => _customBaseMinutes = v),
                ),
              ),
              if (preset.extraName case final extraName?) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: _NumberField(
                    label: '$extraName (s)',
                    value: _customExtraSeconds,
                    onChanged: (v) => _update(() => _customExtraSeconds = v),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

/// A whole-number input for the custom time on the clock. Follows [value]
/// when a chip sets it from outside.
class _NumberField extends StatefulWidget {
  const _NumberField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final _controller = TextEditingController(
    text: widget.value?.toString(),
  );

  @override
  void didUpdateWidget(_NumberField old) {
    super.didUpdateWidget(old);
    if (widget.value != int.tryParse(_controller.text)) {
      _controller.text = widget.value?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    decoration: InputDecoration(labelText: widget.label),
    keyboardType: TextInputType.number,
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(3),
    ],
    onChanged: (text) => widget.onChanged(int.tryParse(text)),
  );
}
