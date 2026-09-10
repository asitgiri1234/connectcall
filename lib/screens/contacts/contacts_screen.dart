import 'package:flutter/material.dart';

import '../../widgets/placeholder_view.dart';

/// Screen 4. Built in Phase 2.
class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderView(
      title: 'Contacts',
      icon: Icons.people_outline_rounded,
    );
  }
}
