part of '../app.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    required this.store,
    this.onProfileTap,
    super.key,
  });

  final DemoStore store;
  final VoidCallback? onProfileTap;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppCubit, AppState>(
      builder: (context, state) {
        final l10n = AppLocalizations.of(context)!;
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final vColors = VaquitaColors.of(context);
        var owedToYou = 0;
        var youOwe = 0;
        for (final group in store.groups) {
          final balance = store.currentUserBalance(group);
          if (balance > 0) owedToYou += balance;
          if (balance < 0) youOwe += balance.abs();
        }
        final user = state.user;
        final avatarText = user != null
            ? user.name
                .trim()
                .split(RegExp(r'\s+'))
                .where((part) => part.isNotEmpty)
                .take(2)
                .map((part) => part[0].toUpperCase())
                .join()
            : l10n.you.toUpperCase();

        return CustomScrollView(
          key: const Key('dashboard-scroll'),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    const VaquitaLogoMark(size: 42),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.appTitle.toUpperCase(),
                            style: theme.textTheme.labelLarge?.copyWith(
                              letterSpacing: 1.6,
                              color: colors.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            user != null ? user.name : l10n.goodAfternoon,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.headlineSmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Semantics(
                      button: onProfileTap != null,
                      label: l10n.profile,
                      child: InkWell(
                        onTap: onProfileTap,
                        customBorder: const CircleBorder(),
                        child: Container(
                          width: 46,
                          height: 46,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colors.primaryContainer,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: colors.primary.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Text(
                            avatarText.isEmpty ? '?' : avatarText,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: colors.onPrimaryContainer,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              sliver: SliverToBoxAdapter(
                child: _BalanceOverview(
                  owedToYou: owedToYou,
                  youOwe: youOwe,
                ),
              ),
            ),
            if (store.isLoading)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: const LinearProgressIndicator(minHeight: 4),
                  ),
                ),
              ),
            if (store.pendingMutations.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: Card(
                    key: const Key('pending-sync-banner'),
                    color: vColors.warningContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(
                        color: vColors.warning.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                      child: Row(
                        children: [
                          Icon(
                            Icons.cloud_upload_outlined,
                            color: vColors.onWarningContainer,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.pendingSyncBannerTitle(
                                    store.pendingMutations.length,
                                  ),
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: vColors.onWarningContainer,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  l10n.pendingSyncBannerDescription,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: vColors.onWarningContainer
                                        .withValues(alpha: 0.88),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            key: const Key('sync-pending-mutations-button'),
                            onPressed: store.isLoading
                                ? null
                                : () => context
                                    .read<AppCubit>()
                                    .syncPendingMutations(),
                            child: Text(l10n.syncNow),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (store.failedMutations.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: Card(
                    key: const Key('failed-sync-banner'),
                    color: colors.errorContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(
                        color: colors.error.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.sync_problem_rounded,
                                color: colors.onErrorContainer,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  l10n.failedSyncBannerTitle(
                                    store.failedMutations.length,
                                  ),
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: colors.onErrorContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              TextButton(
                                key: const Key('discard-failed-sync-button'),
                                onPressed: store.isLoading
                                    ? null
                                    : () async {
                                        final cubit = context.read<AppCubit>();
                                        for (final failed
                                            in List.of(store.failedMutations)) {
                                          await cubit.discardFailedMutation(
                                            failed.id,
                                          );
                                        }
                                      },
                                child: Text(l10n.discard),
                              ),
                              FilledButton.tonal(
                                key: const Key('retry-failed-sync-button'),
                                onPressed: store.isLoading
                                    ? null
                                    : () => context
                                        .read<AppCubit>()
                                        .syncPendingMutations(
                                          retryFailed: true,
                                        ),
                                child: Text(l10n.retry),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (store.errorMessage != null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: Card(
                    color: colors.errorContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(
                        color: colors.error.withValues(alpha: 0.35),
                      ),
                    ),
                    child: ListTile(
                      leading: Icon(
                        Icons.cloud_off_rounded,
                        color: colors.onErrorContainer,
                      ),
                      title: Text(
                        localizedError(l10n, store.errorMessage!),
                        style: TextStyle(color: colors.onErrorContainer),
                      ),
                      trailing: TextButton(
                        onPressed: store.load,
                        child: Text(l10n.retry),
                      ),
                    ),
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 26, 20, 12),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.yourGroups,
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
                        l10n.activeGroups(store.groups.length),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSecondaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (store.groups.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                sliver: SliverToBoxAdapter(
                  child: VaquitaEmptyState(
                    inCard: true,
                    icon: Icons.groups_outlined,
                    title: l10n.noGroups,
                    description: l10n.noGroupsDescription,
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                sliver: SliverList.separated(
                  itemCount: store.groups.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final group = store.groups[index];
                    return _GroupCard(
                      group: group,
                      serverBacked: store.isServerBacked(group),
                      pendingCount:
                          store.pendingMutationCountForGroup(group.id),
                      balance: store.currentUserBalance(group),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => GroupDetailScreen(
                            store: store,
                            groupId: group.id,
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
