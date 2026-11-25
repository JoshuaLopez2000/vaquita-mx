part of '../group_detail_screen.dart';

Future<void> showFinancialStatisticsSheet(
  BuildContext context,
  ExpenseGroup group,
) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _FinancialStatisticsSheet(group: group),
    );

class _FinancialStatisticsSheet extends StatefulWidget {
  const _FinancialStatisticsSheet({required this.group});

  final ExpenseGroup group;

  @override
  State<_FinancialStatisticsSheet> createState() =>
      _FinancialStatisticsSheetState();
}

class _FinancialStatisticsSheetState extends State<_FinancialStatisticsSheet> {
  var _thisMonthOnly = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final statistics = OverpaymentStatistics.forExpenses(
      widget.group.expenses,
      now: DateTime.now(),
      thisMonthOnly: _thisMonthOnly,
      reversedExpenseIds: widget.group.reversedExpenseIds,
    );
    final members = {
      for (final member in widget.group.members) member.id: member,
    };
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.financialStatistics,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(l10n.allTime)),
                ButtonSegment(value: true, label: Text(l10n.thisMonth)),
              ],
              selected: {_thisMonthOnly},
              onSelectionChanged: (value) => setState(() {
                _thisMonthOnly = value.first;
              }),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.distributedOverpayments,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatMoney(statistics.distributedCents),
                    style: VaquitaTheme.money(theme.textTheme.titleLarge),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(height: 1),
                  ),
                  Text(
                    l10n.retainedOverpayments,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatMoney(statistics.retainedCents),
                    style: VaquitaTheme.money(theme.textTheme.titleLarge),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.retainedOverpaymentsDescription,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (statistics.retainedByMember.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final entry in statistics.retainedByMember.entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(members[entry.key]?.name ?? l10n.genericMember),
                  trailing: Text(
                    formatMoney(entry.value),
                    style: VaquitaTheme.money(theme.textTheme.titleSmall),
                  ),
                ),
            ],
            if (statistics.totalCents == 0) ...[
              const SizedBox(height: 14),
              Text(
                l10n.noOverpayments,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.close),
            ),
          ],
        ),
      ),
    );
  }
}
