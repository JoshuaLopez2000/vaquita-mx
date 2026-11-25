part of '../group_detail_screen.dart';

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.group,
    required this.serverBacked,
    required this.balance,
    required this.onTap,
    this.pendingCount = 0,
  });

  final ExpenseGroup group;
  final bool serverBacked;
  final int pendingCount;
  final int balance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final vColors = VaquitaColors.of(context);
    final amountTone = balance < 0 ? vColors.negative : vColors.positive;
    return Material(
      color: colors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: vColors.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: true,
        child: InkWell(
          key: const Key('group-balance-card'),
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      group.emoji,
                      style: const TextStyle(fontSize: 34),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          Container(
                            key: const Key('group-visibility-label'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: colors.secondaryContainer,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  group.visibility == 'shared'
                                      ? Icons.groups_outlined
                                      : Icons.lock_outline_rounded,
                                  size: 13,
                                  color: colors.onSecondaryContainer,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    group.visibility == 'shared'
                                        ? l10n.sharedGroup
                                        : l10n.personalGroup,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colors.onSecondaryContainer,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          GroupStorageBadge(
                            key: Key('group-storage-${group.id}'),
                            serverBacked: serverBacked,
                            pendingCount: pendingCount,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        balance >= 0
                            ? l10n.yourGroupBalance
                            : l10n.youCurrentlyOwe,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          formatMoney(balance.abs()),
                          style: VaquitaTheme.money(
                            theme.textTheme.headlineSmall,
                            color: balance == 0 ? colors.onSurface : amountTone,
                            weight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Tooltip(
                  message: l10n.viewPendingPayments,
                  child: Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
