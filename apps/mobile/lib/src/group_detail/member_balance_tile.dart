part of '../group_detail_screen.dart';

class _MemberBalanceTile extends StatelessWidget {
  const _MemberBalanceTile({
    required this.member,
    required this.balance,
    required this.relationshipBalance,
    required this.isCurrentUser,
    required this.sharedServerGroup,
    required this.onSettle,
  });

  final Member member;
  final int balance;
  final int relationshipBalance;
  final bool isCurrentUser;
  final bool sharedServerGroup;
  final VoidCallback onSettle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final vColors = VaquitaColors.of(context);
    final groupSummary = balance > 0
        ? l10n.getsBack(formatMoney(balance))
        : balance < 0
            ? l10n.owesAmount(formatMoney(balance.abs()))
            : l10n.groupBalanceSettled;
    final relationshipSummary = relationshipBalance > 0
        ? l10n.getsBack(formatMoney(relationshipBalance))
        : relationshipBalance < 0
            ? l10n.owesAmount(formatMoney(relationshipBalance.abs()))
            : l10n.groupBalanceSettled;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: CircleAvatar(
        backgroundColor:
            isCurrentUser ? colors.primaryContainer : colors.secondaryContainer,
        foregroundColor: isCurrentUser
            ? colors.onPrimaryContainer
            : colors.onSecondaryContainer,
        child: Text(
          member.initials,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      title: Text(
        isCurrentUser ? l10n.you : member.name,
        style: theme.textTheme.titleSmall,
      ),
      subtitle: !member.accepted
          ? Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                l10n.invitationPending,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: vColors.warning,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.groupBalanceSummary(groupSummary),
                    style: VaquitaTheme.money(
                      theme.textTheme.bodySmall,
                      color: colors.onSurfaceVariant,
                      weight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    l10n.withYouBalanceSummary(relationshipSummary),
                    style: VaquitaTheme.money(
                      theme.textTheme.bodySmall,
                      color: relationshipBalance > 0
                          ? vColors.positive
                          : relationshipBalance < 0
                              ? vColors.negative
                              : colors.onSurfaceVariant,
                      weight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
      trailing: !member.accepted
          ? Tooltip(
              message: l10n.invitationPending,
              child: Icon(
                Icons.hourglass_empty_rounded,
                color: vColors.warning,
              ),
            )
          : isCurrentUser || relationshipBalance == 0
              ? Semantics(
                  label: l10n.settledUp,
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: vColors.positive,
                  ),
                )
              : sharedServerGroup && relationshipBalance < 0
                  ? Tooltip(
                      message: l10n.waitingForCreditorConfirmation,
                      child: Icon(
                        Icons.hourglass_top_rounded,
                        color: colors.secondary,
                      ),
                    )
                  : ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 148),
                      child: FilledButton.tonal(
                        key: Key('open-settlement-${member.id}'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(48, 38),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        onPressed: onSettle,
                        child: Text(
                          sharedServerGroup
                              ? l10n.request
                              : relationshipBalance < 0
                                  ? l10n.pay
                                  : l10n.confirmPaymentReceived,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
    );
  }
}
