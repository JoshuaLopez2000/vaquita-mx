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
      GroupInvitation invitation, bool accept) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _respondingInvitationId = invitation.group.id);
    final updated = await context
        .read<AppCubit>()
        .respondToInvitation(invitation.group.id, accept);
    if (!mounted) return;
    setState(() => _respondingInvitationId = null);
    if (updated) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(accept
            ? l10n.joinedGroup(invitation.group.name)
            : l10n.invitationDeclined(invitation.group.name)),
      ));
    } else if (widget.store.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(localizedError(
                AppLocalizations.of(context)!, widget.store.errorMessage!))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppCubit, AppState>(
      builder: (context, _) {
        final l10n = AppLocalizations.of(context)!;
        final rows = widget.store.contactStatus;

        return CustomScrollView(
          slivers: [
            SliverAppBar.large(
              title: Text(l10n.inbox),
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            ),
            if (rows.isEmpty && widget.store.invitations.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.inbox_outlined,
                        size: 48,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l10n.inboxEmptyTitle,
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.inboxEmptyDescription,
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ],
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
                          borderRadius: BorderRadius.circular(12),
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
                                Row(children: [
                                  CircleAvatar(child: Text(invite.group.emoji)),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(l10n.joinGroup(invite.group.name),
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium),
                                        Text(l10n.sharedGroupInvitation),
                                      ],
                                    ),
                                  ),
                                ]),
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton(
                                      key: Key(
                                          'decline-invitation-${invite.group.id}'),
                                      onPressed: responding
                                          ? null
                                          : () => _respondToInvitation(
                                              invite, false),
                                      child: Text(l10n.decline),
                                    ),
                                    const SizedBox(width: 8),
                                    FilledButton(
                                      key: Key(
                                          'accept-invitation-${invite.group.id}'),
                                      onPressed: responding
                                          ? null
                                          : () => _respondToInvitation(
                                              invite, true),
                                      child: responding
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2),
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
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 7,
                        ),
                        leading: CircleAvatar(child: Text(row.member.initials)),
                        title: Text(row.member.name),
                        subtitle: Text(row.amountCents > 0
                            ? l10n.youOweContact
                            : l10n.contactOwesYou),
                        trailing: Text(
                          formatMoney(row.amountCents.abs()),
                          style: const TextStyle(fontWeight: FontWeight.w700),
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
