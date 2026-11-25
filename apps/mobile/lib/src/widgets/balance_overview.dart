part of '../app.dart';

class _BalanceOverview extends StatelessWidget {
  const _BalanceOverview({required this.owedToYou, required this.youOwe});

  final int owedToYou;
  final int youOwe;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final vColors = VaquitaColors.of(context);
    final netCents = owedToYou - youOwe;
    final netLabel = netCents > 0
        ? l10n.netPositionPositive(formatMoney(netCents))
        : netCents < 0
            ? l10n.netPositionNegative(formatMoney(netCents.abs()))
            : l10n.netPositionSettled;
    final netIcon = netCents > 0
        ? Icons.trending_up_rounded
        : netCents < 0
            ? Icons.trending_down_rounded
            : Icons.check_circle_outline_rounded;
    final textScale = MediaQuery.textScalerOf(context).scale(1);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [vColors.heroStart, vColors.heroEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: vColors.heroAccent.withValues(alpha: 0.22),
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -36,
            top: -42,
            child: IgnorePointer(
              child: Container(
                width: 148,
                height: 148,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: vColors.heroAccent.withValues(alpha: 0.08),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    Text(
                      l10n.acrossAllGroups,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: vColors.onHero.withValues(alpha: 0.84),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: vColors.onHero.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(netIcon, size: 14, color: vColors.heroAccent),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              netLabel,
                              style: VaquitaTheme.money(
                                theme.textTheme.labelSmall,
                                color: vColors.onHero,
                                weight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked =
                        constraints.maxWidth < 290 || textScale >= 1.35;
                    if (stacked) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _BalanceMetric(
                            label: l10n.youAreOwed,
                            value: formatMoney(owedToYou),
                            icon: Icons.south_west_rounded,
                            accentColor: vColors.heroAccent,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Divider(
                              height: 1,
                              color: vColors.onHero.withValues(alpha: 0.18),
                            ),
                          ),
                          _BalanceMetric(
                            label: l10n.youOwe,
                            value: formatMoney(youOwe),
                            icon: Icons.north_east_rounded,
                            accentColor: const Color(0xFFFFC2B2),
                          ),
                        ],
                      );
                    }
                    return IntrinsicHeight(
                      child: Row(
                        children: [
                          Expanded(
                            child: _BalanceMetric(
                              label: l10n.youAreOwed,
                              value: formatMoney(owedToYou),
                              icon: Icons.south_west_rounded,
                              accentColor: vColors.heroAccent,
                            ),
                          ),
                          VerticalDivider(
                            width: 28,
                            thickness: 1,
                            color: vColors.onHero.withValues(alpha: 0.18),
                          ),
                          Expanded(
                            child: _BalanceMetric(
                              label: l10n.youOwe,
                              value: formatMoney(youOwe),
                              icon: Icons.north_east_rounded,
                              accentColor: const Color(0xFFFFC2B2),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
