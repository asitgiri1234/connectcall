import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import '../core/constants/app_constants.dart';
import '../firebase_options.dart';

/// Android's native full-screen incoming-call screen, used when a call
/// arrives by push while ConnectCall is in the background or closed.
///
/// While the app is open, its own in-app incoming screen is used instead; the
/// push is ignored in the foreground, so a call never rings twice.
class IncomingCallUi {
  const IncomingCallUi._();

  /// Message types sent by the server's /api/notify.
  static const incomingCall = 'incoming_call';
  static const callCancelled = 'call_cancelled';

  static Future<void> show({
    required String callId,
    required String callerName,
    required bool isVideo,
  }) {
    return FlutterCallkitIncoming.showCallkitIncoming(
      CallKitParams(
        id: callId,
        nameCaller: callerName,
        appName: AppConstants.appName,
        handle: isVideo ? 'Video call' : 'Audio call',
        type: isVideo ? 1 : 0,
        duration: AppConstants.ringTimeout.inMilliseconds,
        extra: {'callId': callId},
        missedCallNotification: const NotificationParams(
          showNotification: true,
          subtitle: 'Missed call',
          isShowCallback: false,
        ),
        android: const AndroidParams(
          isCustomNotification: true,
          isShowFullLockedScreen: true,
          backgroundColor: '#0A0F1C',
          actionColor: '#16A34A',
          textColor: '#FFFFFF',
          incomingCallNotificationChannelName: 'Incoming calls',
          missedCallNotificationChannelName: 'Missed calls',
          textAccept: 'Accept',
          textDecline: 'Decline',
        ),
      ),
    );
  }

  /// Dismisses the native screen for [callId], if it is showing.
  static Future<void> dismiss(String callId) async {
    try {
      await FlutterCallkitIncoming.endCall(callId);
    } catch (_) {
      // Nothing was showing.
    }
  }

  /// Handles a push message, in the foreground isolate or the background one.
  static Future<void> handleMessage(RemoteMessage message) async {
    final data = message.data;
    final callId = data['callId'];
    if (callId is! String || callId.isEmpty) return;

    switch (data['type']) {
      case incomingCall:
        await show(
          callId: callId,
          callerName: (data['callerName'] as String?) ?? 'Someone',
          isVideo: data['callType'] == 'video',
        );
      case callCancelled:
        await dismiss(callId);
    }
  }
}

/// Entry point Android runs, in a separate isolate, for a push that arrives
/// while the app is in the background or closed.
///
/// Top level and marked as an entry point so the release compiler keeps it:
/// nothing in the app calls it directly, the plugin does, by reference.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // A background isolate starts with nothing initialised.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('ConnectCall push: ${message.data['type']} ${message.data['callId']}');
  await IncomingCallUi.handleMessage(message);
}
