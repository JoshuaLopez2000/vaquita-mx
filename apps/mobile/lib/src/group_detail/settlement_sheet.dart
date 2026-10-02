part of '../group_detail_screen.dart';

void showSettlementSheet(
  BuildContext context,
  DemoStore store,
  ExpenseGroup group,
  Member member,
  int balance, {
  VoidCallback? onSettled,
}) {
  final l10n = AppLocalizations.of(context)!;
  if (member.userId == store.currentUserId ||
      member.id == store.currentUserId ||
      balance == 0) {
    return;
  }
  // Positive means this contact owes the signed-in user.
  final memberOwes = balance > 0;
  showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.qr_code_2_rounded,
              size: 54,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 14),
            Text(
              memberOwes
                  ? l10n.requestFrom(member.name)
                  : l10n.payContact(member.name),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              '${formatMoney(balance.abs())} MXN',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.demoPaymentDescription,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              key: Key('settle-${member.id}'),
              onPressed: () async {
                final cubit = context.read<AppCubit>();
                final settled = memberOwes
                    ? await cubit.requestPayment(
                        groupId: group.id,
                        debtorId: member.id,
                        amountCents: balance,
                      )
                    : await cubit.settleBalance(
                        groupId: group.id,
                        memberId: member.id,
                      );
                if (!sheetContext.mounted || !context.mounted) return;
                Navigator.pop(sheetContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      settled
                          ? (memberOwes
                              ? l10n.paymentRequestCreated
                              : l10n.paymentConfirmed)
                          : l10n.couldNotConfirmPayment,
                    ),
                  ),
                );
                if (settled) onSettled?.call();
              },
              icon: const Icon(Icons.check_circle_outline_rounded),
              label:
                  Text(memberOwes ? l10n.requestPayment : l10n.simulatePayment),
            ),
          ],
        ),
      ),
    ),
  );
}
