import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/formatters.dart';
import '../models/user_model.dart';

/// Circular avatar with an optional presence dot.
///
/// Falls back to initials on a colour derived from the uid, so every user has
/// a stable, distinguishable avatar without needing an uploaded photo. Deriving
/// from uid rather than name keeps the colour steady if someone renames.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.user,
    this.radius = 24,
    this.showPresence = false,
  });

  final UserModel user;
  final double radius;
  final bool showPresence;

  static const _palette = [
    Color(0xFF4F46E5),
    Color(0xFF0891B2),
    Color(0xFF7C3AED),
    Color(0xFFDB2777),
    Color(0xFFEA580C),
    Color(0xFF059669),
    Color(0xFF2563EB),
    Color(0xFFC026D3),
  ];

  Color get _color {
    if (user.uid.isEmpty) return _palette.first;
    final hash = user.uid.codeUnits.fold<int>(0, (sum, c) => sum + c);
    return _palette[hash % _palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = user.photoUrl != null && user.photoUrl!.isNotEmpty;
    final dotSize = radius * 0.5;

    return SizedBox(
      width: radius * 2,
      height: radius * 2,
      child: Stack(
        children: [
          CircleAvatar(
            radius: radius,
            backgroundColor: _color,
            backgroundImage: hasPhoto ? NetworkImage(user.photoUrl!) : null,
            child: hasPhoto
                ? null
                : Text(
                    Formatters.initials(user.name),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: radius * 0.7,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
          if (showPresence)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  color: user.isOnline ? AppColors.online : AppColors.offline,
                  shape: BoxShape.circle,
                  // Ring in the scaffold colour so the dot reads clearly
                  // against the avatar behind it, in either theme.
                  border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: dotSize * 0.18,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
