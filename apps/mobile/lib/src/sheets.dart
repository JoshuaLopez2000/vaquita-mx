import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaquita_mx/src/models.dart';
import 'package:vaquita_mx/l10n/app_localizations.dart';

class NewGroupInput {
  const NewGroupInput(
      {required this.name,
      required this.memberNames,
      required this.members,
      required this.emoji,
      required this.visibility,
      required this.salarySplitEnabled});

  final String name;
  final List<String> memberNames;
  final List<Map<String, String>> members;
  final String emoji;
  final String visibility;
  final bool salarySplitEnabled;
}

class GroupMemberDraft {
  const GroupMemberDraft({required this.name, this.phone = ''});
  final String name;
  final String phone;
}

class NewExpenseInput {
  const NewExpenseInput({
    required this.description,
    required this.amountCents,
    required this.payerId,
    required this.participantIds,
    required this.splitMode,
  });

  final String description;
  final int amountCents;
  final String payerId;
  final List<String> participantIds;
  final String splitMode;
}

Future<NewGroupInput?> showCreateGroupSheet(
  BuildContext context, {
  List<AppContact> contacts = const [],
}) {
  return showModalBottomSheet<NewGroupInput>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _CreateGroupSheet(contacts: contacts),
  );
}

Future<NewExpenseInput?> showAddExpenseSheet(
  BuildContext context,
  ExpenseGroup group,
) {
  return showModalBottomSheet<NewExpenseInput>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AddExpenseSheet(group: group),
  );
}

class _CreateGroupSheet extends StatefulWidget {
  const _CreateGroupSheet({required this.contacts});

  final List<AppContact> contacts;

  @override
  State<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<_CreateGroupSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _memberNameController = TextEditingController();
  final _memberPhoneController = TextEditingController();
  final _members = <GroupMemberDraft>[];
  final _emojiController = TextEditingController(text: '👥');
  var _visibility = 'personal';
  var _salarySplits = false;

  @override
  void dispose() {
    _nameController.dispose();
    _memberNameController.dispose();
    _memberPhoneController.dispose();
    _emojiController.dispose();
    super.dispose();
  }

  void _submit() {
    final l10n = AppLocalizations.of(context)!;
    if (!_formKey.currentState!.validate()) return;
    final pendingName = _memberNameController.text.trim();
    final pendingPhone = _memberPhoneController.text.trim();
    if (pendingName.isNotEmpty || pendingPhone.isNotEmpty) {
      if (pendingName.isEmpty || pendingPhone.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.memberNeedsNamePhone)),
        );
        return;
      }
      _members.add(GroupMemberDraft(name: pendingName, phone: pendingPhone));
    }
    if (_members.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.addAtLeastOneMember)),
      );
      return;
    }
    Navigator.pop(
      context,
      NewGroupInput(
        name: _nameController.text.trim(),
        memberNames: _members.map((member) => member.name).toList(),
        members: List.unmodifiable(_members
            .map((member) => {'name': member.name, 'phone': member.phone})
            .toList()),
        emoji: _emojiController.text.trim(),
        visibility: _visibility,
        salarySplitEnabled: _salarySplits,
      ),
    );
  }

  void _addMember() {
    final l10n = AppLocalizations.of(context)!;
    final name = _memberNameController.text.trim();
    final phone = _memberPhoneController.text.trim();
    if (name.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.enterNamePhone)),
      );
      return;
    }
    setState(() {
      _members.add(GroupMemberDraft(name: name, phone: phone));
      _memberNameController.clear();
      _memberPhoneController.clear();
    });
  }

  void _toggleContact(AppContact contact) {
    setState(() {
      final index =
          _members.indexWhere((member) => member.phone == contact.phone);
      if (index >= 0) {
        _members.removeAt(index);
      } else {
        _members
            .add(GroupMemberDraft(name: contact.name, phone: contact.phone));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
          child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SheetHandle(),
            Text(
              l10n.createAGroup,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.createGroupDescription,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            TextFormField(
              key: const Key('group-name-field'),
              controller: _nameController,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: l10n.groupName,
                hintText: l10n.beachWeekend,
                prefixIcon: const Icon(Icons.groups_rounded),
              ),
              validator: (value) => value == null || value.trim().length < 2
                  ? l10n.enterGroupName
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
                controller: _emojiController,
                decoration: InputDecoration(
                    labelText: l10n.groupIcon,
                    prefixIcon: const Icon(Icons.emoji_emotions_outlined))),
            const SizedBox(height: 10),
            SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'personal', label: Text(l10n.personal)),
                  ButtonSegment(value: 'shared', label: Text(l10n.shared))
                ],
                selected: {
                  _visibility
                },
                onSelectionChanged: (value) =>
                    setState(() => _visibility = value.first)),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _salarySplits,
                title: Text(l10n.allowSalarySplits),
                subtitle: Text(l10n.salaryOptInOnly),
                onChanged: (value) => setState(() => _salarySplits = value)),
            if (widget.contacts.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(l10n.addSavedContacts,
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final contact in widget.contacts)
                    FilterChip(
                      label: Text(contact.name),
                      selected: _members
                          .any((member) => member.phone == contact.phone),
                      onSelected: (_) => _toggleContact(contact),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 6),
            TextFormField(
              key: const Key('group-members-field'),
              controller: _memberNameController,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _addMember(),
              decoration: InputDecoration(
                labelText: l10n.memberName,
                hintText: l10n.memberNamesExample,
                prefixIcon: const Icon(Icons.person_add_alt_1_rounded),
              ),
              validator: (_) => null,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _memberPhoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: l10n.mexicanMobileNumber,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: l10n.addMember,
                  onPressed: _addMember,
                ),
              ),
              onSubmitted: (_) => _addMember(),
            ),
            if (_members.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (var index = 0; index < _members.length; index++)
                      InputChip(
                        label: Text(_members[index].phone.isEmpty
                            ? _members[index].name
                            : '${_members[index].name} · ${_members[index].phone}'),
                        onDeleted: () =>
                            setState(() => _members.removeAt(index)),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('create-group-submit'),
              onPressed: _submit,
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.createGroup),
            ),
          ],
        ),
      )),
    );
  }
}

