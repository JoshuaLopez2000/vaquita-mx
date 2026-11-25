part of '../group_detail_screen.dart';

class _ExpenseCard extends StatelessWidget {
  const _ExpenseCard({
    required this.store,
    required this.group,
    required this.expense,
    required this.onReverseAndReplace,
  });

  final DemoStore store;
  final ExpenseGroup group;
  final Expense expense;
  final Future<void> Function(Expense expense, String reason)
      onReverseAndReplace;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final payerIDs = expense.payers.isEmpty
        ? [expense.payerId]
        : expense.payers.map((payer) => payer.memberId);
    final members = {for (final member in group.members) member.id: member};
    final payerNames = payerIDs
        .map((id) => members[id]?.name ?? l10n.genericMember)
        .join(', ');
    final reversal = group.reversalForExpense(expense.id);
    final isReversed = reversal != null;
    return Card(
      key: Key('expense-card-${expense.id}'),
      child: ListTile(
        onTap: () => showExpenseDetailsSheet(
          context,
          group,
          expense,
          store: store,
          onReverseAndReplace: onReverseAndReplace,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isReversed
                ? colorScheme.errorContainer
                : colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            isReversed ? Icons.undo_rounded : Icons.receipt_long_rounded,
            color: isReversed
                ? colorScheme.onErrorContainer
                : colorScheme.onSecondaryContainer,
          ),
        ),
        title: Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              expense.description,
              style: theme.textTheme.titleSmall?.copyWith(
                decoration: isReversed ? TextDecoration.lineThrough : null,
              ),
            ),
            if (isReversed)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  l10n.reversed,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            else if (expense.replacesExpenseId != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  l10n.replacement,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onTertiaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            isReversed
                ? '${l10n.reversed} · ${reversal.reason}'
                : l10n.expenseSplitDetails(
                    payerNames,
                    expense.splitMode == 'salary'
                        ? l10n.bySalary
                        : expense.splitMode == 'percentage'
                            ? l10n.byPercentage
                            : l10n.split,
                    expense.participantIds.length,
                  ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        trailing: Text(
          formatMoney(expense.amountCents),
          style: VaquitaTheme.money(
            theme.textTheme.titleSmall,
            color: isReversed ? colorScheme.error : colorScheme.onSurface,
          ).copyWith(
            decoration: isReversed ? TextDecoration.lineThrough : null,
          ),
        ),
      ),
    );
  }
}
