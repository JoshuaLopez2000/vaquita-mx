part of '../group_detail_screen.dart';

class _PendingPayment {
  const _PendingPayment(this.from, this.to, this.amountCents);

  final Member from;
  final Member to;
  final int amountCents;
}

List<_PendingPayment> _pendingPayments(
  ExpenseGroup group,
  List<PaymentRelation> relations,
) {
  final members = {for (final member in group.members) member.id: member};
  return [
    for (final relation in relations)
      if (members[relation.fromMemberId] != null &&
          members[relation.toMemberId] != null)
        _PendingPayment(
          members[relation.fromMemberId]!,
          members[relation.toMemberId]!,
          relation.amountCents,
        ),
  ];
}

void showPendingPaymentsSheet(
  BuildContext context,
  ExpenseGroup group,
  List<PaymentRelation> relations,
  String currentUserId,
) {
  final l10n = AppLocalizations.of(context)!;
  final payments = _pendingPayments(group, relations);
  String displayName(Member member) =>
      member.id == currentUserId || member.userId == currentUserId
          ? l10n.you
          : member.name;

  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * .8,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            Text(
              l10n.pendingPayments,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(l10n.pendingPaymentsDescription),
            const SizedBox(height: 18),
            if (payments.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  l10n.noPendingPayments,
                  textAlign: TextAlign.center,
                ),
              )
            else
              for (final payment in payments)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.arrow_forward_rounded),
                    title: Text(l10n.pendingPaymentFromTo(
                      displayName(payment.from),
                      displayName(payment.to),
                    )),
                    trailing: Text(
                      formatMoney(payment.amountCents),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
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
