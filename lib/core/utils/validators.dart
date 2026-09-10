/// Form validators returning `null` when valid and a user-facing message
/// otherwise, matching the contract `TextFormField.validator` expects.
///
/// Kept as pure functions so form rules are testable without pumping widgets.
class Validators {
  const Validators._();

  static final RegExp _email = RegExp(
    r'^[\w.!#$%&*+/=?^`{|}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+$',
  );

  static String? name(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Name is required';
    if (v.length < 2) return 'Name is too short';
    if (v.length > 50) return 'Name must be under 50 characters';
    return null;
  }

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Email is required';
    if (!_email.hasMatch(v)) return 'Enter a valid email address';
    return null;
  }

  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Password is required';
    // Firebase rejects anything shorter than 6, so catch it client-side
    // rather than round-tripping to get an error back.
    if (v.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  /// Login only checks presence: an existing account may predate any rule
  /// change, and telling someone their saved password is "too short" at the
  /// login screen is confusing.
  static String? loginPassword(String? value) {
    if ((value ?? '').isEmpty) return 'Password is required';
    return null;
  }

  static String? confirmPassword(String? value, String original) {
    if ((value ?? '').isEmpty) return 'Confirm your password';
    if (value != original) return 'Passwords do not match';
    return null;
  }
}
