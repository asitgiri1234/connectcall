import 'package:flutter/material.dart';

import '../../widgets/placeholder_view.dart';

/// Screen 9. Built in Phase 8.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderView(
      title: 'Calls',
      icon: Icons.history_rounded,
    );
  }
}
