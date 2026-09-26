part of '../sheets.dart';

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
