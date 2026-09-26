import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vaquita_mx/src/features/app/application/app_cubit.dart';
import 'package:vaquita_mx/src/models.dart';
import 'package:vaquita_mx/src/sheets.dart';
import 'package:vaquita_mx/src/store.dart';
import 'package:vaquita_mx/l10n/app_localizations.dart';

class GroupDetailScreen extends StatelessWidget {
  const GroupDetailScreen({
    required this.store,
    required this.groupId,
    super.key,
  });

  final DemoStore store;
  final String groupId;

  Future<void> _addExpense(BuildContext context, ExpenseGroup group) async {
    final l10n = AppLocalizations.of(context)!;
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
              ? l10n.expenseAdded(input.description)
              : l10n.couldNotAddExpense,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final l10n = AppLocalizations.of(context)!;
        final group = store.groupById(groupId);
        final balances = store.balances(group);
        return Scaffold(
          appBar: AppBar(
            title: Text(group.name),
            actions: [
              IconButton(
                tooltip: l10n.groupOptions,
                onPressed: () => _showGroupInfo(context, group),
                icon: const Icon(Icons.more_horiz_rounded),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            key: const Key('add-expense-button'),
            onPressed: () => _addExpense(context, group),
            icon: const Icon(Icons.add_rounded),
            label: Text(l10n.addExpense),
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
                title: l10n.balances,
                detail: l10n.membersCount(group.members.length),
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
                title: l10n.expenses,
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

  Future<void> _showGroupInfo(BuildContext context, ExpenseGroup group) async {
    final l10n = AppLocalizations.of(context)!;
    final editGroup = await showModalBottomSheet<bool>(
      context: context,
      builder: (sheetContext) => SafeArea(
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
                  '${group.visibility == 'shared' ? l10n.sharedGroup : l10n.personalGroup} · ${group.members.map((member) => member.name).join(', ')}'),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext, true);
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(l10n.editGroupContacts)),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.pop(sheetContext, false),
                child: Text(l10n.close),
              ),
            ],
          ),
        ),
      ),
    );
    if (editGroup == true && context.mounted) {
      await _editGroup(context, group);
    }
  }

  Future<void> _editGroup(BuildContext context, ExpenseGroup group) async {
    final l10n = AppLocalizations.of(context)!;
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
                  decoration: InputDecoration(labelText: l10n.groupName)),
              const SizedBox(height: 8),
              TextField(
                  controller: emoji,
                  decoration: InputDecoration(labelText: l10n.groupIcon)),
              const SizedBox(height: 8),
              FilledButton(
                  onPressed: () async {
                    await context.read<AppCubit>().updateGroup(
                        group.id, {'name': name.text, 'emoji': emoji.text});
                    if (sheet.mounted) Navigator.pop(sheet);
                  },
                  child: Text(l10n.saveGroup)),
              if (group.salarySplitAvailable)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: group.salarySplitEnabled,
                  title: Text(l10n.enableSalarySplits),
                  subtitle: Text(l10n.everyMemberConsented),
                  onChanged: (value) async {
                    await store
                        .updateGroup(group.id, {'salary_split_enabled': value});
                    if (sheet.mounted) Navigator.pop(sheet);
                  },
                )
              else if (group.visibility == 'shared')
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(l10n.salarySplitsUnlock),
                ),
              const Divider(height: 28),
              TextField(
                  controller: member,
                  decoration: InputDecoration(labelText: l10n.contactName)),
              const SizedBox(height: 8),
              TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration:
                      InputDecoration(labelText: l10n.mexicanMobileNumber)),
              if (group.visibility == 'shared')
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(l10n.pendingUntilAccept),
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
                          SnackBar(content: Text(l10n.couldNotAddContact)),
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
                              ? l10n.invitationSent(member.text.trim())
                              : l10n.contactAdded),
                        ),
                      );
                    }
                  },
                  child: Text(group.visibility == 'shared'
                      ? l10n.sendInvitation
                      : l10n.addContact)),
              if (group.visibility == 'shared' && self.isNotEmpty)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: self.single.salarySharing,
                  title: Text(l10n.allowGroupSalary),
                  subtitle: Text(l10n.salaryPrivacy),
                  onChanged: (value) async {
                    await context.read<AppCubit>().updateMember(
                        group.id, self.single.id, {'salary_sharing': value});
                    if (sheet.mounted) Navigator.pop(sheet);
                  },
                ),
            ]))));
    // The modal future resolves when dismissal begins, while a focused
    // EditableText can still be attached during the reverse animation.
    await Future<void>.delayed(const Duration(milliseconds: 300));
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
  final l10n = AppLocalizations.of(context)!;
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
              memberOwes
                  ? l10n.requestFrom(member.name)
                  : l10n.payContact(member.name),
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
              l10n.demoPaymentDescription,
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
                          ? l10n.paymentConfirmed
                          : l10n.couldNotConfirmPayment,
                    ),
                  ),
                );
                if (settled) onSettled?.call();
              },
              icon: const Icon(Icons.check_circle_outline_rounded),
              label: Text(l10n.simulatePayment),
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
    final l10n = AppLocalizations.of(context)!;
    final enabled = group.salarySplitEnabled;
    final available = group.salarySplitAvailable;
    final message = enabled
        ? l10n.salaryEnabledDescription
        : available
            ? l10n.salaryAvailableDescription
            : group.visibility == 'shared'
                ? l10n.salaryWaitingDescription
                : l10n.salarySharedGroupRequired;
    return Card(
        child: ListTile(
      leading: Icon(Icons.pie_chart_outline_rounded,
          color: Theme.of(context).colorScheme.primary),
      title: Text(enabled ? l10n.salarySplitsEnabled : l10n.salarySplits),
      subtitle: Text(message),
      trailing: TextButton(
          onPressed: onConfigure,
          child: Text(available || group.visibility == 'shared'
              ? l10n.configure
              : l10n.info)),
    ));
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group, required this.balance});

  final ExpenseGroup group;
  final int balance;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
                  balance >= 0 ? l10n.yourGroupBalance : l10n.youCurrentlyOwe,
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
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final subtitle = !member.accepted
        ? l10n.invitationPending
        : balance > 0
            ? l10n.getsBack(formatMoney(balance))
            : balance < 0
                ? l10n.owesAmount(formatMoney(balance.abs()))
                : l10n.groupBalanceSettled;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(child: Text(member.initials)),
      title: Text(isCurrentUser ? l10n.you : member.name),
      subtitle: Text(subtitle),
      trailing: !member.accepted
          ? Icon(Icons.hourglass_empty_rounded, color: colors.secondary)
          : isCurrentUser || balance == 0
              ? Icon(Icons.check_circle_rounded, color: colors.primary)
              : TextButton(
                  onPressed: onSettle,
                  child: Text(balance < 0 ? l10n.request : l10n.pay),
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
    final l10n = AppLocalizations.of(context)!;
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
          l10n.expenseSplitDetails(
            payer.name,
            expense.splitMode == 'salary' ? l10n.bySalary : l10n.split,
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

class _EmptyExpenses extends StatelessWidget {
  const _EmptyExpenses({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.receipt_long_outlined, size: 42),
            const SizedBox(height: 10),
            Text(l10n.noExpensesYet),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.addFirstExpense),
            ),
          ],
        ),
      ),
    );
  }
}
