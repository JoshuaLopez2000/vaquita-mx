part of '../app.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({required this.store, super.key});

  final DemoStore store;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppCubit, AppState>(
      builder: (context, _) {
        final l10n = AppLocalizations.of(context)!;
        var owedToYou = 0;
        var youOwe = 0;
        for (final group in store.groups) {
          final balance = store.currentUserBalance(group);
          if (balance > 0) owedToYou += balance;
          if (balance < 0) youOwe += balance.abs();
        }

        return CustomScrollView(
          key: const Key('dashboard-scroll'),
          slivers: [
            if (store.groups.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                sliver: SliverToBoxAdapter(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(children: [
                        const Icon(Icons.groups_outlined, size: 42),
                        const SizedBox(height: 10),
                        Text(l10n.noGroups,
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(l10n.noGroupsDescription,
                            textAlign: TextAlign.center),
                      ]),
                    ),
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.appTitle.toUpperCase(),
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  letterSpacing: 1.5,
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            l10n.goodAfternoon,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ],
                      ),
                    ),
                    CircleAvatar(
                      radius: 23,
                      child: Text(l10n.you.toUpperCase()),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              sliver: SliverToBoxAdapter(
                child: _BalanceOverview(
                  owedToYou: owedToYou,
                  youOwe: youOwe,
                ),
              ),
            ),
            if (store.isLoading)
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
                sliver: SliverToBoxAdapter(child: LinearProgressIndicator()),
              ),
            if (store.pendingMutations.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: Card(
                    key: const Key('pending-sync-banner'),
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    child: ListTile(
                      leading: const Icon(Icons.cloud_upload_outlined),
                      title: Text(
                        l10n.pendingSyncBannerTitle(
                          store.pendingMutations.length,
                        ),
                      ),
                      subtitle: Text(l10n.pendingSyncBannerDescription),
                      trailing: TextButton(
                        key: const Key('sync-pending-mutations-button'),
                        onPressed: store.isLoading
                            ? null
                            : () => context
                                .read<AppCubit>()
                                .syncPendingMutations(),
                        child: Text(l10n.syncNow),
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
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.sync_problem_rounded),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  l10n.failedSyncBannerTitle(
                                    store.failedMutations.length,
                                  ),
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                key: const Key('discard-failed-sync-button'),
                                onPressed: store.isLoading
                                    ? null
                                    : () async {
                                        final cubit = context.read<AppCubit>();
                                        for (final failed in List.of(
                                            store.failedMutations)) {
                                          await cubit
                                              .discardFailedMutation(failed.id);
                                        }
                                      },
                                child: Text(l10n.discard),
                              ),
                              const SizedBox(width: 8),
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
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: ListTile(
                      leading: const Icon(Icons.cloud_off_rounded),
                      title: Text(localizedError(l10n, store.errorMessage!)),
                      trailing: TextButton(
                        onPressed: store.load,
                        child: Text(l10n.retry),
                      ),
                    ),
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.yourGroups,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    Text(l10n.activeGroups(store.groups.length)),
                  ],
                ),
              ),
            ),
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
                    pendingCount: store.pendingMutationCountForGroup(group.id),
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
