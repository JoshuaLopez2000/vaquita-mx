import 'package:flutter/material.dart';
import 'package:vaquita_mx/l10n/app_localizations.dart';
import 'package:vaquita_mx/src/theme/vaquita_theme.dart';

class GroupStorageBadge extends StatelessWidget {
  const GroupStorageBadge({
    required this.serverBacked,
    this.pendingCount = 0,
    super.key,
  });

  final bool serverBacked;
  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final vColors = VaquitaColors.of(context);
    final fgColor = serverBacked ? colors.primary : colors.onSecondaryContainer;
    final bgColor = serverBacked
        ? colors.primaryContainer.withValues(alpha: 0.7)
        : colors.secondaryContainer.withValues(alpha: 0.85);
    final storageBadge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            serverBacked ? Icons.cloud_done_outlined : Icons.phone_android,
            size: 13,
            color: fgColor,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              serverBacked ? l10n.groupStoredOnServer : l10n.groupStoredLocally,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: fgColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (pendingCount <= 0) return storageBadge;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        storageBadge,
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: vColors.warningContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_upload_outlined,
                size: 13,
                color: vColors.onWarningContainer,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  l10n.pendingSyncCount(pendingCount),
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: vColors.onWarningContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
