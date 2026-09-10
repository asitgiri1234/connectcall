import 'package:flutter/material.dart';

/// Temporary scaffold for screens not yet implemented, so routing and the
/// bottom-navigation shell can be verified before the real screens land.
/// Every usage is replaced during Phases 1, 2 and 8.
class PlaceholderView extends StatelessWidget {
  const PlaceholderView({super.key, required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 44, color: theme.colorScheme.primary),
            const SizedBox(height: 14),
            Text(title, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text('Coming in a later phase',
                style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
