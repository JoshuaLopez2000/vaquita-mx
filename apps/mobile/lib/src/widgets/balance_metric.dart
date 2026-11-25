part of '../app.dart';

class _BalanceMetric extends StatelessWidget {
  const _BalanceMetric({
    required this.label,
    required this.value,
    required this.icon,
    this.accentColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vColors = VaquitaColors.of(context);
    final onHero = vColors.onHero;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: (accentColor ?? onHero).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(
                icon,
                size: 14,
                color: accentColor ?? onHero,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: onHero.withValues(alpha: 0.86),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: VaquitaTheme.money(
              theme.textTheme.headlineSmall,
              color: onHero,
              weight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}
