part of '../sheets.dart';

class _AddExpenseSheet extends StatefulWidget {
  const _AddExpenseSheet({required this.group, this.initialExpense});

  final ExpenseGroup group;
  final Expense? initialExpense;

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
  final Map<String, TextEditingController> _shareAmountControllers = {};
  final Map<String, TextEditingController> _percentageControllers = {};
  var _splitMode = 'equal';
  var _splitOverpayment = true;
  var _exactSharesEdited = false;
  var _percentagesEdited = false;
  var _payerAmountsEdited = false;

  @override
  void initState() {
    super.initState();
    for (final member in widget.group.members) {
      _payerAmountControllers[member.id] = TextEditingController();
      _shareAmountControllers[member.id] = TextEditingController();
      _percentageControllers[member.id] = TextEditingController();
    }
    final activeIds = {
      for (final member in widget.group.members)
        if (member.active) member.id,
    };
    final initial = widget.initialExpense;
    if (initial == null) {
      _payerIds = {widget.group.members.first.id};
      _participantIds = widget.group.members.map((member) => member.id).toSet();
      return;
    }
    _descriptionController.text = initial.description;
    _amountController.text = _formatCentavos(initial.amountCents);
    final initialPayers = initial.payers.isEmpty
        ? [
            ExpensePayer(
              memberId: initial.payerId,
              amountCents: initial.amountCents,
            ),
          ]
        : initial.payers;
    _payerIds = {
      for (final payer in initialPayers)
        if (activeIds.contains(payer.memberId)) payer.memberId,
    };
    if (_payerIds.isEmpty) {
      _payerIds = {widget.group.members.first.id};
    }
    final singleExactPayer = initialPayers.length == 1 &&
        initialPayers.first.amountCents == initial.amountCents &&
        _payerIds.length == 1 &&
        _payerIds.contains(initialPayers.first.memberId);
    if (singleExactPayer) {
      if (!initial.splitOverpayment) {
        _payerAmountControllers[initialPayers.first.memberId]?.text =
            _formatCentavos(initial.amountCents);
      }
      _payerAmountsEdited = false;
    } else {
      for (final payer in initialPayers) {
        final controller = _payerAmountControllers[payer.memberId];
        if (controller != null) {
          controller.text = _formatCentavos(payer.amountCents);
        }
      }
      _payerAmountsEdited = true;
    }
    _participantIds = {
      for (final id in initial.participantIds)
        if (activeIds.contains(id)) id,
    };
    if (_participantIds.isEmpty) {
      _participantIds = widget.group.members.map((member) => member.id).toSet();
    }
    _splitMode = initial.splitMode == 'salary' &&
            (!widget.group.salarySplitEnabled ||
                !widget.group.salarySplitAvailable)
        ? 'equal'
        : initial.splitMode;
    _splitOverpayment = initial.splitOverpayment;
    if (_splitMode == 'exact') {
      final sourceShares = initial.consumptionShares.isNotEmpty
          ? initial.consumptionShares
          : initial.shares;
      for (final entry in sourceShares.entries) {
        final controller = _shareAmountControllers[entry.key];
        if (controller != null) {
          controller.text = _formatCentavos(entry.value);
        }
      }
      _exactSharesEdited = sourceShares.isNotEmpty;
    } else if (_splitMode == 'percentage') {
      for (final entry in initial.percentages.entries) {
        final controller = _percentageControllers[entry.key];
        if (controller != null) {
          controller.text = ExpenseAllocation.formatPercentageBps(entry.value);
        }
      }
      _percentagesEdited = initial.percentages.isNotEmpty;
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    for (final controller in _payerAmountControllers.values) {
      controller.dispose();
    }
    for (final controller in _shareAmountControllers.values) {
      controller.dispose();
    }
    for (final controller in _percentageControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  int? _parseAmount() {
    return _parseCentavos(_amountController.text);
  }

  int? _parseCentavos(String input, {bool allowZero = false}) {
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
    return value > 0 || allowZero && value == 0 ? value : null;
  }

  String _formatCentavos(int amountCents) {
    final sign = amountCents < 0 ? '-' : '';
    final absolute = amountCents.abs();
    return '$sign${absolute ~/ 100}.${(absolute % 100).toString().padLeft(2, '0')}';
  }

  void _populateExactShares() {
    // Existing multiple-payer behavior treats every contributed centavo as
    // group spending, even when it exceeds the entered expense amount. Until
    // the user edits an exact share, keep the generated shares in sync with
    // that allocation total.
    final total = _parseAmount();
    if (total == null || _participantIds.isEmpty) return;
    final ordered = widget.group.members
        .where((member) => _participantIds.contains(member.id))
        .toList();
    final shares = ExpenseAllocation.equalShares(
      allocationTotalCents: total,
      participantCount: ordered.length,
    );
    for (final (index, member) in ordered.indexed) {
      _shareAmountControllers[member.id]!.text = _formatCentavos(shares[index]);
    }
  }

  List<Member> get _orderedParticipants => widget.group.members
      .where((member) => _participantIds.contains(member.id))
      .toList();

  void _populatePercentages() {
    final ordered = _orderedParticipants;
    if (ordered.isEmpty) return;
    final values = ExpenseAllocation.equalPercentageBps(ordered.length);
    for (final (index, member) in ordered.indexed) {
      _percentageControllers[member.id]!.text =
          ExpenseAllocation.formatPercentageBps(values[index]);
    }
  }

  int? get _allocatedPercentageBps {
    var total = 0;
    for (final member in _orderedParticipants) {
      final value = ExpenseAllocation.parsePercentageBps(
        _percentageControllers[member.id]!.text,
        allowZero: true,
      );
      if (value == null) return null;
      total += value;
    }
    return total;
  }

  Map<String, int>? _draftPercentagesBps() {
    final ordered = _orderedParticipants;
    if (ordered.isEmpty) return null;
    final result = <String, int>{};
    var total = 0;
    for (final member in ordered) {
      final bps = ExpenseAllocation.parsePercentageBps(
        _percentageControllers[member.id]!.text,
      );
      if (bps == null) return null;
      result[member.id] = bps;
      total += bps;
    }
    if (total != ExpenseAllocation.percentageTotalBps) return null;
    return result;
  }

  Map<String, int>? _percentagePreviewShares() {
    final amountCents = _parseAmount();
    final percentagesBps = _draftPercentagesBps();
    if (amountCents == null || percentagesBps == null) return null;
    final payers = _draftPayers();
    final paidAmount = payers == null
        ? amountCents
        : ExpenseAllocation.total(
              expenseTotalCents: amountCents,
              payers: payers,
            ) ??
            amountCents;
    return ExpenseAllocation.percentageFinalShares(
      amountCents: amountCents,
      paidAmountCents: paidAmount,
      splitOverpayment: _splitOverpayment,
      participantIds: [for (final member in _orderedParticipants) member.id],
      percentagesBps: percentagesBps,
    );
  }

  int? get _exactAllocatedCentavos {
    var total = 0;
    for (final id in _participantIds) {
      final value = _parseCentavos(
        _shareAmountControllers[id]!.text,
        allowZero: true,
      );
      if (value == null) return null;
      total += value;
    }
    return total;
  }

  List<ExpensePayer>? _draftPayers() {
    final amountCents = _parseAmount();
    if (amountCents == null) return null;
    final payers = <ExpensePayer>[];
    for (final member in widget.group.members) {
      if (!_payerIds.contains(member.id)) continue;
      final entered = _payerAmountControllers[member.id]!.text.trim();
      final contribution =
          entered.isEmpty && _payerIds.length == 1 && _splitOverpayment
              ? amountCents
              : _parseCentavos(entered);
      if (contribution == null) return null;
      payers.add(ExpensePayer(memberId: member.id, amountCents: contribution));
    }
    return payers;
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
    final payers = _draftPayers();
    final allocationTotal = payers == null
        ? null
        : ExpenseAllocation.total(
            expenseTotalCents: amountCents,
            payers: payers,
          );
    if (payers == null || allocationTotal == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.amountGreaterZero)));
      return;
    }
    if (_splitOverpayment &&
        _splitMode == 'exact' &&
        !ExpenseAllocation.exactSharesMatch(
          allocatedCents: _exactAllocatedCentavos,
          allocationTotalCents: amountCents,
        )) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.exactSharesMustMatchTotal)));
      return;
    }
    if (_splitMode == 'exact' &&
        !ExpenseAllocation.canAllocateExactOverpayment(
          expenseTotalCents: amountCents,
          payers: payers,
          consumption: {
            for (final member in widget.group.members)
              if (_participantIds.contains(member.id))
                member.id: _parseCentavos(
                  _shareAmountControllers[member.id]!.text,
                  allowZero: true,
                )!,
          },
        )) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.exactOverpaymentNeedsTotalChange)),
      );
      return;
    }
    Map<String, int>? validatedPercentages;
    if (_splitMode == 'percentage') {
      validatedPercentages = _draftPercentagesBps();
      if (validatedPercentages == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.percentagesMustTotalHundred)),
        );
        return;
      }
    }
    final orderedParticipantIds = [
      for (final member in _orderedParticipants) member.id,
    ];
    Navigator.pop(
      context,
      NewExpenseInput(
        description: _descriptionController.text.trim(),
        amountCents: amountCents,
        payerId: payers.first.memberId,
        payers: payers,
        participantIds: orderedParticipantIds,
        splitMode: _splitMode,
        splitOverpayment: _splitOverpayment,
        shares: _splitMode == 'exact'
            ? [
                for (final member in _orderedParticipants)
                  ExpenseShare(
                    memberId: member.id,
                    amountCents: _parseCentavos(
                      _shareAmountControllers[member.id]!.text,
                      allowZero: true,
                    )!,
                  ),
              ]
            : const [],
        percentages: _splitMode == 'percentage'
            ? [
                for (final memberId in orderedParticipantIds)
                  ExpensePercentage(
                    memberId: memberId,
                    percentageBps: validatedPercentages![memberId]!,
                  ),
              ]
            : const [],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final percentagePreview =
        _splitMode == 'percentage' ? _percentagePreviewShares() : null;
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
              onChanged: (value) {
                if (_payerIds.length == 1 && !_payerAmountsEdited) {
                  final singlePayerId = _payerIds.first;
                  if (!_splitOverpayment) {
                    _payerAmountControllers[singlePayerId]!.text = value;
                  }
                }
                if (_splitMode == 'exact' && !_exactSharesEdited) {
                  setState(_populateExactShares);
                } else if (_splitMode == 'percentage') {
                  setState(() {});
                }
              },
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
                  key: Key('expense-payer-checkbox-${member.id}'),
                  value: _payerIds.contains(member.id),
                  onChanged: (selected) => setState(() {
                    if (selected ?? false) {
                      _payerIds.add(member.id);
                    } else if (_payerIds.length > 1) {
                      _payerIds.remove(member.id);
                      _payerAmountControllers[member.id]!.clear();
                    }
                    if (_splitMode == 'exact' && !_exactSharesEdited) {
                      _populateExactShares();
                    }
                  }),
                ),
                Expanded(child: Text(member.name)),
                if (_payerIds.contains(member.id))
                  SizedBox(
                      width: 110,
                      child: TextFormField(
                        key: Key('expense-payer-${member.id}'),
                        controller: _payerAmountControllers[member.id],
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                        ],
                        onChanged: (_) {
                          _payerAmountsEdited = true;
                          if (_splitMode == 'exact' && !_exactSharesEdited) {
                            setState(_populateExactShares);
                          } else if (_splitMode == 'percentage') {
                            setState(() {});
                          }
                        },
                        decoration: const InputDecoration(
                            prefixText: r'$ ', hintText: '0.00'),
                      )),
              ]),
            CheckboxListTile(
              key: const Key('expense-split-overpayment-checkbox'),
              contentPadding: EdgeInsets.zero,
              value: _splitOverpayment,
              title: Text(l10n.splitOverpayment),
              subtitle: Text(l10n.splitOverpaymentDescription),
              onChanged: (value) => setState(() {
                _splitOverpayment = value ?? true;
              }),
            ),
            const SizedBox(height: 18),
            SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 'equal', label: Text(l10n.equal)),
                  ButtonSegment(
                      value: 'percentage', label: Text(l10n.byPercentage)),
                  if (widget.group.salarySplitEnabled)
                    ButtonSegment(value: 'salary', label: Text(l10n.bySalary)),
                  ButtonSegment(value: 'exact', label: Text(l10n.exactAmount)),
                ],
                selected: {_splitMode},
                onSelectionChanged: (value) => setState(() {
                      _splitMode = value.first;
                      if (_splitMode == 'salary') {
                        _participantIds.removeWhere((id) => !widget
                            .group.members
                            .firstWhere((m) => m.id == id)
                            .salarySharing);
                      }
                      if (_splitMode == 'exact') {
                        _exactSharesEdited = false;
                        _populateExactShares();
                      }
                      if (_splitMode == 'percentage') {
                        _percentagesEdited = false;
                        _populatePercentages();
                      }
                    })),
            if (_splitMode == 'salary')
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(l10n.salaryEligibleOnly)),
            Text(
              _splitMode == 'salary'
                  ? l10n.splitBySalaryBetween
                  : _splitMode == 'exact'
                      ? l10n.exactSplitBetween
                      : _splitMode == 'percentage'
                          ? l10n.percentageSplitBetween
                          : l10n.splitEquallyBetween,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            for (final member in widget.group.members)
              Row(children: [
                Expanded(
                  child: CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: _participantIds.contains(member.id),
                    title: Text(member.name),
                    subtitle: _splitMode == 'percentage' &&
                            _participantIds.contains(member.id)
                        ? Text(
                            percentagePreview != null
                                ? formatMoney(percentagePreview[member.id]!)
                                : '—',
                            key: Key('expense-percentage-preview-${member.id}'),
                          )
                        : null,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: _splitMode == 'salary' && !member.salarySharing
                        ? null
                        : (selected) {
                            setState(() {
                              if (selected ?? false) {
                                _participantIds.add(member.id);
                                if (_splitMode == 'exact' &&
                                    !_exactSharesEdited) {
                                  _populateExactShares();
                                }
                                if (_splitMode == 'percentage' &&
                                    !_percentagesEdited) {
                                  _populatePercentages();
                                }
                              } else {
                                _participantIds.remove(member.id);
                                if (_splitMode == 'percentage' &&
                                    !_percentagesEdited) {
                                  _populatePercentages();
                                }
                              }
                            });
                          },
                  ),
                ),
                if (_splitMode == 'exact' &&
                    _participantIds.contains(member.id))
                  SizedBox(
                    width: 110,
                    child: TextFormField(
                      key: Key('expense-share-${member.id}'),
                      controller: _shareAmountControllers[member.id],
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      onChanged: (_) => setState(() {
                        _exactSharesEdited = true;
                      }),
                      decoration: InputDecoration(
                        labelText: l10n.consumed,
                        prefixText: r'$ ',
                        hintText: '0.00',
                      ),
                    ),
                  ),
                if (_splitMode == 'percentage' &&
                    _participantIds.contains(member.id))
                  SizedBox(
                    width: 110,
                    child: TextFormField(
                      key: Key('expense-percentage-${member.id}'),
                      controller: _percentageControllers[member.id],
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      onChanged: (_) => setState(() {
                        _percentagesEdited = true;
                      }),
                      decoration: const InputDecoration(
                        suffixText: '%',
                        hintText: '0.00',
                      ),
                    ),
                  ),
              ]),
            if (_splitMode == 'exact')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n.exactAmountRemaining(_formatCentavos(
                    (_parseAmount() ?? 0) - (_exactAllocatedCentavos ?? 0),
                  )),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            if (_splitMode == 'percentage')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n.percentageRemaining(
                    ExpenseAllocation.formatPercentageBps(
                      ExpenseAllocation.percentageTotalBps -
                          (_allocatedPercentageBps ?? 0),
                    ),
                  ),
                  key: const Key('expense-percentage-remaining'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
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
