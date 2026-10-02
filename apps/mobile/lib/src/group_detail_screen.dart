import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:vaquita_mx/src/features/app/application/app_cubit.dart';
import 'package:vaquita_mx/src/models.dart';
import 'package:vaquita_mx/src/sheets.dart';
import 'package:vaquita_mx/src/store.dart';
import 'package:vaquita_mx/l10n/app_localizations.dart';
import 'package:vaquita_mx/src/widgets/salary_inference_notice.dart';

part 'group_detail/settlement_sheet.dart';
part 'group_detail/salary_split_card.dart';
part 'group_detail/group_header.dart';
part 'group_detail/section_header.dart';
part 'group_detail/member_balance_tile.dart';
part 'group_detail/expense_card.dart';
part 'group_detail/expense_details_sheet.dart';
part 'group_detail/pending_payments_sheet.dart';
part 'group_detail/empty_expenses.dart';

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
                group: group,
                balance: store.currentUserBalance(group),
                onTap: () => showPendingPaymentsSheet(
                  context,
                  group,
                  store.paymentRelations(group),
                  store.currentUserId,
                ),
              ),
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
                        relationshipBalance: store.balanceWith(
                          group,
                          group.members
                              .where((member) => member.active)
                              .elementAt(index),
                        ),
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
                          store.balanceWith(
                            group,
                            group.members
                                .where((member) => member.active)
                                .elementAt(index),
                          ),
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
                  '${group.visibility == 'shared' ? l10n.sharedGroup : l10n.personalGroup} Â· ${group.members.map((member) => member.name).join(', ')}'),
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
              if (group.salarySplitEnabled) ...[
                const SalaryInferenceNotice(),
                const SizedBox(height: 12),
              ],
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
