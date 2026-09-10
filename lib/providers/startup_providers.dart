import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import 'auth_providers.dart';

/// Completes once the splash screen has been visible for its minimum time.
///
/// Kept separate from auth so a fast session restore cannot make the splash
/// flash by in a single frame, which reads as a glitch rather than a launch.
final splashGateProvider = FutureProvider<void>((ref) async {
  await Future<void>.delayed(AppConstants.splashMinimum);
});

/// True once the app knows both where the user should go and that the splash
/// has been shown long enough. The router redirect holds on splash until this
/// flips.
final appReadyProvider = Provider<bool>((ref) {
  final auth = ref.watch(authStateProvider);
  final gate = ref.watch(splashGateProvider);
  return !auth.isLoading && !gate.isLoading;
});
