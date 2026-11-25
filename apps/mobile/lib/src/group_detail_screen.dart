import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:vaquita_mx/l10n/app_localizations.dart';
import 'package:vaquita_mx/src/expense_allocation.dart';
import 'package:vaquita_mx/src/features/app/application/app_cubit.dart';
import 'package:vaquita_mx/src/financial_statistics.dart';
import 'package:vaquita_mx/src/models.dart';
import 'package:vaquita_mx/src/sheets.dart';
import 'package:vaquita_mx/src/store.dart';
import 'package:vaquita_mx/src/theme/vaquita_theme.dart';
import 'package:vaquita_mx/src/widgets/group_emoji_picker.dart';
import 'package:vaquita_mx/src/widgets/group_storage_badge.dart';
import 'package:vaquita_mx/src/widgets/salary_inference_notice.dart';
import 'package:vaquita_mx/src/widgets/vaquita_brand.dart';

part 'group_detail/settlement_sheet.dart';
part 'group_detail/settlement_details_sheet.dart';
part 'group_detail/salary_split_card.dart';
part 'group_detail/group_header.dart';
part 'group_detail/section_header.dart';
part 'group_detail/member_balance_tile.dart';
part 'group_detail/expense_card.dart';
part 'group_detail/expense_details_sheet.dart';
part 'group_detail/pending_payments_sheet.dart';
part 'group_detail/financial_statistics_sheet.dart';
part 'group_detail/empty_expenses.dart';

class GroupDetailScreen extends StatelessWidget {
  const GroupDetailScreen({
    required this.store,
    required this.groupId,
    super.key,
  });

  final DemoStore store;
  final String groupId;

