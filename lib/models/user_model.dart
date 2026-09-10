import '../core/constants/app_constants.dart';

/// A ConnectCall user, as stored under `users/{uid}` in the Realtime Database.
///
/// Immutable. Realtime Database returns loosely typed maps, so every field is
/// parsed defensively: a missing or wrong-typed value falls back rather than
/// throwing, because a single malformed record must not break the whole
/// contacts list.
class UserModel {
  const UserModel({
    required this.uid,
    required this.name,
    required this.email,
    this.photoUrl,
    this.isOnline = false,
    this.lastSeen,
    this.createdAt,
  });

  final String uid;
  final String name;
  final String email;
  final String? photoUrl;

  /// Written by the presence system. Backed by `onDisconnect()` on the
  /// server, so it survives a crash or a dropped connection.
  final bool isOnline;
  final DateTime? lastSeen;
  final DateTime? createdAt;

  /// Builds from a Realtime Database snapshot value.
  ///
  /// [uid] comes from the node key rather than the payload, so it is always
  /// correct even if the stored record is incomplete.
  factory UserModel.fromMap(String uid, Map<Object?, Object?> map) {
    return UserModel(
      uid: uid,
      name: _asString(map['name']) ?? 'Unknown',
      email: _asString(map['email']) ?? '',
      photoUrl: _asString(map['photoUrl']),
      isOnline: map['isOnline'] == true,
      lastSeen: _asDate(map['lastSeen']),
      createdAt: _asDate(map['createdAt']),
    );
  }

  Map<String, Object?> toMap() => {
        'name': name,
        'email': email,
        'photoUrl': photoUrl,
        'isOnline': isOnline,
        'lastSeen': lastSeen?.millisecondsSinceEpoch,
        'createdAt': createdAt?.millisecondsSinceEpoch,
      };

  UserModel copyWith({
    String? name,
    String? photoUrl,
    bool? isOnline,
    DateTime? lastSeen,
  }) {
    return UserModel(
      uid: uid,
      name: name ?? this.name,
      email: email,
      photoUrl: photoUrl ?? this.photoUrl,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      createdAt: createdAt,
    );
  }

  /// Case- and diacritic-insensitive match used by contact search.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return name.toLowerCase().contains(q) || email.toLowerCase().contains(q);
  }

  static String? _asString(Object? value) {
    if (value is String && value.isNotEmpty) return value;
    return null;
  }

  static DateTime? _asDate(Object? value) {
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserModel &&
          other.uid == uid &&
          other.name == name &&
          other.email == email &&
          other.photoUrl == photoUrl &&
          other.isOnline == isOnline &&
          other.lastSeen == lastSeen;

  @override
  int get hashCode =>
      Object.hash(uid, name, email, photoUrl, isOnline, lastSeen);

  @override
  String toString() => 'UserModel($uid, $name, online: $isOnline)';
}

/// Convenience for building the database path of a user record.
extension UserModelPath on UserModel {
  String get dbPath => DbPaths.user(uid);
}
