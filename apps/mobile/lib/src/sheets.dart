import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaquita_mx/src/models.dart';

class NewGroupInput {
  const NewGroupInput({required this.name, required this.memberNames});

  final String name;
  final List<String> memberNames;
}

class NewExpenseInput {
  const NewExpenseInput({
    required this.description,
    required this.amountCents,
    required this.payerId,
    required this.participantIds,
  });

  final String description;
  final int amountCents;
  final String payerId;
  final List<String> participantIds;
}

Future<NewGroupInput?> showCreateGroupSheet(BuildContext context) {
  return showModalBottomSheet<NewGroupInput>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _CreateGroupSheet(),
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
  const _CreateGroupSheet();

  @override
  State<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<_CreateGroupSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _membersController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _membersController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      NewGroupInput(
        name: _nameController.text.trim(),
        memberNames: _membersController.text
            .split(',')
            .map((name) => name.trim())
            .where((name) => name.isNotEmpty)
            .toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
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
              'Create a group',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'You are added automatically. Separate other members with commas.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            TextFormField(
              key: const Key('group-name-field'),
              controller: _nameController,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Group name',
                hintText: 'Beach weekend',
                prefixIcon: Icon(Icons.groups_rounded),
              ),
              validator: (value) => value == null || value.trim().length < 2
                  ? 'Enter a group name'
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: const Key('group-members-field'),
              controller: _membersController,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Members',
                hintText: 'Ana, Diego, Sofía',
                prefixIcon: Icon(Icons.person_add_alt_1_rounded),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Add at least one other member'
                  : null,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('create-group-submit'),
              onPressed: _submit,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create group'),
            ),
          ],
        ),
      ),
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
    if (!_formKey.currentState!.validate()) return;
    if (_participantIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one participant.')),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              'Add an expense',
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
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'Dinner',
                prefixIcon: Icon(Icons.receipt_long_rounded),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Add a description'
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
              decoration: const InputDecoration(
                labelText: 'Amount',
                hintText: '0.00',
                prefixText: r'$ ',
                suffixText: 'MXN',
              ),
              validator: (_) => _parseAmount() == null
                  ? 'Enter an amount greater than zero'
                  : null,
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              key: const Key('expense-payer-field'),
              initialValue: _payerId,
              decoration: const InputDecoration(
                labelText: 'Paid by',
                prefixIcon: Icon(Icons.account_balance_wallet_rounded),
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
            Text(
              'Split equally between',
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
                onChanged: (selected) {
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
              label: const Text('Save expense'),
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
