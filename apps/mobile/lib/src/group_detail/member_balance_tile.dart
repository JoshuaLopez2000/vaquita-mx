part of '../group_detail_screen.dart';

class _MemberBalanceTile extends StatelessWidget {
  const _MemberBalanceTile({
    required this.member,
    required this.balance,
    required this.relationshipBalance,
    required this.isCurrentUser,
    required this.onSettle,
  });

  final Member member;
  final int balance;
  final int relationshipBalance;
  final bool isCurrentUser;
  final VoidCallback onSettle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(child: Text(member.initials)),
      title: Text(isCurrentUser ? l10n.you : member.name),
      subtitle: !member.accepted
          ? Text(l10n.invitationPending)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.groupBalanceSummary(groupSummary)),
                Text(l10n.withYouBalanceSummary(relationshipSummary)),
              ],
            ),
      trailing: !member.accepted
          ? Icon(Icons.hourglass_empty_rounded, color: colors.secondary)
          : isCurrentUser || relationshipBalance == 0
              ? Icon(Icons.check_circle_rounded, color: colors.primary)
              : TextButton(
                  onPressed: onSettle,
                  child:
                      Text(relationshipBalance < 0 ? l10n.pay : l10n.request),
                ),
    );
  }
}
