import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

const _tabs = [
  (path: '/', label: 'Ladder', icon: Icons.format_list_numbered),
  (path: '/record', label: 'Record game', icon: Icons.add_circle_outline),
  (path: '/history', label: 'History', icon: Icons.history),
  (path: '/me', label: 'You', icon: Icons.person_outline),
];

int _tabFor(String location) {
  if (location == '/record') return 1;
  if (location == '/history') return 2;
  if (location == '/me' || location == '/settings') return 3;
  return 0;
}

/// Bottom navigation around the signed-in screens, with content capped to a
/// comfortable reading width on large screens.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: child,
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabFor(location),
        onDestinationSelected: (i) => context.go(_tabs[i].path),
        destinations: [
          for (final t in _tabs)
            NavigationDestination(icon: Icon(t.icon), label: t.label),
        ],
      ),
    );
  }
}
