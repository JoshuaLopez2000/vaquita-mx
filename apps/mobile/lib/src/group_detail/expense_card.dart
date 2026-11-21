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
    final payerIDs = expense.payers.isEmpty
        ? [expense.payerId]
        : expense.payers.map((payer) => payer.memberId);
    final members = {for (final member in group.members) member.id: member};
    final payerNames = payerIDs
        .map((id) => members[id]?.name ?? l10n.genericMember)
        .join(', ');
    final reversal = group.reversalForExpense(expense.id);
    final isReversed = reversal != null;
    final colorScheme = Theme.of(context).colorScheme;
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
            color: isReversed ? colorScheme.onErrorContainer : null,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                expense.description,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  decoration: isReversed ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            if (isReversed)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Chip(
                  label: Text(l10n.reversed),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: colorScheme.errorContainer,
                  labelStyle: TextStyle(
                    color: colorScheme.onErrorContainer,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            else if (expense.replacesExpenseId != null)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Chip(
                  label: Text(l10n.replacement),
                  visualDensity: VisualDensity.compact,
                  labelStyle: const TextStyle(fontSize: 11),
                ),
              ),
          ],
        ),
        subtitle: Text(
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
        ),
        trailing: Text(
          formatMoney(expense.amountCents),
          style: TextStyle(
            fontWeight: FontWeight.w800,
            decoration: isReversed ? TextDecoration.lineThrough : null,
          ),
        ),
      ),
    );
  }
}
