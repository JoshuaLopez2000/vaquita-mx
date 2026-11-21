part of '../group_detail_screen.dart';

class _ExpenseCard extends StatelessWidget {
  const _ExpenseCard({required this.group, required this.expense});

  final ExpenseGroup group;
  final Expense expense;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final payerIDs = expense.payers.isEmpty
        ? [expense.payerId]
        : expense.payers.map((payer) => payer.memberId);
    final payerNames = payerIDs
        .map((id) => group.members.firstWhere((member) => member.id == id).name)
        .join(', ');
    return Card(
      child: ListTile(
        onTap: () => showExpenseDetailsSheet(context, group, expense),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.receipt_long_rounded),
        ),
        title: Text(
          expense.description,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          l10n.expenseSplitDetails(
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
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
