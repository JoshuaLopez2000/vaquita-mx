import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vaquita_mx/src/features/app/application/app_cubit.dart';
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
    final created = await context.read<AppCubit>().addExpense(
          groupId: group.id,
          description: input.description,
          amountCents: input.amountCents,
          payerId: input.payerId,
          participantIds: input.participantIds,
          splitMode: input.splitMode,
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          created
              ? '${input.description} added.'
              : 'Could not add the expense.',
        ),
      ),
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
              const SizedBox(height: 14),
              _SalarySplitCard(
                group: group,
                onConfigure: () => _editGroup(context, group),
              ),
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
                        index <
                            group.members
                                .where((member) => member.active)
                                .length;
                        index++) ...[
                      _MemberBalanceTile(
                        member: group.members
                            .where((member) => member.active)
                            .elementAt(index),
                        balance: balances[group.members
                                .where((member) => member.active)
                                .elementAt(index)
                                .id] ??
                            0,
                        isCurrentUser: group.members
                                    .where((member) => member.active)
                                    .elementAt(index)
                                    .userId ==
                                store.currentUserId ||
                            group.members
                                    .where((member) => member.active)
                                    .elementAt(index)
                                    .id ==
                                store.currentUserId,
                        onSettle: () => _showSettlement(
                          context,
                          group,
                          group.members
                              .where((member) => member.active)
                              .elementAt(index),
                          balances[group.members
                                  .where((member) => member.active)
                                  .elementAt(index)
                                  .id] ??
                              0,
                        ),
                      ),
                      if (index !=
                          group.members
                                  .where((member) => member.active)
                                  .length -
                              1)
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
              Text(
                  '${group.visibility == 'shared' ? 'Shared group' : 'Personal group'} · ${group.members.map((member) => member.name).join(', ')}'),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _editGroup(context, group);
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit group and add contacts')),
              const SizedBox(height: 8),
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

  Future<void> _editGroup(BuildContext context, ExpenseGroup group) async {
    final self = group.members
        .where((member) => member.userId == store.currentUserId)
        .toList();
    final name = TextEditingController(text: group.name);
    final emoji = TextEditingController(text: group.emoji);
    final member = TextEditingController();
    final phone = TextEditingController();
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (sheet) => Padding(
            padding: EdgeInsets.fromLTRB(
                24, 20, 24, 24 + MediaQuery.viewInsetsOf(sheet).bottom),
            child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Group name')),
              const SizedBox(height: 8),
              TextField(
                  controller: emoji,
                  decoration: const InputDecoration(labelText: 'Icon')),
              const SizedBox(height: 8),
              FilledButton(
                  onPressed: () async {
                    await context.read<AppCubit>().updateGroup(
                        group.id, {'name': name.text, 'emoji': emoji.text});
                    if (sheet.mounted) Navigator.pop(sheet);
                  },
                  child: const Text('Save group')),
              if (group.salarySplitAvailable)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: group.salarySplitEnabled,
                  title: const Text('Enable salary-based splits'),
                  subtitle: const Text('Every active member has consented.'),
                  onChanged: (value) async {
                    await store
                        .updateGroup(group.id, {'salary_split_enabled': value});
                    if (sheet.mounted) Navigator.pop(sheet);
                  },
                )
              else if (group.visibility == 'shared')
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                      'Salary splits unlock after every member accepts and opts in.'),
                ),
              const Divider(height: 28),
              TextField(
                  controller: member,
                  decoration: const InputDecoration(labelText: 'Contact name')),
              const SizedBox(height: 8),
              TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration:
                      const InputDecoration(labelText: 'Mexican phone number')),
              if (group.visibility == 'shared')
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(top: 4),
                    child:
                        Text('They will appear as pending until they accept.'),
                  ),
                ),
              const SizedBox(height: 8),
              OutlinedButton(
                  onPressed: () async {
                    final appCubit = context.read<AppCubit>();
                    final added = await appCubit.addMember(
                        group.id, member.text.trim(), phone.text.trim());
                    if (!added) {
                      if (sheet.mounted) {
                        ScaffoldMessenger.of(sheet).showSnackBar(
                          const SnackBar(
                              content: Text('Could not add this contact.')),
                        );
                      }
                      return;
                    }
                    await appCubit.loadGroups();
                    if (sheet.mounted) {
                      Navigator.pop(sheet);
                    }
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(group.visibility == 'shared'
                              ? 'Invitation sent to ${member.text.trim()}.'
                              : 'Contact added.'),
                        ),
                      );
                    }
                  },
                  child: Text(group.visibility == 'shared'
                      ? 'Send invitation'
                      : 'Add contact')),
              if (group.visibility == 'shared' && self.isNotEmpty)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: self.single.salarySharing,
                  title: const Text('Allow this group to use my salary'),
                  subtitle: const Text(
                      'Your salary value stays private; only your proportional share is used.'),
                  onChanged: (value) async {
                    await context.read<AppCubit>().updateMember(
                        group.id, self.single.id, {'salary_sharing': value});
                    if (sheet.mounted) Navigator.pop(sheet);
                  },
                ),
            ]))));
    name.dispose();
    emoji.dispose();
    member.dispose();
    phone.dispose();
  }

  void _showSettlement(
    BuildContext context,
    ExpenseGroup group,
    Member member,
    int balance,
  ) =>
      showSettlementSheet(context, store, group, member, balance);
}

