import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/call_model.dart';
import '../models/user_model.dart';

/// The one entry point every call button in the app goes through.
///
/// Centralised so that starting a call behaves identically from Home,
/// Contacts or call history: the permission explanation, the controller
/// call, error messages and navigation to the call screen all live here.
/// Phase 5 fills this in; until then it says so plainly rather than doing
/// nothing when tapped.
Future<void> launchCall(
  BuildContext context,
  WidgetRef ref, {
  required UserModel callee,
  required CallType type,
}) async {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('${type.label} to ${callee.name} arrives in the next phase.'),
      duration: const Duration(seconds: 2),
    ),
  );
}
