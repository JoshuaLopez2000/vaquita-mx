part of '../group_detail_screen.dart';

class _MemberBalanceTile extends StatelessWidget {
  const _MemberBalanceTile({
    required this.member,
    required this.balance,
    required this.isCurrentUser,
    required this.onSettle,
  });

  final Member member;
  final int balance;
  final bool isCurrentUser;
  final VoidCallback onSettle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final subtitle = !member.accepted
        ? l10n.invitationPending
        : balance > 0
            ? l10n.getsBack(formatMoney(balance))
            : balance < 0
                ? l10n.owesAmount(formatMoney(balance.abs()))
                : l10n.groupBalanceSettled;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(child: Text(member.initials)),
      title: Text(isCurrentUser ? l10n.you : member.name),
      subtitle: Text(subtitle),
      trailing: !member.accepted
          ? Icon(Icons.hourglass_empty_rounded, color: colors.secondary)
          : isCurrentUser || balance == 0
              ? Icon(Icons.check_circle_rounded, color: colors.primary)
              : TextButton(
                  onPressed: onSettle,
                  child: Text(balance < 0 ? l10n.request : l10n.pay),
                ),
    );
  }
}
