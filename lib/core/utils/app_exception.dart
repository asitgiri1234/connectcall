/// A failure already translated into something worth showing a user.
///
/// Services catch platform exceptions at their boundary and rethrow this, so
/// the UI never has to know about `FirebaseAuthException` codes or Agora error
/// enums. Screens just render [message].
class AppException implements Exception {
  const AppException(this.message, {this.code, this.isRecoverable = true});

  /// Plain-language, user-facing. No error codes, no stack traces.
  final String message;

  /// The original platform code, kept for logging and debugging only.
  final String? code;

  /// Whether retrying the same action could plausibly succeed. Drives whether
  /// the UI offers a "Try again" affordance.
  final bool isRecoverable;

  const AppException.network()
      : message = 'No internet connection. Check your network and try again.',
        code = 'network',
        isRecoverable = true;

  const AppException.unknown()
      : message = 'Something went wrong. Please try again.',
        code = 'unknown',
        isRecoverable = true;

  @override
  String toString() => 'AppException($code): $message';
}

/// Maps Firebase Authentication error codes to human sentences.
///
/// Deliberately does not distinguish "user not found" from "wrong password":
/// Firebase itself collapses these into `invalid-credential` on recent
/// versions, and separating them would let anyone probe which emails are
/// registered.
class AuthErrorMapper {
  const AuthErrorMapper._();

  static AppException map(String code, [String? fallback]) {
    switch (code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return const AppException(
          'Incorrect email or password.',
          code: 'invalid-credential',
        );
      case 'invalid-email':
        return const AppException(
          'That email address is not valid.',
          code: 'invalid-email',
        );
      case 'user-disabled':
        return const AppException(
          'This account has been disabled.',
          code: 'user-disabled',
          isRecoverable: false,
        );
      case 'email-already-in-use':
        return const AppException(
          'An account already exists with this email. Try logging in.',
          code: 'email-already-in-use',
          isRecoverable: false,
        );
      case 'weak-password':
        return const AppException(
          'Password is too weak. Use at least 6 characters.',
          code: 'weak-password',
        );
      case 'operation-not-allowed':
        return const AppException(
          'Email sign-in is not enabled for this project.',
          code: 'operation-not-allowed',
          isRecoverable: false,
        );
      case 'too-many-requests':
        return const AppException(
          'Too many attempts. Wait a moment and try again.',
          code: 'too-many-requests',
        );
      case 'network-request-failed':
        return const AppException.network();
      case 'requires-recent-login':
        return const AppException(
          'Please log in again to complete this action.',
          code: 'requires-recent-login',
        );
      default:
        return AppException(
          fallback ?? 'Could not complete that. Please try again.',
          code: code,
        );
    }
  }
}
