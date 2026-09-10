import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/app_exception.dart';

/// Inline error surface for forms.
///
/// Inline rather than a snackbar because a form error refers to the fields
/// directly above it and must stay visible while the user corrects them; a
/// snackbar would slide away after a few seconds.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.error, this.onRetry});

  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (error == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final exception =
        error is AppException ? error as AppException : const AppException.unknown();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.decline.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.decline.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 20, color: AppColors.decline),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              exception.message,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppColors.decline, height: 1.4),
            ),
          ),
          if (onRetry != null && exception.isRecoverable) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.decline,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }
}
