import 'package:flutter/material.dart';

import '../../widgets/placeholder_view.dart';

/// Screen 5. Built in Phase 2.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderView(
      title: 'Profile',
      icon: Icons.person_outline_rounded,
    );
  }
}
