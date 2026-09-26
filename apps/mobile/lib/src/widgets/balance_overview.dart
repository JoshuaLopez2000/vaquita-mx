part of '../app.dart';

class _BalanceOverview extends StatelessWidget {
  const _BalanceOverview({required this.owedToYou, required this.youOwe});

  final int owedToYou;
  final int youOwe;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors.primary, const Color(0xFF004B43)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.acrossAllGroups,
            style: TextStyle(color: colors.onPrimary.withValues(alpha: 0.8)),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _BalanceMetric(
                  label: l10n.youAreOwed,
                  value: formatMoney(owedToYou),
                  icon: Icons.south_west_rounded,
                ),
              ),
              Container(
                width: 1,
                height: 48,
                color: colors.onPrimary.withValues(alpha: 0.2),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 18),
                  child: _BalanceMetric(
                    label: l10n.youOwe,
                    value: formatMoney(youOwe),
                    icon: Icons.north_east_rounded,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
