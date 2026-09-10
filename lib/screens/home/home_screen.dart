import 'package:flutter/material.dart';

import '../../widgets/placeholder_view.dart';

/// Screen 3. Built in Phase 2.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderView(
      title: 'Home',
      icon: Icons.home_outlined,
    );
  }
}
