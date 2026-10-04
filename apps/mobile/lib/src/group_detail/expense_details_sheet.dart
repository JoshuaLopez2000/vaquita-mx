part of '../group_detail_screen.dart';

Map<String, int> _expenseShares(Expense expense) {
  if (expense.shares.isNotEmpty) return expense.shares;
  if (expense.splitMode != 'equal' || expense.participantIds.isEmpty) {
    return const {};
  }

  final result = <String, int>{};
  final paid = expense.payers.isEmpty
      ? expense.amountCents
      : expense.payers.fold<int>(0, (sum, payer) => sum + payer.amountCents);
  final allocatedAmount =
      paid > expense.amountCents ? paid : expense.amountCents;
  final baseShare = allocatedAmount ~/ expense.participantIds.length;
  var remainder = allocatedAmount % expense.participantIds.length;
  for (final participantId in expense.participantIds) {
    result[participantId] = baseShare + (remainder > 0 ? 1 : 0);
    if (remainder > 0) remainder--;
  }
  return result;
}

void showExpenseDetailsSheet(
  BuildContext context,
  ExpenseGroup group,
  Expense expense,
) {
  final l10n = AppLocalizations.of(context)!;
  final members = {for (final member in group.members) member.id: member};
  final payers = expense.payers.isEmpty
      ? [
          ExpensePayer(
              memberId: expense.payerId, amountCents: expense.amountCents)
        ]
      : expense.payers;
  final shares = _expenseShares(expense);
  final percentFormat = NumberFormat.percentPattern(l10n.localeName)
    ..minimumFractionDigits = 1
    ..maximumFractionDigits = 1;

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * .85,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            Text(
              l10n.expenseDetails,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(expense.description,
                style: Theme.of(context).textTheme.titleMedium),
            for (final payer in payers)
              if (members[payer.memberId] != null) ...[
                const SizedBox(height: 4),
                Text(l10n.paidByName(
                    '${members[payer.memberId]!.name} — ${formatMoney(payer.amountCents)}')),
              ],
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(l10n.total),
                    Text(
                      formatMoney(expense.amountCents),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(l10n.splitMethod,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Chip(
              avatar: Icon(
                expense.splitMode == 'salary'
                    ? Icons.pie_chart_outline_rounded
                    : Icons.balance_rounded,
              ),
              label: Text(expense.splitMode == 'salary'
                  ? l10n.salaryBasedSplit
                  : l10n.equalSplit),
            ),
            Text(expense.splitMode == 'salary'
                ? l10n.salarySplitExplanation
                : l10n.equalSplitExplanation),
            const SizedBox(height: 22),
            Text(l10n.participantShares,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            for (final participantId in expense.participantIds)
              Builder(builder: (context) {
                final member = members[participantId];
                final share = shares[participantId];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    child: Text(member?.initials ?? '?'),
                  ),
                  title: Text(member?.name ?? l10n.genericMember),
                  subtitle: Text(share == null || expense.amountCents == 0
                      ? l10n.shareUnavailable
                      : l10n.shareOfTotal(
                          percentFormat.format(share / expense.amountCents))),
                  trailing: Text(
                    share == null ? '—' : formatMoney(share),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                );
              }),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(sheetContext),
              child: Text(l10n.close),
            ),
          ],
        ),
      ),
    ),
  );
}
