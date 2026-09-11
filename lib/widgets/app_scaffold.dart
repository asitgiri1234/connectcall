import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/router/routes.dart';
import 'connection_banner.dart';

/// The persistent bottom-navigation shell wrapping the four main tabs.
///
/// Backed by a [StatefulNavigationShell], so each tab keeps its own
/// navigation stack and scroll position when you switch away and back.
class AppScaffold extends StatelessWidget {
  const AppScaffold({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const _destinations = <NavigationDestination>[
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home_rounded),
      label: 'Home',
    ),
    NavigationDestination(
      icon: Icon(Icons.people_outline_rounded),
      selectedIcon: Icon(Icons.people_rounded),
      label: 'Contacts',
    ),
    NavigationDestination(
      icon: Icon(Icons.history_rounded),
      selectedIcon: Icon(Icons.history_rounded),
      label: 'Calls',
    ),
    NavigationDestination(
      icon: Icon(Icons.person_outline_rounded),
      selectedIcon: Icon(Icons.person_rounded),
      label: 'Profile',
    ),
  ];

  void _onTap(int index) {
    // Tapping the already-selected tab pops that branch back to its root,
    // which is the behaviour users expect from a bottom nav.
    shell.goBranch(index, initialLocation: index == shell.currentIndex);
  }

  @override
  Widget build(BuildContext context) {
    assert(_destinations.length == Routes.shellTabs.length);
    return Scaffold(
      body: shell,
      // The offline banner sits just above the tabs rather than at the top,
      // so it never fights each screen's app bar for the status-bar area.
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ConnectionBanner(),
          NavigationBar(
            selectedIndex: shell.currentIndex,
            onDestinationSelected: _onTap,
            destinations: _destinations,
          ),
        ],
      ),
    );
  }
}
