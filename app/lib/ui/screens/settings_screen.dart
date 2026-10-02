import 'package:flutter/material.dart';

import '../../data/ladder_repository.dart';
import '../../design/design_scope.dart';
import '../../design/design_spec.dart';
import '../../design/designs.dart';
import '../app_scope.dart';
import '../widgets/surface.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: context.repo.me?.displayName);
  bool _savingName = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _toast(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _saveName() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _savingName = true);
    try {
      await context.repo.updateProfile(displayName: _name.text);
      _toast('Name saved.');
    } on LadderException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _pickDesign(DesignSpec spec) async {
    try {
      await context.repo.updateProfile(design: spec.id);
    } on LadderException catch (e) {
      _toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = context.design;
    final repo = context.repo;
    final current = repo.me?.design;
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        const ScreenTitle('Settings'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Form(
            key: _form,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Display name'),
                    validator: validateDisplayName,
                    onFieldSubmitted: (_) => _saveName(),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 56,
                  child: FilledButton(
                    onPressed: _savingName ? null : _saveName,
                    child: const Text('Save name'),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 4),
          child: Text('Design', style: d.display(24)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text('Changes how the whole app looks, on every device you use.',
              style: d.body(15, color: d.muted)),
        ),
        for (final spec in designs)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: DesignOption(
              spec: spec,
              selected: spec.id == current,
              onTap: () => _pickDesign(spec),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: OutlinedButton(
            onPressed: () => repo.signOut(),
            child: const Text('Sign out'),
          ),
        ),
      ],
    );
  }
}

/// A design rendered in its own colors and type, so members can see what
/// they're picking.
class DesignOption extends StatelessWidget {
  const DesignOption({super.key, required this.spec, required this.selected, required this.onTap});

  final DesignSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = context.design;
    final radius = BorderRadius.circular(spec.pill ? 28 : spec.radius);
    return Semantics(
      selected: selected,
      button: true,
      label: '${spec.name} design. ${spec.tagline}',
      excludeSemantics: true,
      child: Material(
        color: spec.background,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: selected ? active.accent : spec.line,
            width: selected ? 3 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(spec.name, style: spec.display(24)),
                      const SizedBox(height: 4),
                      Text(spec.tagline, style: spec.body(14, color: spec.muted)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          for (final c in [spec.accent, spec.win, spec.loss, spec.surface])
                            Container(
                              width: 22,
                              height: 22,
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                color: c,
                                shape: spec.radius == 0 ? BoxShape.rectangle : BoxShape.circle,
                                border: Border.all(color: spec.line),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle, color: spec.accent, size: 28, semanticLabel: 'Selected'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
