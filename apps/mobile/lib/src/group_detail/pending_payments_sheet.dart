part of '../group_detail_screen.dart';

class _PendingPayment {
  const _PendingPayment(this.from, this.to, this.amountCents);

  final Member from;
  final Member to;
  final int amountCents;
}

List<_PendingPayment> _pendingPayments(
  ExpenseGroup group,
  Map<String, int> balances,
) {
  final debtors = [
    for (final member in group.members.where((member) => member.active))
      if ((balances[member.id] ?? 0) < 0)
        MapEntry(member, -(balances[member.id] ?? 0)),
  ];
  final creditors = [
    for (final member in group.members.where((member) => member.active))
      if ((balances[member.id] ?? 0) > 0)
        MapEntry(member, balances[member.id] ?? 0),
  ];

  final payments = <_PendingPayment>[];
  var debtorIndex = 0;
  var creditorIndex = 0;
  var debtorRemaining = debtors.isEmpty ? 0 : debtors.first.value;
  var creditorRemaining = creditors.isEmpty ? 0 : creditors.first.value;

  while (debtorIndex < debtors.length && creditorIndex < creditors.length) {
    final amount = debtorRemaining < creditorRemaining
        ? debtorRemaining
        : creditorRemaining;
    if (amount > 0) {
      payments.add(_PendingPayment(
        debtors[debtorIndex].key,
        creditors[creditorIndex].key,
        amount,
      ));
    }
    debtorRemaining -= amount;
    creditorRemaining -= amount;
    if (debtorRemaining == 0) {
      debtorIndex++;
      if (debtorIndex < debtors.length) {
        debtorRemaining = debtors[debtorIndex].value;
      }
    }
    if (creditorRemaining == 0) {
      creditorIndex++;
      if (creditorIndex < creditors.length) {
        creditorRemaining = creditors[creditorIndex].value;
      }
    }
  }
  return payments;
}

void showPendingPaymentsSheet(
  BuildContext context,
  ExpenseGroup group,
  Map<String, int> balances,
  String currentUserId,
) {
  final l10n = AppLocalizations.of(context)!;
  final payments = _pendingPayments(group, balances);
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
