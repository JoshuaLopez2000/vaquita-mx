import 'package:flutter/material.dart';
import 'package:vaquita_mx/src/models.dart';
import 'package:vaquita_mx/src/sheets.dart';
import 'package:vaquita_mx/src/store.dart';

class GroupDetailScreen extends StatelessWidget {
  const GroupDetailScreen({
    required this.store,
    required this.groupId,
    super.key,
  });

  final DemoStore store;
  final String groupId;

  Future<void> _addExpense(BuildContext context, ExpenseGroup group) async {
    final input = await showAddExpenseSheet(context, group);
    if (input == null || !context.mounted) return;
    store.addExpense(
      groupId: group.id,
      description: input.description,
      amountCents: input.amountCents,
      payerId: input.payerId,
      participantIds: input.participantIds,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${input.description} added.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final group = store.groupById(groupId);
        final balances = store.balances(group);
        return Scaffold(
          appBar: AppBar(
            title: Text(group.name),
            actions: [
              IconButton(
                tooltip: 'Group options',
                onPressed: () => _showGroupInfo(context, group),
                icon: const Icon(Icons.more_horiz_rounded),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            key: const Key('add-expense-button'),
            onPressed: () => _addExpense(context, group),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add expense'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
            children: [
              _GroupHeader(
                  group: group, balance: store.currentUserBalance(group)),
              const SizedBox(height: 24),
              _SectionHeader(
                title: 'Balances',
                detail: '${group.members.length} members',
              ),
              const SizedBox(height: 10),
              Card(
                child: Column(
                  children: [
                    for (var index = 0;
                        index < group.members.length;
                        index++) ...[
                      _MemberBalanceTile(
                        member: group.members[index],
                        balance: balances[group.members[index].id] ?? 0,
                        isCurrentUser:
                            group.members[index].id == DemoStore.currentUserId,
                        onSettle: () => _showSettlement(
                          context,
                          group,
                          group.members[index],
                          balances[group.members[index].id] ?? 0,
                        ),
                      ),
                      if (index != group.members.length - 1)
                        const Divider(height: 1, indent: 72),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _SectionHeader(
                title: 'Expenses',
                detail: formatMoney(group.totalSpentCents),
              ),
              const SizedBox(height: 10),
              if (group.expenses.isEmpty)
                _EmptyExpenses(onAdd: () => _addExpense(context, group))
              else
                for (final expense in group.expenses) ...[
                  _ExpenseCard(group: group, expense: expense),
                  const SizedBox(height: 10),
                ],
            ],
          ),
        );
      },
    );
  }

  void _showGroupInfo(BuildContext context, ExpenseGroup group) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${group.emoji} ${group.name}',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 12),
              Text(group.members.map((member) => member.name).join(', ')),
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSettlement(
    BuildContext context,
    ExpenseGroup group,
    Member member,
    int balance,
  ) {
    if (member.id == DemoStore.currentUserId || balance == 0) return;
    final memberOwes = balance < 0;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.qr_code_2_rounded,
                size: 54,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 14),
              Text(
                memberOwes
                    ? 'Request from ${member.name}'
                    : 'Pay ${member.name}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                '${formatMoney(balance.abs())} MXN',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Demo mode: this simulates a confirmed provider callback. No real money moves.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                key: Key('settle-${member.id}'),
                onPressed: () {
                  store.settleBalance(groupId: group.id, memberId: member.id);
                  Navigator.pop(sheetContext);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Simulated payment confirmed.')),
                  );
                },
                icon: const Icon(Icons.check_circle_outline_rounded),
                label: const Text('Simulate payment'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group, required this.balance});

  final ExpenseGroup group;
  final int balance;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Text(group.emoji, style: const TextStyle(fontSize: 42)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  balance >= 0 ? 'Your group balance' : 'You currently owe',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 3),
                Text(
                  formatMoney(balance.abs()),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: balance < 0 ? colors.error : colors.primary,
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        Text(detail),
      ],
    );
  }
}

class _MemberBalanceTile extends StatelessWidget {
  const _MemberBalanceTile({
    required this.member,
    required this.balance,
    required this.isCurrentUser,
    required this.onSettle,
  });

  final Member member;
  final int balance;
  final bool isCurrentUser;
  final VoidCallback onSettle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final subtitle = balance > 0
        ? 'gets back ${formatMoney(balance)}'
        : balance < 0
            ? 'owes ${formatMoney(balance.abs())}'
            : 'settled up';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(child: Text(member.initials)),
      title: Text(isCurrentUser ? 'You' : member.name),
      subtitle: Text(subtitle),
      trailing: isCurrentUser || balance == 0
          ? Icon(Icons.check_circle_rounded, color: colors.primary)
          : TextButton(
              onPressed: onSettle,
              child: Text(balance < 0 ? 'Request' : 'Pay'),
            ),
    );
  }
}

class _ExpenseCard extends StatelessWidget {
  const _ExpenseCard({required this.group, required this.expense});

  final ExpenseGroup group;
  final Expense expense;

  @override
  Widget build(BuildContext context) {
    final payer = group.members.firstWhere(
      (member) => member.id == expense.payerId,
    );
    return Card(
      child: ListTile(
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
          'Paid by ${payer.name} · split ${expense.participantIds.length} ways',
        ),
        trailing: Text(
          formatMoney(expense.amountCents),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _EmptyExpenses extends StatelessWidget {
  const _EmptyExpenses({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.receipt_long_outlined, size: 42),
            const SizedBox(height: 10),
            const Text('No expenses yet'),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add the first one'),
            ),
          ],
        ),
      ),
    );
  }
}
