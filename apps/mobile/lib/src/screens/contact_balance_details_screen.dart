part of '../app.dart';

class ContactBalanceDetailsScreen extends StatelessWidget {
  const ContactBalanceDetailsScreen({
    required this.store,
    required this.status,
    super.key,
  });

  final DemoStore store;
  final ContactStatus status;

  List<_GroupBalance> _groupBalances() {
    final balances = <_GroupBalance>[];
    for (final group in store.groups) {
      Member? member;
      for (final candidate in group.members) {
        if (candidate.id == status.member.id) {
          member = candidate;
          break;
        }
      }
      if (member == null) continue;
      final amount = store.balanceWith(group, member);
      if (amount == 0) continue;
      final contactMember = member;
      final concepts = group.expenses
          .where(
            (expense) =>
                (expense.payers.isEmpty
                        ? [expense.payerId]
                        : expense.payers.map((payer) => payer.memberId))
                    .contains(contactMember.id) ||
                expense.participantIds.contains(contactMember.id),
          )
          .toList();
      balances.add(_GroupBalance(group, contactMember, amount, concepts));
    }
    return balances;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppCubit, AppState>(
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final vColors = VaquitaColors.of(context);
    final balances = _groupBalances();
    final currentAmount =
        balances.fold<int>(0, (total, balance) => total + balance.amount);
    final tone = currentAmount > 0
        ? vColors.positive
        : currentAmount < 0
            ? vColors.negative
            : colors.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(title: Text(status.member.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.balanceDetails,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      formatMoney(currentAmount.abs()),
                      style: VaquitaTheme.money(
                        theme.textTheme.headlineMedium,
                        color: tone,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    currentAmount > 0
                        ? l10n.memberOwesYou(status.member.name)
                        : currentAmount < 0
                            ? l10n.youOweMember(status.member.name)
                            : l10n.settledUp,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(l10n.byGroup, style: theme.textTheme.titleLarge),
          const SizedBox(height: 10),
          if (balances.isEmpty)
            VaquitaEmptyState(
              inCard: true,
              icon: Icons.check_circle_outline_rounded,
              title: l10n.settledUp,
              description: l10n.noActiveBalances,
            )
          else
            for (final balance in balances) ...[
              Card(
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      leading: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colors.primaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          balance.group.emoji,
                          style: const TextStyle(fontSize: 22),
                        ),
                      ),
                      title: Text(
                        balance.group.name,
                        style: theme.textTheme.titleMedium,
                      ),
                      subtitle: Text(
                        balance.amount > 0
                            ? l10n.memberOwesYou(status.member.name)
                            : l10n.youOweMember(status.member.name),
                      ),
                      trailing: Text(
                        formatMoney(balance.amount.abs()),
                        style: VaquitaTheme.money(
                          theme.textTheme.titleMedium,
                          color: balance.amount > 0
                              ? vColors.positive
                              : vColors.negative,
                        ),
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => GroupDetailScreen(
                            store: store,
                            groupId: balance.group.id,
                          ),
                        ),
                      ),
                    ),
                    if (balance.concepts.isNotEmpty) ...[
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            l10n.concepts,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                      for (final expense in balance.concepts)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.receipt_long_outlined),
                          title: Text(expense.description),
                          trailing: Text(
                            formatMoney(expense.amountCents),
                            style: VaquitaTheme.money(
                              theme.textTheme.bodyMedium,
                              weight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                    if (!(balance.group.visibility == 'shared' &&
                        store.canRequestPayment(balance.group) &&
                        balance.amount < 0))
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            key: Key(
                              store.canRequestPayment(balance.group)
                                  ? 'request-payment-${balance.group.id}'
                                  : 'settlement-${balance.group.id}',
                            ),
                            onPressed: () => showSettlementSheet(
                              context,
                              store,
                              balance.group,
                              balance.member,
                              balance.amount,
                              onSettled: () {
                                if (context.mounted) {
                                  Navigator.of(context).pop();
                                }
                                context.read<AppCubit>().showMovements();
                              },
                            ),
                            icon: const Icon(Icons.qr_code_2_rounded),
                            label: Text(
                              store.canRequestPayment(balance.group)
                                  ? l10n.requestPayment
                                  : balance.amount > 0
                                      ? l10n.confirmPaymentReceived
                                      : l10n.payContact(status.member.name),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }
}

class _GroupBalance {
  const _GroupBalance(this.group, this.member, this.amount, this.concepts);

  final ExpenseGroup group;
  final Member member;
  final int amount;
  final List<Expense> concepts;
}
