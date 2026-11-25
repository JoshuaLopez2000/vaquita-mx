part of '../app.dart';

class StatusScreen extends StatefulWidget {
  const StatusScreen({required this.store, super.key});

  final DemoStore store;

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  String? _respondingInvitationId;
  String _orientationFilter = 'all';
  bool _loadingMoreRequests = false;

  @override
  void initState() {
    super.initState();
    context.read<AppCubit>().loadInbox();
  }

  Future<void> _selectOrientation(String orientation) async {
    if (_orientationFilter == orientation) return;
    setState(() => _orientationFilter = orientation);
    await context.read<AppCubit>().loadPaymentRequests(
          orientation: orientation == 'all' ? null : orientation,
        );
  }

  Future<void> _loadMoreRequests() async {
    if (_loadingMoreRequests) return;
    setState(() => _loadingMoreRequests = true);
    await context.read<AppCubit>().loadPaymentRequests(
          orientation: _orientationFilter == 'all' ? null : _orientationFilter,
          append: true,
        );
    if (mounted) {
      setState(() => _loadingMoreRequests = false);
    }
  }

  Future<void> _refresh() => context.read<AppCubit>().loadInbox(
        paymentRequestOrientation:
            _orientationFilter == 'all' ? null : _orientationFilter,
      );

  Future<void> _openPaymentRequest(PaymentRequestItem request) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PaymentRequestDetailScreen(
          store: widget.store,
          requestId: request.id,
          initialRequest: request,
        ),
      ),
    );
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
        final invitations = widget.store.invitations;
        final allRequests = widget.store.paymentRequests;
        final filteredRequests = _orientationFilter == 'all'
            ? allRequests
            : allRequests
                .where((item) => item.role == _orientationFilter)
                .toList();
        final showRequestsSection = widget.store.isAuthenticated &&
            (allRequests.isNotEmpty || _orientationFilter != 'all');
        final isEmpty =
            rows.isEmpty && invitations.isEmpty && !showRequestsSection;

        return RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
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
              if (isEmpty)
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
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      for (final invite in invitations) ...[
                        _buildInvitationCard(context, l10n, invite),
                        const SizedBox(height: 10),
                      ],
                      if (showRequestsSection) ...[
                        if (invitations.isNotEmpty) const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                l10n.paymentRequestsTitle,
                                style: theme.textTheme.titleLarge,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: colors.secondaryContainer,
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                '${filteredRequests.length}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colors.onSecondaryContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            ChoiceChip(
                              key: const Key('payment-requests-filter-all'),
                              label: Text(l10n.paymentRequestsFilterAll),
                              selected: _orientationFilter == 'all',
                              onSelected: (_) => _selectOrientation('all'),
                            ),
                            ChoiceChip(
                              key: const Key('payment-requests-filter-debtor'),
                              label: Text(l10n.paymentRequestsFilterToPay),
                              selected: _orientationFilter == 'debtor',
                              onSelected: (_) => _selectOrientation('debtor'),
                            ),
                            ChoiceChip(
                              key:
                                  const Key('payment-requests-filter-creditor'),
                              label: Text(l10n.paymentRequestsFilterSent),
                              selected: _orientationFilter == 'creditor',
                              onSelected: (_) => _selectOrientation('creditor'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (filteredRequests.isEmpty)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                l10n.noMatchingPaymentRequests,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          )
                        else ...[
                          for (final request in filteredRequests) ...[
                            PaymentRequestCard(
                              request: request,
                              onTap: () => _openPaymentRequest(request),
                            ),
                            const SizedBox(height: 10),
                          ],
                          if (widget.store.paymentRequestsNextCursor != null)
                            Align(
                              alignment: Alignment.center,
                              child: TextButton(
                                key: const Key('load-more-payment-requests'),
                                onPressed: _loadingMoreRequests
                                    ? null
                                    : _loadMoreRequests,
                                child: Text(l10n.loadMore),
                              ),
                            ),
                        ],
                        if (rows.isNotEmpty) const SizedBox(height: 12),
                      ],
                      for (final row in rows) ...[
                        Builder(
                          builder: (context) {
                            final youOwe = row.amountCents > 0;
                            final tone =
                                youOwe ? vColors.negative : vColors.positive;
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
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
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
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
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
                        const SizedBox(height: 10),
                      ],
                    ]),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInvitationCard(
    BuildContext context,
    AppLocalizations l10n,
    GroupInvitation invite,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final responding = _respondingInvitationId == invite.group.id;
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.joinGroup(invite.group.name),
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n.sharedGroupInvitation,
                          style: theme.textTheme.bodySmall?.copyWith(
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
                    key: Key('decline-invitation-${invite.group.id}'),
                    onPressed: responding
                        ? null
                        : () => _respondToInvitation(invite, false),
                    child: Text(l10n.decline),
                  ),
                  FilledButton(
                    key: Key('accept-invitation-${invite.group.id}'),
                    onPressed: responding
                        ? null
                        : () => _respondToInvitation(invite, true),
                    child: responding
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
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
}