void showSettlementSheet(
  BuildContext context,
  DemoStore store,
  ExpenseGroup group,
  Member member,
  int balance, {
  VoidCallback? onSettled,
}) {
  if (member.userId == store.currentUserId ||
      member.id == store.currentUserId ||
      balance == 0) {
    return;
  }
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
              memberOwes ? 'Request from ${member.name}' : 'Pay ${member.name}',
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
              onPressed: () async {
                final settled = await context.read<AppCubit>().settleBalance(
                      groupId: group.id,
                      memberId: member.id,
                    );
                if (!sheetContext.mounted || !context.mounted) return;
                Navigator.pop(sheetContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      settled
                          ? 'Simulated payment confirmed.'
                          : 'Could not confirm the payment.',
                    ),
                  ),
                );
                if (settled) onSettled?.call();
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

class _SalarySplitCard extends StatelessWidget {
  const _SalarySplitCard({required this.group, required this.onConfigure});
  final ExpenseGroup group;
  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    final enabled = group.salarySplitEnabled;
    final available = group.salarySplitAvailable;
    final message = enabled
        ? 'Expenses can be divided in proportion to salary.'
        : available
            ? 'Everyone consented. Turn it on to use it for new expenses.'
            : group.visibility == 'shared'
                ? 'Waiting for every member to accept and share salary consent.'
                : 'Salary splits require a shared group so every member can consent.';
    return Card(
        child: ListTile(
      leading: Icon(Icons.pie_chart_outline_rounded,
          color: Theme.of(context).colorScheme.primary),
      title:
          Text(enabled ? 'Salary-based splits enabled' : 'Salary-based splits'),
      subtitle: Text(message),
      trailing: TextButton(
          onPressed: onConfigure,
          child: Text(available || group.visibility == 'shared'
              ? 'Configure'
              : 'Info')),
    ));
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
    final subtitle = !member.accepted
        ? 'Invitation pending'
        : balance > 0
            ? 'gets back ${formatMoney(balance)}'
            : balance < 0
                ? 'owes ${formatMoney(balance.abs())}'
                : 'settled up';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(child: Text(member.initials)),
      title: Text(isCurrentUser ? 'You' : member.name),
      subtitle: Text(subtitle),
      trailing: !member.accepted
          ? Icon(Icons.hourglass_empty_rounded, color: colors.secondary)
          : isCurrentUser || balance == 0
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
          'Paid by ${payer.name} · ${expense.splitMode == 'salary' ? 'split by salary' : 'split'} ${expense.participantIds.length} ways',
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
