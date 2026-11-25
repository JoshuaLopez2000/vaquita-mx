part of '../app.dart';

class _GroupCard extends StatelessWidget {
  const _GroupCard({
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
    final balanceColor = balance > 0
        ? vColors.positive
        : balance < 0
            ? vColors.negative
            : colors.onSurfaceVariant;
    final balanceIcon = balance > 0
        ? Icons.south_west_rounded
        : balance < 0
            ? Icons.north_east_rounded
            : Icons.check_rounded;
    final balanceLabel = balance > 0
        ? l10n.groupBalanceOwed
        : balance < 0
            ? l10n.groupBalanceYouOwe
            : l10n.groupBalanceSettled;

    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final compact = textScale > 1.25;

    return Card(
      child: Semantics(
        button: true,
        child: InkWell(
          key: Key('group-${group.id}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: EdgeInsets.all(compact ? 14 : 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ExcludeSemantics(
                  child: Container(
                    width: compact ? 44 : 54,
                    height: compact ? 44 : 54,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(compact ? 14 : 16),
                    ),
                    child: Text(
                      group.emoji,
                      style: TextStyle(fontSize: compact ? 22 : 26),
                    ),
                  ),
                ),
                SizedBox(width: compact ? 10 : 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            group.visibility == 'shared'
                                ? Icons.groups_outlined
                                : Icons.lock_outline_rounded,
                            size: 13,
                            color: colors.secondary,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              group.visibility == 'shared'
                                  ? l10n.sharedGroup
                                  : l10n.personalGroup,
                              key: Key('group-visibility-${group.id}'),
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colors.secondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        l10n.groupSummary(
                          group.members.length,
                          group.expenses.length,
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 7),
                      GroupStorageBadge(
                        key: Key('group-storage-${group.id}'),
                        serverBacked: serverBacked,
                        pendingCount: pendingCount,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: compact ? 92 : 120),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          formatMoney(balance.abs()),
                          style: VaquitaTheme.money(
                            theme.textTheme.titleMedium,
                            color: balanceColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(balanceIcon, size: 12, color: balanceColor),
                            const SizedBox(width: 3),
                            Text(
                              balanceLabel,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: balanceColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
