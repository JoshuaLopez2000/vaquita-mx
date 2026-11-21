part of '../group_detail_screen.dart';

Future<void> showFinancialStatisticsSheet(
  BuildContext context,
  ExpenseGroup group,
) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
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
    final statistics = OverpaymentStatistics.forExpenses(
      widget.group.expenses,
      now: DateTime.now(),
      thisMonthOnly: _thisMonthOnly,
      reversedExpenseIds: widget.group.reversedExpenseIds,
    );
    final members = {
      for (final member in widget.group.members) member.id: member
    };
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outline,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(l10n.financialStatistics,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  )),
          const SizedBox(height: 8),
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
          const SizedBox(height: 20),
          Text(l10n.distributedOverpayments),
          Text(formatMoney(statistics.distributedCents),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(l10n.retainedOverpayments),
          Text(formatMoney(statistics.retainedCents),
              style: Theme.of(context).textTheme.titleLarge),
          Text(l10n.retainedOverpaymentsDescription),
          if (statistics.retainedByMember.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final entry in statistics.retainedByMember.entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(members[entry.key]?.name ?? l10n.genericMember),
                trailing: Text(formatMoney(entry.value)),
              ),
          ],
          if (statistics.totalCents == 0) ...[
            const SizedBox(height: 12),
            Text(l10n.noOverpayments),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }
}
