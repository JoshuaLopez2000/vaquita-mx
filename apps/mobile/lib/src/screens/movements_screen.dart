part of '../app.dart';

class MovementsScreen extends StatelessWidget {
  const MovementsScreen({required this.store, super.key});

  final DemoStore store;

  List<_Movement> _items(AppLocalizations l10n) {
    final items = <_Movement>[];
    for (final group in store.groups) {
      final members = {for (final member in group.members) member.id: member};
      String displayName(String memberId) {
        final member = members[memberId];
        if (member == null) return l10n.genericMember;
        if (member.id == store.currentUserId ||
            member.userId == store.currentUserId) {
          return l10n.you;
        }
        return member.name;
      }

      final expensesById = {
        for (final expense in group.expenses) expense.id: expense,
      };
      final settlementsById = {
        for (final settlement in group.settlements) settlement.id: settlement,
      };
      for (final expense in group.expenses) {
        final isReversed = group.isExpenseReversed(expense.id);
        final payerDetail = l10n.memberPaid(
          (expense.payers.isEmpty
                  ? [expense.payerId]
                  : expense.payers.map((payer) => payer.memberId))
              .map(displayName)
              .join(', '),
        );
        items.add(
          _Movement(
            group: group,
            title: expense.description,
            detail:
                isReversed ? '${l10n.reversed} · $payerDetail' : payerDetail,
            amountCents: expense.amountCents,
            occurredAt: expense.createdAt,
            isSettlement: false,
            isReversed: isReversed,
            isReversalEntry: false,
          ),
        );
      }
      for (final reversal in group.expenseReversals) {
        final original = expensesById[reversal.originalExpenseId];
        items.add(
          _Movement(
            group: group,
            title: l10n.expenseReversalMovement(
              original?.description ?? reversal.originalExpenseId,
            ),
            detail:
                '${l10n.reversedByName(displayName(reversal.actorMemberId))} · ${reversal.reason}',
            amountCents: -(original?.amountCents ?? 0),
            occurredAt: reversal.createdAt,
            isSettlement: false,
            isReversed: false,
            isReversalEntry: true,
          ),
        );
      }
      for (final settlement in group.settlements) {
        final isReversed = group.isSettlementReversed(settlement.id);
        final from = displayName(settlement.fromMemberId);
        final to = displayName(settlement.toMemberId);
        items.add(
          _Movement(
            group: group,
            title: l10n.memberPaidMember(from, to),
            detail: isReversed
                ? '${l10n.reversed} · ${l10n.settlement}'
                : l10n.settlement,
            amountCents: settlement.amountCents,
            occurredAt: settlement.createdAt,
            isSettlement: true,
            isReversed: isReversed,
            isReversalEntry: false,
          ),
        );
      }
      for (final reversal in group.settlementReversals) {
        final original = settlementsById[reversal.originalSettlementId];
        items.add(
          _Movement(
            group: group,
            title: l10n.settlementReversalMovement,
            detail:
                '${l10n.reversedByName(displayName(reversal.actorMemberId))} · ${reversal.reason}',
            amountCents: -(original?.amountCents ?? 0),
            occurredAt: reversal.createdAt,
            isSettlement: true,
            isReversed: false,
            isReversalEntry: true,
          ),
        );
      }
    }
    items.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return items;
  }

  String _relativeDate(DateTime value, AppLocalizations l10n) {
    final date = value.toLocal();
    final today = DateUtils.dateOnly(DateTime.now());
    final daysAgo = today.difference(DateUtils.dateOnly(date)).inDays;
    if (daysAgo == 0) return l10n.today;
    if (daysAgo == 1) return l10n.yesterday;
    if (daysAgo < 7) return l10n.daysAgo(daysAgo);
    return DateFormat.yMd(l10n.localeName).format(date);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppCubit, AppState>(
      builder: (context, _) {
        final l10n = AppLocalizations.of(context)!;
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final vColors = VaquitaColors.of(context);
        final items = _items(l10n);
        return CustomScrollView(
          slivers: [
            SliverAppBar.large(
              title: Text(l10n.movements),
              backgroundColor: theme.scaffoldBackgroundColor,
            ),
            if (items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: VaquitaEmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: l10n.noMovements,
                    description: l10n.movementsEmptyDescription,
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                sliver: SliverList.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final isErrorTone = item.isReversed || item.isReversalEntry;
                    final bg = isErrorTone
                        ? colors.errorContainer
                        : item.isSettlement
                            ? vColors.positiveContainer
                            : colors.secondaryContainer;
                    final fg = isErrorTone
                        ? colors.onErrorContainer
                        : item.isSettlement
                            ? vColors.onPositiveContainer
                            : colors.onSecondaryContainer;
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            isErrorTone
                                ? Icons.undo_rounded
                                : item.isSettlement
                                    ? Icons.handshake_outlined
                                    : Icons.receipt_long_outlined,
                            color: fg,
                          ),
                        ),
                        title: Text(
                          item.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            decoration: item.isReversed
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            l10n.movementMetadata(
                              item.group.emoji,
                              item.group.name,
                              item.detail,
                              _relativeDate(item.occurredAt, l10n),
                            ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        trailing: Text(
                          formatMoney(item.amountCents),
                          style: VaquitaTheme.money(
                            theme.textTheme.titleSmall,
                            color: isErrorTone
                                ? colors.error
                                : item.isSettlement
                                    ? vColors.positive
                                    : colors.onSurface,
                          ).copyWith(
                            decoration: item.isReversed
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => GroupDetailScreen(
                              store: store,
                              groupId: item.group.id,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Movement {
  const _Movement({
    required this.group,
    required this.title,
    required this.detail,
    required this.amountCents,
    required this.occurredAt,
    required this.isSettlement,
    this.isReversed = false,
    this.isReversalEntry = false,
  });

  final ExpenseGroup group;
  final String title;
  final String detail;
  final int amountCents;
  final DateTime occurredAt;
  final bool isSettlement;
  final bool isReversed;
  final bool isReversalEntry;
}
