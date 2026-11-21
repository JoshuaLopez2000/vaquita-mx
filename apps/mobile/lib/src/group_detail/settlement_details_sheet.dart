part of '../group_detail_screen.dart';

Future<String?> showReversalReasonDialog(
  BuildContext context, {
  required String title,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _ReversalReasonDialog(title: title),
  );
}

class _ReversalReasonDialog extends StatefulWidget {
  const _ReversalReasonDialog({required this.title});

  final String title;

  @override
  State<_ReversalReasonDialog> createState() => _ReversalReasonDialogState();
}

class _ReversalReasonDialogState extends State<_ReversalReasonDialog> {
  final _controller = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const Key('reversal-reason-input'),
        controller: _controller,
        autofocus: true,
        maxLines: 3,
        decoration: InputDecoration(
          labelText: l10n.reversalReasonLabel,
          hintText: l10n.reversalReasonHint,
          errorText: _errorText,
        ),
        onChanged: (_) {
          if (_errorText != null) setState(() => _errorText = null);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('confirm-reversal-button'),
          onPressed: () {
            final trimmed = _controller.text.trim();
            if (trimmed.isEmpty || trimmed.runes.length > 500) {
              setState(() => _errorText = l10n.reversalReasonRequired);
              return;
            }
            Navigator.pop(context, trimmed);
          },
          child: Text(l10n.confirmReversal),
        ),
      ],
    );
  }
}

class _SettlementCard extends StatelessWidget {
  const _SettlementCard({
    required this.store,
    required this.group,
    required this.settlement,
    required this.onReverseAndReplace,
  });

  final DemoStore store;
  final ExpenseGroup group;
  final Settlement settlement;
  final Future<void> Function(Settlement settlement, String reason)
      onReverseAndReplace;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final members = {for (final member in group.members) member.id: member};
    final fromName =
        members[settlement.fromMemberId]?.name ?? l10n.genericMember;
    final toName = members[settlement.toMemberId]?.name ?? l10n.genericMember;
    final reversal = group.reversalForSettlement(settlement.id);
    final isReversed = reversal != null;
    final colorScheme = Theme.of(context).colorScheme;
    final dateLabel =
        DateFormat.yMd(l10n.localeName).format(settlement.createdAt.toLocal());

    return Card(
      key: Key('settlement-card-${settlement.id}'),
      child: ListTile(
        onTap: () => showSettlementDetailsSheet(
          context,
          store,
          group,
          settlement,
          onReverseAndReplace: onReverseAndReplace,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isReversed
                ? colorScheme.errorContainer
                : colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            isReversed ? Icons.undo_rounded : Icons.handshake_outlined,
            color: isReversed
                ? colorScheme.onErrorContainer
                : colorScheme.onPrimaryContainer,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                l10n.memberPaidMember(fromName, toName),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  decoration: isReversed ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            if (isReversed)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Chip(
                  label: Text(l10n.reversed),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: colorScheme.errorContainer,
                  labelStyle: TextStyle(
                    color: colorScheme.onErrorContainer,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            else if (settlement.replacesSettlementId != null)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Chip(
                  label: Text(l10n.replacement),
                  visualDensity: VisualDensity.compact,
                  labelStyle: const TextStyle(fontSize: 11),
                ),
              ),
          ],
        ),
        subtitle: Text(
          isReversed
              ? '${l10n.reversed} · ${reversal.reason}'
              : '${l10n.settlement} · $dateLabel',
        ),
        trailing: Text(
          formatMoney(settlement.amountCents),
          style: TextStyle(
            fontWeight: FontWeight.w800,
            decoration: isReversed ? TextDecoration.lineThrough : null,
          ),
        ),
      ),
    );
  }
}

