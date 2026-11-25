part of '../group_detail_screen.dart';

void showSettlementSheet(
  BuildContext context,
  DemoStore store,
  ExpenseGroup group,
  Member member,
  int balance, {
  String? replacesSettlementId,
  VoidCallback? onSettled,
}) {
  if (member.userId == store.currentUserId ||
      member.id == store.currentUserId ||
      balance == 0) {
    return;
  }
  final sharedServerGroup = store.canRequestPayment(group);
  if (sharedServerGroup && balance < 0) return;
  final memberOwes = balance > 0;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: SingleChildScrollView(
          child: _SettlementSheet(
            store: store,
            group: group,
            member: member,
            outstandingCents: balance.abs(),
            memberOwes: memberOwes,
            canRequestPayment: sharedServerGroup,
            replacesSettlementId: replacesSettlementId,
            onSettled: onSettled,
          ),
        ),
      ),
    ),
  );
}

class _SettlementSheet extends StatefulWidget {
  const _SettlementSheet({
    required this.store,
    required this.group,
    required this.member,
    required this.outstandingCents,
    required this.memberOwes,
    required this.canRequestPayment,
    this.replacesSettlementId,
    this.onSettled,
  });

  final DemoStore store;
  final ExpenseGroup group;
  final Member member;
  final int outstandingCents;
  final bool memberOwes;
  final bool canRequestPayment;
  final String? replacesSettlementId;
  final VoidCallback? onSettled;

  @override
  State<_SettlementSheet> createState() => _SettlementSheetState();
}

class _SettlementSheetState extends State<_SettlementSheet> {
  late final TextEditingController _amountController;
  String? _errorText;
  bool _submittingRequest = false;

  @override
  void initState() {
    super.initState();
    // The debtor starts with the whole outstanding amount ready to settle.
    _amountController = TextEditingController(
      text: _formatCentavos(widget.outstandingCents),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  int? _parseCentavos(String input) {
    final normalized = input.replaceAll(',', '').trim();
    final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(normalized);
    if (match == null) return null;
    final pesos = int.tryParse(match.group(1)!);
    if (pesos == null) return null;
    final decimals = (match.group(2) ?? '').padRight(2, '0');
    final centavos = int.tryParse(decimals);
    if (centavos == null) return null;
    final value = pesos * 100 + centavos;
    return value > 0 ? value : null;
  }

  String _formatCentavos(int amountCents) {
    final absolute = amountCents.abs();
    return '${absolute ~/ 100}.${(absolute % 100).toString().padLeft(2, '0')}';
  }

  int? get _amount {
    final parsed = _parseCentavos(_amountController.text);
    if (parsed == null || parsed > widget.outstandingCents) return null;
    return parsed;
  }

  void _settleEverything() {
    setState(() {
      _amountController.text = _formatCentavos(widget.outstandingCents);
      _errorText = null;
    });
  }

  Future<void> _requestPayment() async {
    if (_submittingRequest) return;
    final l10n = AppLocalizations.of(context)!;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _submittingRequest = true);
    final settled = await context.read<AppCubit>().requestPayment(
          groupId: widget.group.id,
          debtorId: widget.member.id,
          amountCents: widget.outstandingCents,
          description: l10n.paymentRequestDefaultDescription,
        );
    if (!mounted) return;
    setState(() => _submittingRequest = false);
    final createdRequest = widget.store.lastCreatedPaymentRequest;
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          settled ? l10n.paymentRequestCreated : l10n.couldNotConfirmPayment,
        ),
        action: settled && createdRequest != null
            ? SnackBarAction(
                label: l10n.viewRequest,
                onPressed: () {
                  navigator.push(
                    MaterialPageRoute<void>(
                      builder: (_) => PaymentRequestDetailScreen(
                        store: widget.store,
                        requestId: createdRequest.id,
                        initialRequest: createdRequest,
                      ),
                    ),
                  );
                },
              )
            : null,
      ),
    );
    if (settled) widget.onSettled?.call();
  }

  Future<void> _submitSettlement() async {
    final l10n = AppLocalizations.of(context)!;
    final amount = _amount;
    if (amount == null) {
      setState(() => _errorText = l10n.settlementAmountError);
      return;
    }
    final cubit = context.read<AppCubit>();
    final settled = widget.memberOwes
        ? await cubit.confirmReceivedPayment(
            groupId: widget.group.id,
            debtorId: widget.member.id,
            amountCents: amount,
            replacesSettlementId: widget.replacesSettlementId,
          )
        : await cubit.settleBalance(
            groupId: widget.group.id,
            memberId: widget.member.id,
            amountCents: amount,
            replacesSettlementId: widget.replacesSettlementId,
          );
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          settled
              ? widget.store.lastMutationQueuedOffline
                  ? l10n.savedOfflineWillSync
                  : widget.memberOwes
                      ? l10n.paymentReceivedRecorded
                      : l10n.settlementRecorded
              : l10n.couldNotConfirmPayment,
        ),
      ),
    );
    if (settled) widget.onSettled?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final vColors = VaquitaColors.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.qr_code_2_rounded,
                size: 34,
                color: colors.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            widget.memberOwes && widget.canRequestPayment
                ? l10n.requestFrom(widget.member.name)
                : widget.memberOwes
                    ? l10n.confirmReceivedFrom(widget.member.name)
                    : l10n.payContact(widget.member.name),
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          Text(
            '${formatMoney(widget.outstandingCents)} MXN',
            textAlign: TextAlign.center,
            style: VaquitaTheme.money(
              theme.textTheme.titleLarge,
              color: widget.memberOwes ? vColors.positive : vColors.negative,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: vColors.warningContainer.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: vColors.onWarningContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.canRequestPayment && widget.memberOwes
                        ? l10n.sharedCreditorSettlementDescription
                        : widget.canRequestPayment
                            ? l10n.demoPaymentDescription
                            : l10n.manualSettlementDescription,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: vColors.onWarningContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!widget.canRequestPayment || widget.memberOwes) ...[
            const SizedBox(height: 20),
            TextField(
              key: const Key('settlement-amount'),
              controller: _amountController,
              decoration: InputDecoration(
                labelText: l10n.settlementAmount,
                prefixText: r'$ ',
                suffixText: 'MXN',
                errorText: _errorText,
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) {
                // Recompute button state and validation on every edit.
                setState(() => _errorText = null);
              },
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('settle-all'),
                onPressed: _amount == widget.outstandingCents
                    ? null
                    : _settleEverything,
                child: Text(l10n.settleAll),
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (widget.canRequestPayment) ...[
            OutlinedButton.icon(
              key: Key('request-${widget.member.id}'),
              onPressed: widget.store.isOnline && !_submittingRequest
                  ? () async => _requestPayment()
                  : null,
              icon: _submittingRequest
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.qr_code_2_rounded),
              label: Text(l10n.requestPayment),
            ),
            if (!widget.store.isOnline) ...[
              const SizedBox(height: 6),
              Text(
                l10n.paymentRequestsRequireInternet,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 10),
          ],
          FilledButton.icon(
            key: Key('settle-${widget.member.id}'),
            onPressed: () async => _submitSettlement(),
            icon: const Icon(Icons.check_circle_outline_rounded),
            label: Text(
              widget.memberOwes
                  ? l10n.confirmPaymentReceived
                  : l10n.recordPayment,
            ),
          ),
        ],
      ),
    );
  }
}
