part of '../app.dart';

class _GroupCard extends StatelessWidget {
  const _GroupCard({
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
    final balanceColor = balance >= 0 ? colors.primary : colors.error;
    final balanceLabel = balance > 0
        ? l10n.groupBalanceOwed
        : balance < 0
            ? l10n.groupBalanceYouOwe
            : l10n.groupBalanceSettled;

    return Card(
      child: InkWell(
        key: Key('group-${group.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Text(group.emoji, style: const TextStyle(fontSize: 27)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 3),
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
                        Text(
                          group.visibility == 'shared'
                              ? l10n.sharedGroup
                              : l10n.personalGroup,
                          key: Key('group-visibility-${group.id}'),
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: colors.secondary,
                                  ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      l10n.groupSummary(
                          group.members.length, group.expenses.length),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    GroupStorageBadge(
                      key: Key('group-storage-${group.id}'),
                      serverBacked: serverBacked,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatMoney(balance.abs()),
                    style: TextStyle(
                      color: balanceColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    balanceLabel,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
