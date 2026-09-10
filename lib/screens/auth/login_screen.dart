import 'package:flutter/material.dart';

import '../../widgets/placeholder_view.dart';

/// Screen 2a. Built in Phase 1.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderView(
      title: 'Login',
      icon: Icons.lock_outline_rounded,
    );
  }
}
