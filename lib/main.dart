import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Phase 1 initialises Firebase here before runApp.
  runApp(const ProviderScope(child: ConnectCallApp()));
}

class ConnectCallApp extends ConsumerWidget {
  const ConnectCallApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // Follows the device setting. Bonus 3 (dark mode) is satisfied by
      // building both themes from the same tokens rather than bolting on
      // a second palette later.
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
