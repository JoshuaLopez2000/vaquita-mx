part of '../app.dart';

class MovementsScreen extends StatelessWidget {
  const MovementsScreen({required this.store, super.key});

  final DemoStore store;

  List<_Movement> _items(AppLocalizations l10n) {
    final items = <_Movement>[];
    for (final group in store.groups) {
      final members = {for (final member in group.members) member.id: member};
      String displayName(String memberId) {
        final member = members[memberId];
        if (member == null) return l10n.genericMember;
        if (member.id == store.currentUserId ||
            member.userId == store.currentUserId) {
          return l10n.you;
        }
        return member.name;
      }

      for (final expense in group.expenses) {
        items.add(_Movement(
          group: group,
          title: expense.description,
          detail: l10n.memberPaid((expense.payers.isEmpty
                  ? [expense.payerId]
                  : expense.payers.map((payer) => payer.memberId))
              .map(displayName)
              .join(', ')),
          amountCents: expense.amountCents,
          occurredAt: expense.createdAt,
          isSettlement: false,
        ));
      }
      for (final settlement in group.settlements) {
        final from = displayName(settlement.fromMemberId);
        final to = displayName(settlement.toMemberId);
        items.add(_Movement(
          group: group,
          title: l10n.memberPaidMember(from, to),
          detail: l10n.settlement,
          amountCents: settlement.amountCents,
          occurredAt: settlement.createdAt,
          isSettlement: true,
        ));
      }
    }
    items.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return items;
  }

  String _relativeDate(DateTime value, AppLocalizations l10n) {
    final date = value.toLocal();
    final today = DateUtils.dateOnly(DateTime.now());
    final daysAgo = today.difference(DateUtils.dateOnly(date)).inDays;
    if (daysAgo == 0) return l10n.today;
    if (daysAgo == 1) return l10n.yesterday;
    if (daysAgo < 7) return l10n.daysAgo(daysAgo);
    return DateFormat.yMd(l10n.localeName).format(date);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppCubit, AppState>(
      builder: (context, _) {
        final l10n = AppLocalizations.of(context)!;
        final items = _items(l10n);
        return CustomScrollView(
          slivers: [
            SliverAppBar.large(
              title: Text(l10n.movements),
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            ),
            if (items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.receipt_long_outlined,
                            size: 48,
                            color: Theme.of(context).colorScheme.secondary),
                        const SizedBox(height: 16),
                        Text(l10n.noMovements,
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 8),
                        Text(
                          l10n.movementsEmptyDescription,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                sliver: SliverList.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 7),
                        leading: CircleAvatar(
                          child: Icon(item.isSettlement
                              ? Icons.handshake_outlined
                              : Icons.receipt_long_outlined),
                        ),
                        title: Text(item.title),
                        subtitle: Text(l10n.movementMetadata(
                          item.group.emoji,
                          item.group.name,
                          item.detail,
                          _relativeDate(item.occurredAt, l10n),
                        )),
                        trailing: Text(formatMoney(item.amountCents),
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => GroupDetailScreen(
                              store: store,
                              groupId: item.group.id,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Movement {
  const _Movement({
    required this.group,
    required this.title,
    required this.detail,
    required this.amountCents,
    required this.occurredAt,
    required this.isSettlement,
  });

  final ExpenseGroup group;
  final String title;
  final String detail;
  final int amountCents;
  final DateTime occurredAt;
  final bool isSettlement;
}
