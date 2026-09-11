import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/connectivity_providers.dart';

/// A strip that appears when the app has lost its connection to Firebase.
///
/// Driven by `.info/connected`, the Realtime Database's own view of its
/// socket, so it reflects whether calls can actually work rather than whether
/// Wi-Fi happens to be switched on.
///
/// It waits for two seconds of continuous disconnection before appearing.
/// `.info/connected` reports false for a moment on every cold start while the
/// socket opens, and a banner that flashes on each launch would teach users to
/// ignore it.
class ConnectionBanner extends ConsumerStatefulWidget {
  const ConnectionBanner({super.key});

  static const _grace = Duration(seconds: 2);

  @override
  ConsumerState<ConnectionBanner> createState() => _ConnectionBannerState();
}

class _ConnectionBannerState extends ConsumerState<ConnectionBanner> {
  Timer? _graceTimer;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual<AsyncValue<bool>>(
      firebaseConnectedProvider,
      (previous, next) => _onConnectionChanged(next.value),
      fireImmediately: true,
    );
  }

  void _onConnectionChanged(bool? connected) {
    if (connected == false) {
      _graceTimer ??= Timer(ConnectionBanner._grace, () {
        if (mounted) setState(() => _offline = true);
      });
    } else {
      _graceTimer?.cancel();
      _graceTimer = null;
      if (_offline && mounted) setState(() => _offline = false);
    }
  }

  @override
  void dispose() {
    _graceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: !_offline
          ? const SizedBox(width: double.infinity)
          : Semantics(
              // Announced by screen readers as soon as it appears.
              liveRegion: true,
              child: Material(
                color: scheme.inverseSurface,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      Icon(Icons.cloud_off_rounded,
                          size: 18, color: scheme.onInverseSurface),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'You are offline. Calling will work again once you '
                          'reconnect.',
                          style: TextStyle(
                            color: scheme.onInverseSurface,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
