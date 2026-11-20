import 'package:flutter/material.dart';
import 'package:vaquita_mx/l10n/app_localizations.dart';

class GroupStorageBadge extends StatelessWidget {
  const GroupStorageBadge({
    required this.serverBacked,
    super.key,
  });

  final bool serverBacked;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final color = serverBacked ? colors.primary : colors.secondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            serverBacked ? Icons.cloud_done_outlined : Icons.phone_android,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            serverBacked ? l10n.groupStoredOnServer : l10n.groupStoredLocally,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}