class _AddExpenseSheet extends StatefulWidget {
  const _AddExpenseSheet({required this.group});

  final ExpenseGroup group;

  @override
  State<_AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<_AddExpenseSheet> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  late String _payerId;
  late final Set<String> _participantIds;
  var _splitMode = 'equal';

  @override
  void initState() {
    super.initState();
    _payerId = widget.group.members.first.id;
    _participantIds = widget.group.members.map((member) => member.id).toSet();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  int? _parseAmount() {
    final normalized = _amountController.text.replaceAll(',', '').trim();
    final value = double.tryParse(normalized);
    if (value == null || !value.isFinite || value <= 0) return null;
    return (value * 100).round();
  }

  void _submit() {
    final l10n = AppLocalizations.of(context)!;
    if (!_formKey.currentState!.validate()) return;
    if (_participantIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.selectParticipant)),
      );
      return;
    }
    Navigator.pop(
      context,
      NewExpenseInput(
        description: _descriptionController.text.trim(),
        amountCents: _parseAmount()!,
        payerId: _payerId,
        participantIds: _participantIds.toList(),
        splitMode: _splitMode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SheetHandle(),
            Text(
              l10n.addAnExpense,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              key: const Key('expense-description-field'),
              controller: _descriptionController,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: l10n.expenseDescription,
                hintText: l10n.dinnerExample,
                prefixIcon: const Icon(Icons.receipt_long_rounded),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? l10n.addDescription
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: const Key('expense-amount-field'),
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: InputDecoration(
                labelText: l10n.amount,
                hintText: '0.00',
                prefixText: r'$ ',
                suffixText: 'MXN',
              ),
              validator: (_) =>
                  _parseAmount() == null ? l10n.amountGreaterZero : null,
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              key: const Key('expense-payer-field'),
              initialValue: _payerId,
              decoration: InputDecoration(
                labelText: l10n.paidBy,
                prefixIcon: const Icon(Icons.account_balance_wallet_rounded),
              ),
              items: [
                for (final member in widget.group.members)
                  DropdownMenuItem(
                    value: member.id,
                    child: Text(member.name),
                  ),
              ],
              onChanged: (value) => setState(() => _payerId = value!),
            ),
            const SizedBox(height: 18),
            if (widget.group.salarySplitEnabled)
              SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'equal', label: Text(l10n.equal)),
                    ButtonSegment(value: 'salary', label: Text(l10n.bySalary))
                  ],
                  selected: {
                    _splitMode
                  },
                  onSelectionChanged: (value) => setState(() {
                        _splitMode = value.first;
                        if (_splitMode == 'salary') {
                          _participantIds.removeWhere((id) => !widget
                              .group.members
                              .firstWhere((m) => m.id == id)
                              .salarySharing);
                        }
                      })),
            if (_splitMode == 'salary')
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(l10n.salaryEligibleOnly)),
            Text(
              _splitMode == 'salary'
                  ? l10n.splitBySalaryBetween
                  : l10n.splitEquallyBetween,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            for (final member in widget.group.members)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _participantIds.contains(member.id),
                title: Text(member.name),
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: _splitMode == 'salary' && !member.salarySharing
                    ? null
                    : (selected) {
                        setState(() {
                          if (selected ?? false) {
                            _participantIds.add(member.id);
                          } else {
                            _participantIds.remove(member.id);
                          }
                        });
                      },
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('add-expense-submit'),
              onPressed: _submit,
              icon: const Icon(Icons.check_rounded),
              label: Text(l10n.saveExpense),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 42,
        height: 4,
        margin: const EdgeInsets.only(bottom: 18),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }
}
