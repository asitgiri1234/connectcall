import 'package:permission_handler/permission_handler.dart';

import '../models/call_model.dart';

/// The three outcomes the brief asks the app to handle distinctly.
enum PermissionOutcome {
  /// Everything needed for this call type is allowed.
  granted,

  /// Refused this time. Asking again is allowed, so the UI can simply explain
  /// why and let the user retry.
  denied,

  /// Refused with "don't ask again", or blocked by device policy. The system
  /// dialog will not appear again, so the only way forward is the app's
  /// settings page. Re-requesting here would silently do nothing, which is
  /// the bug this distinction exists to avoid.
  permanentlyDenied,
}

/// Which capture permission is missing, so the message can name it.
enum CallPermission { microphone, camera }

class PermissionCheck {
  const PermissionCheck(this.outcome, this.missing);

  final PermissionOutcome outcome;
  final List<CallPermission> missing;

  bool get isGranted => outcome == PermissionOutcome.granted;

  /// A sentence naming exactly what is missing and what to do about it.
  String get message {
    final what = switch (missing) {
      [CallPermission.microphone] => 'Microphone access',
      [CallPermission.camera] => 'Camera access',
      _ => 'Microphone and camera access',
    };
    final purpose = missing.contains(CallPermission.camera)
        ? 'for video calls'
        : 'to make and receive calls';

    return switch (outcome) {
      PermissionOutcome.granted => '',
      PermissionOutcome.denied => '$what is needed $purpose.',
      PermissionOutcome.permanentlyDenied =>
        '$what is turned off for ConnectCall. Enable it in Settings '
            '$purpose.',
    };
  }
}

/// Runtime permissions for calls.
///
/// Permissions are requested at the moment a call starts or is answered,
/// never at app launch. Asking in context, when the user has just tapped a
/// call button, is far more likely to be granted, and the brief requires the
/// microphone to be requested before audio calls and the camera before video.
///
/// Plain Dart with no widget dependency: the dialog that explains a refusal
/// lives in the UI layer and just reads [PermissionCheck.message].
class PermissionService {
  const PermissionService();

  /// Checks and, where allowed, requests what [type] needs.
  ///
  /// Audio calls need only the microphone. Video calls need both, and are
  /// requested together so the user sees one decision rather than two
  /// back-to-back prompts.
  Future<PermissionCheck> ensureForCall(CallType type) async {
    final needed = <CallPermission, Permission>{
      CallPermission.microphone: Permission.microphone,
      if (type == CallType.video) CallPermission.camera: Permission.camera,
    };

    final statuses = await needed.values.toList().request();

    final missing = <CallPermission>[];
    var permanent = false;
    needed.forEach((key, permission) {
      final status = statuses[permission] ?? PermissionStatus.denied;
      if (status.isGranted || status.isLimited) return;
      missing.add(key);
      // Restricted means a device policy (parental controls, MDM) blocks it:
      // like a permanent denial, only the system can change it.
      if (status.isPermanentlyDenied || status.isRestricted) permanent = true;
    });

    if (missing.isEmpty) {
      return const PermissionCheck(PermissionOutcome.granted, []);
    }
    return PermissionCheck(
      permanent ? PermissionOutcome.permanentlyDenied : PermissionOutcome.denied,
      missing,
    );
  }

  /// Opens this app's page in system settings. Returns false if the device
  /// could not open it.
  Future<bool> openSettings() => openAppSettings();
}
