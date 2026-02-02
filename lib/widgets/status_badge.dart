import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class StatusBadge extends StatelessWidget {
  final String label;
  final StatusType type;
  final bool showIcon;
  final double? fontSize;

  const StatusBadge({
    super.key,
    required this.label,
    required this.type,
    this.showIcon = true,
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    Color backgroundColor;
    Color textColor;
    IconData? icon;

    if (isDark) {
      switch (type) {
        case StatusType.success:
        case StatusType.completed:
        case StatusType.present:
        case StatusType.available:
          backgroundColor = AppColors.badgeSuccess;
          textColor = AppColors.success;
          icon = Icons.check_circle;
          break;
        case StatusType.warning:
        case StatusType.pending:
        case StatusType.halfDay:
        case StatusType.low:
          backgroundColor = AppColors.badgeWarning;
          textColor = AppColors.warning;
          icon = Icons.warning_amber_rounded;
          break;
        case StatusType.error:
        case StatusType.failed:
        case StatusType.absent:
        case StatusType.critical:
          backgroundColor = AppColors.badgeError;
          textColor = AppColors.error;
          icon = Icons.cancel;
          break;
        case StatusType.info:
        case StatusType.processing:
          backgroundColor = AppColors.badgeInfo;
          textColor = AppColors.info;
          icon = Icons.info;
          break;
        case StatusType.neutral:
          backgroundColor = AppColors.darkSurfaceVariant;
          textColor = AppColors.textSecondary;
          icon = Icons.circle;
      }
    } else {
      // Light theme colors
      switch (type) {
        case StatusType.success:
        case StatusType.completed:
        case StatusType.present:
        case StatusType.available:
          backgroundColor = AppColors.lightBadgeSuccess;
          textColor = AppColors.lightBadgeTextSuccess;
          icon = Icons.check_circle;
          break;
        case StatusType.warning:
        case StatusType.pending:
        case StatusType.halfDay:
        case StatusType.low:
          backgroundColor = AppColors.lightBadgeWarning;
          textColor = AppColors.lightBadgeTextWarning;
          icon = Icons.warning_amber_rounded;
          break;
        case StatusType.error:
        case StatusType.failed:
        case StatusType.absent:
        case StatusType.critical:
          backgroundColor = AppColors.lightBadgeError;
          textColor = AppColors.lightBadgeTextError;
          icon = Icons.cancel;
          break;
        case StatusType.info:
        case StatusType.processing:
          backgroundColor = AppColors.lightBadgeInfo;
          textColor = AppColors.lightBadgeTextInfo;
          icon = Icons.info;
          break;
        case StatusType.neutral:
          backgroundColor = AppColors.lightBadgeNeutral;
          textColor = AppColors.lightBadgeTextNeutral;
          icon = Icons.circle;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon) ...[
            Icon(
              icon,
              size: (fontSize ?? 12) + 2,
              color: textColor,
            ),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize ?? 12,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

enum StatusType {
  success,
  warning,
  error,
  info,
  neutral,
  completed,
  pending,
  failed,
  processing,
  present,
  absent,
  halfDay,
  available,
  low,
  critical,
}
