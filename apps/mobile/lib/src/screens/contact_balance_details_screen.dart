part of '../app.dart';

class ContactBalanceDetailsScreen extends StatelessWidget {
  const ContactBalanceDetailsScreen(
      {required this.store, required this.status, super.key});

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
          .where((expense) =>
              (expense.payers.isEmpty
                      ? [expense.payerId]
                      : expense.payers.map((payer) => payer.memberId))
                  .contains(contactMember.id) ||
              expense.participantIds.contains(contactMember.id))
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
    final balances = _groupBalances();
    final currentAmount =
        balances.fold<int>(0, (total, balance) => total + balance.amount);
    return Scaffold(
      appBar: AppBar(title: Text(status.member.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Text(l10n.balanceDetails,
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(formatMoney(currentAmount.abs()),
              style: Theme.of(context).textTheme.headlineMedium),
          if (currentAmount == 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(l10n.settledUp),
            ),
          const SizedBox(height: 24),
          Text(l10n.byGroup, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (balances.isEmpty)
            Text(l10n.noActiveBalances)
          else
            for (final balance in balances)
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: CircleAvatar(child: Text(balance.group.emoji)),
                      title: Text(balance.group.name),
                      subtitle: Text(balance.amount > 0
                          ? l10n.memberOwesYou(status.member.name)
                          : l10n.youOweMember(status.member.name)),
                      trailing: Text(formatMoney(balance.amount.abs()),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
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
                          child: Text(l10n.concepts,
                              style: Theme.of(context).textTheme.labelLarge),
                        ),
                      ),
                      for (final expense in balance.concepts)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.receipt_long_outlined),
                          title: Text(expense.description),
                          trailing: Text(formatMoney(expense.amountCents)),
                        ),
                    ],
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          key: Key('request-payment-${balance.group.id}'),
                          onPressed: () => showSettlementSheet(
                              context,
                              store,
                              balance.group,
                              balance.member,
                              balance.amount, onSettled: () {
                            if (context.mounted) Navigator.of(context).pop();
                            context.read<AppCubit>().showMovements();
                          }),
                          icon: const Icon(Icons.qr_code_2_rounded),
                          label: Text(balance.amount > 0
                              ? l10n.requestPayment
                              : l10n.payContact(status.member.name)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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
