part of '../group_detail_screen.dart';

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group, required this.balance});

  final ExpenseGroup group;
  final int balance;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Text(group.emoji, style: const TextStyle(fontSize: 42)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
        ],
      ),
    );
  }
}
