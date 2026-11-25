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
  Expense expense, {
  DemoStore? store,
  Future<void> Function(Expense expense, String reason)? onReverseAndReplace,
}) {
  final l10n = AppLocalizations.of(context)!;
  final members = {for (final member in group.members) member.id: member};
  final reversal = group.reversalForExpense(expense.id);
  final replacement = group.replacementForExpense(expense.id);
  final canReverse = store != null && store.canReverseExpense(group, expense);
  final pendingServerSync = store != null &&
      store.canUseServerFeatures(group) &&
      expense.id.startsWith('local_expense_');
  final payers = expense.payers.isEmpty
      ? [
          ExpensePayer(
            memberId: expense.payerId,
            amountCents: expense.amountCents,
          ),
        ]
      : expense.payers;
  final shares = expense.consumptionShares.isNotEmpty
      ? expense.consumptionShares
      : _expenseShares(expense);
  final shareTotal = expense.consumptionShares.isNotEmpty
      ? expense.amountCents
      : (expense.paidAmountCents > 0
          ? expense.paidAmountCents
          : expense.amountCents);
  final percentFormat = NumberFormat.percentPattern(l10n.localeName)
    ..minimumFractionDigits = 1
    ..maximumFractionDigits = 1;

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final colors = theme.colorScheme;
      return SafeArea(
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
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(expense.description, style: theme.textTheme.titleMedium),
              for (final payer in payers)
                if (members[payer.memberId] != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    l10n.paidByName(
                      '${members[payer.memberId]!.name} — ${formatMoney(payer.amountCents)}',
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(l10n.total, style: theme.textTheme.titleMedium),
                    Text(
                      formatMoney(expense.amountCents),
                      style: VaquitaTheme.money(
                        theme.textTheme.titleLarge,
                        color:
                            reversal != null ? colors.error : colors.onSurface,
                      ).copyWith(
                        decoration: reversal != null
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
              if (expense.replacesExpenseId != null) ...[
                const SizedBox(height: 12),
                Text(
                  l10n.replacesOriginalRecord,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
              if (reversal != null) ...[
                const SizedBox(height: 16),
                _ReversalAuditCard(
                  actorName: members[reversal.actorMemberId]?.name ??
                      l10n.genericMember,
                  reason: reversal.reason,
                  createdAt: reversal.createdAt,
                  hasReplacement: replacement != null,
                ),
              ],
              if (expense.paidAmountCents > expense.amountCents) ...[
                const SizedBox(height: 10),
                Text(
                  '${l10n.totalPaid}: ${formatMoney(expense.paidAmountCents)}',
                ),
                Text(
                  '${l10n.overpayment}: ${formatMoney(expense.overpaymentCents)}',
                ),
              ],
              const SizedBox(height: 18),
              Text(l10n.splitMethod, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  avatar: Icon(
                    expense.splitMode == 'salary'
                        ? Icons.pie_chart_outline_rounded
                        : expense.splitMode == 'percentage'
                            ? Icons.percent_rounded
                            : Icons.balance_rounded,
                  ),
                  label: Text(
                    expense.splitMode == 'salary'
                        ? l10n.salaryBasedSplit
                        : expense.splitMode == 'exact'
                            ? l10n.exactSplit
                            : expense.splitMode == 'percentage'
                                ? l10n.percentageSplit
                                : l10n.equalSplit,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                expense.splitMode == 'salary'
                    ? l10n.salarySplitExplanation
                    : expense.splitMode == 'exact'
                        ? l10n.exactSplitExplanation
                        : expense.splitMode == 'percentage'
                            ? l10n.percentageSplitExplanation
                            : l10n.equalSplitExplanation,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                expense.consumptionShares.isNotEmpty
                    ? l10n.consumption
                    : l10n.participantShares,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              for (final participantId in expense.participantIds)
                Builder(
                  builder: (context) {
                    final member = members[participantId];
                    final share = shares[participantId];
                    final pctBps = expense.splitMode == 'percentage'
                        ? expense.percentages[participantId]
                        : null;
                    final shareLabel = pctBps != null
                        ? l10n.shareOfTotal(
                            '${ExpenseAllocation.formatPercentageBps(pctBps)}%',
                          )
                        : share == null || shareTotal == 0
                            ? l10n.shareUnavailable
                            : l10n.shareOfTotal(
                                percentFormat.format(share / shareTotal),
                              );
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: colors.secondaryContainer,
                        foregroundColor: colors.onSecondaryContainer,
                        child: Text(member?.initials ?? '?'),
                      ),
                      title: Text(member?.name ?? l10n.genericMember),
                      subtitle: Text(shareLabel),
                      trailing: Text(
                        share == null ? '—' : formatMoney(share),
                        style: VaquitaTheme.money(
                          theme.textTheme.titleSmall,
                        ),
                      ),
                    );
                  },
                ),
              if (expense.overpaymentShares.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  l10n.overpaymentAllocation,
                  style: theme.textTheme.titleMedium,
                ),
                for (final participantId in expense.participantIds)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      members[participantId]?.name ?? l10n.genericMember,
                    ),
                    trailing: Text(
                      formatMoney(
                        expense.overpaymentShares[participantId] ?? 0,
                      ),
                      style: VaquitaTheme.money(theme.textTheme.bodyMedium),
                    ),
                  ),
                Text(l10n.finalLiability, style: theme.textTheme.titleMedium),
                for (final participantId in expense.participantIds)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      members[participantId]?.name ?? l10n.genericMember,
                    ),
                    trailing: Text(
                      formatMoney(expense.shares[participantId] ?? 0),
                      style: VaquitaTheme.money(theme.textTheme.bodyMedium),
                    ),
                  ),
              ],
              if (pendingServerSync && reversal == null) ...[
                const SizedBox(height: 12),
                Text(
                  l10n.syncBeforeReversal,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
              if (canReverse) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  key: Key('reverse-expense-${expense.id}'),
                  onPressed: () async {
                    final reason = await showReversalReasonDialog(
                      sheetContext,
                      title: l10n.reverseExpense,
                    );
                    if (reason == null || !sheetContext.mounted) return;
                    final reversed =
                        await sheetContext.read<AppCubit>().reverseExpense(
                              groupId: group.id,
                              expenseId: expense.id,
                              reason: reason,
                            );
                    if (!sheetContext.mounted) return;
                    Navigator.pop(sheetContext);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          reversed
                              ? (store.lastMutationQueuedOffline
                                  ? l10n.savedOfflineWillSync
                                  : l10n.expenseReversed)
                              : l10n.couldNotReverseRecord,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.undo_rounded),
                  label: Text(l10n.reverseExpense),
                ),
                if (onReverseAndReplace != null) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: Key('reverse-replace-expense-${expense.id}'),
                    onPressed: () async {
                      final reason = await showReversalReasonDialog(
                        sheetContext,
                        title: l10n.reverseAndReplaceExpense,
                      );
                      if (reason == null || !sheetContext.mounted) return;
                      Navigator.pop(sheetContext);
                      await onReverseAndReplace(expense, reason);
                    },
                    icon: const Icon(Icons.published_with_changes_rounded),
                    label: Text(l10n.reverseAndReplaceExpense),
                  ),
                ],
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: Text(l10n.close),
              ),
            ],
          ),
        ),
      );
    },
  );
}
