import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/auth_providers.dart';
import '../../providers/startup_providers.dart';
import '../../screens/auth/login_screen.dart';
import '../../screens/auth/register_screen.dart';
import '../../screens/contacts/contacts_screen.dart';
import '../../screens/history/history_screen.dart';
import '../../screens/home/home_screen.dart';
import '../../screens/profile/profile_screen.dart';
import '../../screens/splash/splash_screen.dart';
import '../../widgets/app_scaffold.dart';
import 'routes.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Routes reachable while signed out.
const _publicRoutes = {Routes.splash, Routes.login, Routes.register};

/// The app router, with auth-gated redirection.
///
/// Every "where should this user be" decision lives in the [GoRouter.redirect]
/// below, so no screen has to check auth for itself and there is exactly one
/// place to reason about the signed-in / signed-out boundary.
final routerProvider = Provider<GoRouter>((ref) {
  // GoRouter needs a Listenable to know when to re-run its redirect. This
  // bridges the Riverpod providers the redirect depends on to that API: the
  // counter value is meaningless, the notification is the point.
  final refresh = ValueNotifier<int>(0);
  ref.onDispose(refresh.dispose);
  ref.listen<AsyncValue<User?>>(
    authStateProvider,
    (_, next) => refresh.value++,
    fireImmediately: true,
  );
  ref.listen<bool>(
    appReadyProvider,
    (_, next) => refresh.value++,
    fireImmediately: true,
  );

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    debugLogDiagnostics: true,
    redirect: (context, state) {
      final auth = ref.read(authStateProvider);
      final location = state.matchedLocation;

      // Firebase restores a persisted session asynchronously, and the splash
      // has a minimum display time. Until both settle we do not know where
      // this user belongs, so hold on splash rather than guessing signed-out
      // and bouncing a returning user through the login screen.
      if (!ref.read(appReadyProvider)) {
        return location == Routes.splash ? null : Routes.splash;
      }

      final signedIn = auth.value != null;
      final onPublicRoute = _publicRoutes.contains(location);

      if (!signedIn) {
        // Splash has finished and there is no session: send them to login.
        return onPublicRoute && location != Routes.splash ? null : Routes.login;
      }

      // Signed in, but sitting on splash or an auth form: move them into
      // the app. This is what makes a successful login navigate.
      if (onPublicRoute) return Routes.home;

      return null;
    },
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: Routes.register,
        builder: (context, state) => const RegisterScreen(),
      ),

      // The four tabs live in a stateful shell so each keeps its own stack.
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppScaffold(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.home,
              builder: (context, state) => const HomeScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.contacts,
              builder: (context, state) => const ContactsScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.history,
              builder: (context, state) => const HistoryScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.profile,
              builder: (context, state) => const ProfileScreen(),
            ),
          ]),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48),
              const SizedBox(height: 12),
              Text(
                'Page not found',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                state.uri.toString(),
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => context.go(Routes.home),
                child: const Text('Go home'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
});