  Future<void> _addExpense(
    BuildContext context,
    ExpenseGroup group, {
    Expense? replacingExpense,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final input = await showAddExpenseSheet(
      context,
      group,
      initialExpense: replacingExpense,
    );
    if (input == null || !context.mounted) return;
    final created = await context.read<AppCubit>().addExpense(
          groupId: group.id,
          description: input.description,
          amountCents: input.amountCents,
          payerId: input.payerId,
          payers: input.payers,
          participantIds: input.participantIds,
          splitMode: input.splitMode,
          shares: input.shares,
          percentages: input.percentages,
          splitOverpayment: input.splitOverpayment,
          replacesExpenseId: replacingExpense?.id,
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          created
              ? (store.lastMutationQueuedOffline
                  ? l10n.savedOfflineWillSync
                  : l10n.expenseAdded(input.description))
              : l10n.couldNotAddExpense,
        ),
      ),
    );
  }

  Future<void> _reverseAndReplaceExpense(
    BuildContext context,
    ExpenseGroup group,
    Expense expense,
    String reason,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final reversed = await context.read<AppCubit>().reverseExpense(
          groupId: group.id,
          expenseId: expense.id,
          reason: reason,
        );
    if (!context.mounted) return;
    if (!reversed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.couldNotReverseRecord)),
      );
      return;
    }
    final updatedGroup = store.groupById(group.id);
    await _addExpense(context, updatedGroup, replacingExpense: expense);
  }

  Future<void> _reverseAndReplaceSettlement(
    BuildContext context,
    ExpenseGroup group,
    Settlement settlement,
    String reason,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final reversed = await context.read<AppCubit>().reverseSettlement(
          groupId: group.id,
          settlementId: settlement.id,
          reason: reason,
        );
    if (!context.mounted) return;
    if (!reversed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.couldNotReverseRecord)),
      );
      return;
    }
    final updatedGroup = store.groupById(group.id);
    final selfMember = updatedGroup.members.where(
      (member) =>
          member.userId == store.currentUserId ||
          member.id == store.currentUserId,
    );
    final selfId = selfMember.isNotEmpty
        ? selfMember.first.id
        : (updatedGroup.members.isNotEmpty
            ? updatedGroup.members.first.id
            : '');
    final counterpartyId = settlement.fromMemberId == selfId
        ? settlement.toMemberId
        : settlement.fromMemberId;
    final counterpartyMatches =
        updatedGroup.members.where((member) => member.id == counterpartyId);
    if (counterpartyMatches.isEmpty) return;
    final counterparty = counterpartyMatches.first;
    final relationshipBalance = store.balanceWith(updatedGroup, counterparty);
    if (relationshipBalance == 0) return;
    showSettlementSheet(
      context,
      store,
      updatedGroup,
      counterparty,
      relationshipBalance,
      replacesSettlementId: settlement.id,
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
        final activeMembers =
            group.members.where((member) => member.active).toList();
        return Scaffold(
          appBar: AppBar(
            title: Text(group.name),
            actions: [
              IconButton(
                key: const Key('group-financial-statistics-button'),
                tooltip: l10n.financialStatistics,
                onPressed: () => showFinancialStatisticsSheet(context, group),
                icon: const Icon(Icons.insights_outlined),
              ),
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
                serverBacked: store.isServerBacked(group),
                pendingCount: store.pendingMutationCountForGroup(group.id),
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
                detail: l10n.membersCount(activeMembers.length),
              ),
              const SizedBox(height: 10),
              Card(
                child: Column(
                  children: [
                    for (var index = 0;
                        index < activeMembers.length;
                        index++) ...[
                      Builder(
                        builder: (context) {
                          final member = activeMembers[index];
                          final relationshipBalance =
                              store.balanceWith(group, member);
                          return _MemberBalanceTile(
                            member: member,
                            balance: balances[member.id] ?? 0,
                            relationshipBalance: relationshipBalance,
                            isCurrentUser:
                                member.userId == store.currentUserId ||
                                    member.id == store.currentUserId,
                            sharedServerGroup: store.canRequestPayment(group),
                            onSettle: () => _showSettlement(
                              context,
                              group,
                              member,
                              relationshipBalance,
                            ),
                          );
                        },
                      ),
                      if (index != activeMembers.length - 1)
                        const Divider(height: 1, indent: 72),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _SectionHeader(
                title: l10n.expenses,
                detail: formatMoney(group.totalSpentCents),
                isMoneyDetail: true,
              ),
              const SizedBox(height: 10),
              if (group.expenses.isEmpty)
                _EmptyExpenses(onAdd: () => _addExpense(context, group))
              else
                for (final expense in group.expenses) ...[
                  _ExpenseCard(
                    store: store,
                    group: group,
                    expense: expense,
                    onReverseAndReplace: (target, reason) =>
                        _reverseAndReplaceExpense(
                      context,
                      group,
                      target,
                      reason,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              if (group.settlements.isNotEmpty) ...[
                const SizedBox(height: 16),
                _SectionHeader(
                  title: l10n.settlementsHistory,
                  detail: '${group.settlements.length}',
                ),
                const SizedBox(height: 10),
                for (final settlement in group.settlements) ...[
                  _SettlementCard(
                    store: store,
                    group: group,
                    settlement: settlement,
                    onReverseAndReplace: (target, reason) =>
                        _reverseAndReplaceSettlement(
                      context,
                      group,
                      target,
                      reason,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _showGroupInfo(BuildContext context, ExpenseGroup group) async {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final editGroup = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      group.emoji,
                      style: const TextStyle(fontSize: 26),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      group.name,
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '${group.visibility == 'shared' && store.canUseServerFeatures(group) ? l10n.sharedGroup : l10n.personalGroup} · ${group.members.where((m) => m.active).map((member) => member.name).join(', ')}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.pop(sheetContext, true),
                icon: const Icon(Icons.edit_outlined),
                label: Text(l10n.editGroupContacts),
              ),
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
    final serverSharedGroup =
        group.visibility == 'shared' && store.canUseServerFeatures(group);
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
      showDragHandle: true,
      builder: (sheet) => Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          4,
          24,
          24 + MediaQuery.viewInsetsOf(sheet).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.editGroupContacts,
                style: Theme.of(sheet).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: name,
                decoration: InputDecoration(
                  labelText: l10n.groupName,
                  prefixIcon: const Icon(Icons.groups_outlined),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: emoji,
                readOnly: true,
                onTap: () async {
                  final selected = await showGroupEmojiPicker(sheet);
                  if (selected != null) emoji.text = selected;
                },
                decoration: InputDecoration(
                  labelText: l10n.groupIcon,
                  prefixIcon: const Icon(Icons.emoji_emotions_outlined),
                  suffixIcon: const Icon(Icons.expand_more_rounded),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () async {
                  final updated = await context.read<AppCubit>().updateGroup(
                    group.id,
                    {'name': name.text, 'emoji': emoji.text},
                  );
                  if (!updated) {
                    if (sheet.mounted) {
                      ScaffoldMessenger.of(sheet).showSnackBar(
                        SnackBar(content: Text(l10n.couldNotUpdateGroup)),
                      );
                    }
                    return;
                  }
                  if (sheet.mounted) Navigator.pop(sheet);
                },
                child: Text(l10n.saveGroup),
              ),
              if (group.salarySplitAvailable)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: group.salarySplitEnabled,
                  title: Text(l10n.enableSalarySplits),
                  subtitle: Text(l10n.everyMemberConsented),
                  onChanged: (value) async {
                    final updated = await store.updateGroup(
                      group.id,
                      {'salary_split_enabled': value},
                    );
                    if (!updated) {
                      if (sheet.mounted) {
                        ScaffoldMessenger.of(sheet).showSnackBar(
                          SnackBar(content: Text(l10n.couldNotUpdateGroup)),
                        );
                      }
                      return;
                    }
                    if (sheet.mounted) Navigator.pop(sheet);
                  },
                )
              else if (serverSharedGroup)
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 8),
                  child: Text(
                    l10n.salarySplitsUnlock,
                    style: Theme.of(sheet).textTheme.bodySmall,
                  ),
                ),
              if (group.salarySplitEnabled) ...[
                const SizedBox(height: 8),
                const SalaryInferenceNotice(),
              ],
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Divider(height: 1),
              ),
              TextField(
                controller: member,
                decoration: InputDecoration(
                  labelText: l10n.contactName,
                  prefixIcon: const Icon(Icons.person_add_alt_1_outlined),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: l10n.mexicanMobileNumber,
                  prefixIcon: const Icon(Icons.phone_iphone_rounded),
                ),
              ),
              if (serverSharedGroup)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    l10n.pendingUntilAccept,
                    style: Theme.of(sheet).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final appCubit = context.read<AppCubit>();
                  final added = await appCubit.addMember(
                    group.id,
                    member.text.trim(),
                    phone.text.trim(),
                  );
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
                        content: Text(
                          serverSharedGroup
                              ? l10n.invitationSent(member.text.trim())
                              : l10n.contactAdded,
                        ),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: Text(
                  serverSharedGroup ? l10n.sendInvitation : l10n.addContact,
                ),
              ),
              if (serverSharedGroup && self.isNotEmpty) ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: self.single.salarySharing,
                  title: Text(l10n.allowGroupSalary),
                  subtitle: Text(l10n.salaryPrivacy),
                  onChanged: (value) async {
                    await context.read<AppCubit>().updateMember(
                      group.id,
                      self.single.id,
                      {'salary_sharing': value},
                    );
                    if (sheet.mounted) Navigator.pop(sheet);
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
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
