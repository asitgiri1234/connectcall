import 'package:flutter/material.dart';

import '../../widgets/placeholder_view.dart';

/// Screen 2b. Built in Phase 1.
class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderView(
      title: 'Register',
      icon: Icons.person_add_alt_1_outlined,
    );
  }
}
