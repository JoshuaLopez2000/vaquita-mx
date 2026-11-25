part of '../group_detail_screen.dart';

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.detail,
    this.isMoneyDetail = false,
  });

  final String title;
  final String detail;
  final bool isMoneyDetail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleLarge,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: colors.secondaryContainer,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            detail,
            style: isMoneyDetail
                ? VaquitaTheme.money(
                    theme.textTheme.labelSmall,
                    color: colors.onSecondaryContainer,
                    weight: FontWeight.w700,
                  )
                : theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSecondaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
          ),
        ),
      ],
    );
  }
}