void showSettlementDetailsSheet(
  BuildContext context,
  DemoStore store,
  ExpenseGroup group,
  Settlement settlement, {
  Future<void> Function(Settlement settlement, String reason)?
      onReverseAndReplace,
}) {
  final l10n = AppLocalizations.of(context)!;
  final members = {for (final member in group.members) member.id: member};
  final fromName = members[settlement.fromMemberId]?.name ?? l10n.genericMember;
  final toName = members[settlement.toMemberId]?.name ?? l10n.genericMember;
  final reversal = group.reversalForSettlement(settlement.id);
  final replacement = group.replacementForSettlement(settlement.id);
  final canReverse = store.canReverseSettlement(group, settlement);
  final pendingServerSync = store.canUseServerFeatures(group) &&
      settlement.id.startsWith('local_settlement_');
  final timestampFormat = DateFormat.yMd(l10n.localeName).add_Hm();

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * .85,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            Text(
              l10n.settlementDetails,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.memberPaidMember(fromName, toName),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(timestampFormat.format(settlement.createdAt.toLocal())),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(l10n.total),
                    Text(
                      formatMoney(settlement.amountCents),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            decoration: reversal != null
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            if (settlement.replacesSettlementId != null) ...[
              const SizedBox(height: 12),
              Text(l10n.replacesOriginalRecord),
            ],
            if (reversal != null) ...[
              const SizedBox(height: 16),
              _ReversalAuditCard(
                actorName:
                    members[reversal.actorMemberId]?.name ?? l10n.genericMember,
                reason: reversal.reason,
                createdAt: reversal.createdAt,
                hasReplacement: replacement != null,
              ),
            ],
            if (pendingServerSync && reversal == null) ...[
              const SizedBox(height: 12),
              Text(l10n.syncBeforeReversal),
            ],
            if (canReverse) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                key: Key('reverse-settlement-${settlement.id}'),
                onPressed: () async {
                  final reason = await showReversalReasonDialog(
                    sheetContext,
                    title: l10n.reverseSettlement,
                  );
                  if (reason == null || !sheetContext.mounted) return;
                  final reversed =
                      await sheetContext.read<AppCubit>().reverseSettlement(
                            groupId: group.id,
                            settlementId: settlement.id,
                            reason: reason,
                          );
                  if (!sheetContext.mounted) return;
                  Navigator.pop(sheetContext);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        reversed
                            ? (store.lastMutationQueuedOffline
                                ? l10n.savedOfflineWillSync
                                : l10n.settlementReversed)
                            : l10n.couldNotReverseRecord,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.undo_rounded),
                label: Text(l10n.reverseSettlement),
              ),
              if (onReverseAndReplace != null) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: Key('reverse-replace-settlement-${settlement.id}'),
                  onPressed: () async {
                    final reason = await showReversalReasonDialog(
                      sheetContext,
                      title: l10n.reverseAndReplaceSettlement,
                    );
                    if (reason == null || !sheetContext.mounted) return;
                    Navigator.pop(sheetContext);
                    await onReverseAndReplace(settlement, reason);
                  },
                  icon: const Icon(Icons.published_with_changes_rounded),
                  label: Text(l10n.reverseAndReplaceSettlement),
                ),
              ],
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(sheetContext),
              child: Text(l10n.close),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ReversalAuditCard extends StatelessWidget {
  const _ReversalAuditCard({
    required this.actorName,
    required this.reason,
    required this.createdAt,
    required this.hasReplacement,
  });

  final String actorName;
  final String reason;
  final DateTime createdAt;
  final bool hasReplacement;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final timestamp =
        DateFormat.yMd(l10n.localeName).add_Hm().format(createdAt.toLocal());
    return Card(
      color: colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.undo_rounded,
                    size: 18, color: colorScheme.onErrorContainer),
                const SizedBox(width: 8),
                Text(
                  l10n.reversalAuditTitle,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colorScheme.onErrorContainer,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              l10n.reversedByName(actorName),
              style: TextStyle(color: colorScheme.onErrorContainer),
            ),
            Text(
              l10n.reversalReasonValue(reason),
              style: TextStyle(color: colorScheme.onErrorContainer),
            ),
            Text(
              timestamp,
              style: TextStyle(
                color: colorScheme.onErrorContainer,
                fontSize: 12,
              ),
            ),
            if (hasReplacement) ...[
              const SizedBox(height: 6),
              Text(
                l10n.replacedByRecord,
                style: TextStyle(
                  color: colorScheme.onErrorContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
