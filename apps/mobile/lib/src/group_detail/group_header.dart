part of '../group_detail_screen.dart';

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.group,
    required this.serverBacked,
    required this.balance,
    required this.onTap,
  });

  final ExpenseGroup group;
  final bool serverBacked;
  final int balance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.primaryContainer,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        key: const Key('group-balance-card'),
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            Text(group.emoji, style: const TextStyle(fontSize: 42)),
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
                            horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: colors.surface.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              group.visibility == 'shared'
                                  ? Icons.groups_outlined
                                  : Icons.lock_outline_rounded,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              group.visibility == 'shared'
                                  ? l10n.sharedGroup
                                  : l10n.personalGroup,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                      GroupStorageBadge(
                        key: Key('group-storage-${group.id}'),
                        serverBacked: serverBacked,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    balance >= 0 ? l10n.yourGroupBalance : l10n.youCurrentlyOwe,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    formatMoney(balance.abs()),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: balance < 0 ? colors.error : colors.primary,
                        ),
                  ),
                ],
              ),
            ),
            Tooltip(
              message: l10n.viewPendingPayments,
              child: const Icon(Icons.chevron_right_rounded),
            ),
          ]),
        ),
      ),
    );
  }
}
