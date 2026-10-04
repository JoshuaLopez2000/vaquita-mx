part of '../sheets.dart';

class _AddExpenseSheet extends StatefulWidget {
  const _AddExpenseSheet({required this.group});

  final ExpenseGroup group;

  @override
  State<_AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<_AddExpenseSheet> {
  // Dart compiled for the web uses JavaScript numbers. Keep user-entered
  // centavos within its exact-integer range rather than rounding money.
  static const _maxSafeCentavos = 9007199254740991;

  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  late final Set<String> _payerIds;
  final Map<String, TextEditingController> _payerAmountControllers = {};
  late final Set<String> _participantIds;
  var _splitMode = 'equal';

  @override
  void initState() {
    super.initState();
    _payerIds = {widget.group.members.first.id};
    for (final member in widget.group.members) {
      _payerAmountControllers[member.id] = TextEditingController();
    }
    _participantIds = widget.group.members.map((member) => member.id).toSet();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    for (final controller in _payerAmountControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  int? _parseAmount() {
    return _parseCentavos(_amountController.text);
  }

  int? _parseCentavos(String input) {
    final normalized = input.replaceAll(',', '').trim();
    final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(normalized);
    if (match == null) return null;
    final pesos = int.tryParse(match.group(1)!);
    if (pesos == null) return null;
    final decimals = (match.group(2) ?? '').padRight(2, '0');
    final centavos = int.tryParse(decimals);
    if (centavos == null || pesos > (_maxSafeCentavos - centavos) ~/ 100) {
      return null;
    }
    final value = pesos * 100 + centavos;
    return value > 0 ? value : null;
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
    final amountCents = _parseAmount()!;
    final payers = <ExpensePayer>[];
    for (final member in widget.group.members) {
      if (!_payerIds.contains(member.id)) continue;
      final entered = _payerAmountControllers[member.id]!.text.trim();
      final contribution = entered.isEmpty && _payerIds.length == 1
          ? amountCents
          : _parseCentavos(entered);
      if (contribution == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.amountGreaterZero)));
        return;
      }
      payers.add(ExpensePayer(memberId: member.id, amountCents: contribution));
    }
    if (payers.fold<int>(0, (sum, payer) => sum + payer.amountCents) <
        amountCents) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.amountGreaterZero)));
      return;
    }
    Navigator.pop(
      context,
      NewExpenseInput(
        description: _descriptionController.text.trim(),
        amountCents: amountCents,
        payerId: payers.first.memberId,
        payers: payers,
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
            Text(l10n.paidBy, style: Theme.of(context).textTheme.titleMedium),
            for (final member in widget.group.members)
              Row(children: [
                Checkbox(
                  value: _payerIds.contains(member.id),
                  onChanged: (selected) => setState(() {
                    if (selected ?? false) {
                      _payerIds.add(member.id);
                    } else if (_payerIds.length > 1) {
                      _payerIds.remove(member.id);
                      _payerAmountControllers[member.id]!.clear();
                    }
                  }),
                ),
                Expanded(child: Text(member.name)),
                if (_payerIds.contains(member.id))
                  SizedBox(
                      width: 110,
                      child: TextFormField(
                        controller: _payerAmountControllers[member.id],
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                        ],
                        decoration: const InputDecoration(
                            prefixText: r'$ ', hintText: '0.00'),
                      )),
              ]),
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
