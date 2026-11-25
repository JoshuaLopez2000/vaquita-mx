part of '../app.dart';

class StatusScreen extends StatefulWidget {
  const StatusScreen({required this.store, super.key});

  final DemoStore store;

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  String? _respondingInvitationId;

  @override
  void initState() {
    super.initState();
    context.read<AppCubit>().loadInbox();
  }

  Future<void> _respondToInvitation(
    GroupInvitation invitation,
    bool accept,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _respondingInvitationId = invitation.group.id);
    final updated = await context
        .read<AppCubit>()
        .respondToInvitation(invitation.group.id, accept);
    if (!mounted) return;
    setState(() => _respondingInvitationId = null);
    if (updated) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept
                ? l10n.joinedGroup(invitation.group.name)
                : l10n.invitationDeclined(invitation.group.name),
          ),
        ),
      );
    } else if (widget.store.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            localizedError(
              AppLocalizations.of(context)!,
              widget.store.errorMessage!,
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppCubit, AppState>(
      builder: (context, _) {
        final l10n = AppLocalizations.of(context)!;
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final vColors = VaquitaColors.of(context);
        final rows = widget.store.contactStatus;

        return CustomScrollView(
          slivers: [
            SliverAppBar.large(
              title: Text(l10n.inbox),
              backgroundColor: theme.scaffoldBackgroundColor,
            ),
            if (widget.store.isLoading)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                sliver: SliverToBoxAdapter(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: const LinearProgressIndicator(minHeight: 4),
                  ),
                ),
              ),
            if (rows.isEmpty && widget.store.invitations.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: VaquitaEmptyState(
                    icon: Icons.inbox_outlined,
                    title: l10n.inboxEmptyTitle,
                    description: l10n.inboxEmptyDescription,
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                sliver: SliverList.separated(
                  itemCount: rows.length + widget.store.invitations.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    if (index < widget.store.invitations.length) {
                      final invite = widget.store.invitations[index];
                      final responding =
                          _respondingInvitationId == invite.group.id;
                      return Card(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => InvitationDetailsScreen(
                                invitation: invite,
                              ),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: colors.primaryContainer,
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Text(
                                        invite.group.emoji,
                                        style: const TextStyle(fontSize: 24),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            l10n.joinGroup(invite.group.name),
                                            style: theme.textTheme.titleMedium,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            l10n.sharedGroupInvitation,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              color: colors.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Wrap(
                                  alignment: WrapAlignment.end,
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    TextButton(
                                      key: Key(
                                        'decline-invitation-${invite.group.id}',
                                      ),
                                      onPressed: responding
                                          ? null
                                          : () => _respondToInvitation(
                                                invite,
                                                false,
                                              ),
                                      child: Text(l10n.decline),
                                    ),
                                    FilledButton(
                                      key: Key(
                                        'accept-invitation-${invite.group.id}',
                                      ),
                                      onPressed: responding
                                          ? null
                                          : () => _respondToInvitation(
                                                invite,
                                                true,
                                              ),
                                      child: responding
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : Text(l10n.acceptInvitation),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }
                    final row = rows[index - widget.store.invitations.length];
                    // Status API convention: positive = you owe contact.
                    final youOwe = row.amountCents > 0;
                    final tone = youOwe ? vColors.negative : vColors.positive;
                    final directionIcon = youOwe
                        ? Icons.north_east_rounded
                        : Icons.south_west_rounded;
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: colors.primaryContainer,
                          foregroundColor: colors.onPrimaryContainer,
                          child: Text(
                            row.member.initials,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        title: Text(
                          row.member.name,
                          style: theme.textTheme.titleMedium,
                        ),
                        subtitle: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(directionIcon, size: 14, color: tone),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                youOwe
                                    ? l10n.youOweContact
                                    : l10n.contactOwesYou,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              formatMoney(row.amountCents.abs()),
                              style: VaquitaTheme.money(
                                theme.textTheme.titleMedium,
                                color: tone,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: colors.onSurfaceVariant,
                            ),
                          ],
                        ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ContactBalanceDetailsScreen(
                              store: widget.store,
                              status: row,
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
