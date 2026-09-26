import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:vaquita_mx/src/api_client.dart';
import 'package:vaquita_mx/src/auth_screen.dart';
import 'package:vaquita_mx/src/contacts_screen.dart';
import 'package:vaquita_mx/src/features/app/application/app_cubit.dart';
import 'package:vaquita_mx/src/features/app/application/app_state.dart';
import 'package:vaquita_mx/src/group_detail_screen.dart';
import 'package:vaquita_mx/l10n/app_localizations.dart';
import 'package:vaquita_mx/l10n/localized_error.dart';
import 'package:vaquita_mx/src/models.dart';
import 'package:vaquita_mx/src/sheets.dart';
import 'package:vaquita_mx/src/store.dart';

class VaquitaApp extends StatefulWidget {
  const VaquitaApp({this.store, super.key});

  final DemoStore? store;

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    // Android emulators reach the host through 10.0.2.2; browsers run on
    // the host itself, where that special emulator address is unreachable.
    defaultValue: kIsWeb ? 'http://localhost:8080' : 'http://10.0.2.2:8080',
  );

  @override
  State<VaquitaApp> createState() => _VaquitaAppState();
}

class _VaquitaAppState extends State<VaquitaApp> {
  late final DemoStore store;
  late final AppCubit appCubit;
  late final bool _ownsStore;
  var _authenticated = false;
  var _restoringSession = true;
  var _locale = const Locale('es');

  void _setLocale(Locale locale) => setState(() => _locale = locale);

  @override
  void initState() {
    super.initState();
    _ownsStore = widget.store == null;
    store = widget.store ??
        DemoStore.remote(ApiClient(baseUrl: VaquitaApp.apiBaseUrl));
    appCubit = AppCubit(store);
    _authenticated = !_ownsStore;
    if (_ownsStore) {
      _restoreSession();
    } else {
      _restoringSession = false;
    }
  }

  Future<void> _restoreSession() async {
    final restored = await store.apiClient!.restoreSession();
    if (!mounted) return;
    setState(() {
      _authenticated = restored;
      _restoringSession = false;
    });
    if (restored) appCubit.loadGroups();
  }

  @override
  void dispose() {
    appCubit.close();
    if (_ownsStore) {
      store.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF006B5E);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    );

    return BlocProvider.value(
      value: appCubit,
      child: MaterialApp(
        onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: _locale,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: colorScheme,
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFFF5F7F4),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: colorScheme.surfaceContainerLowest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
          cardTheme: CardThemeData(
            margin: EdgeInsets.zero,
            elevation: 0,
            color: colorScheme.surfaceContainerLowest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        home: _restoringSession
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : _authenticated
                ? AppShell(store: store, onLocaleChanged: _setLocale)
                : AuthScreen(
                    api: store.apiClient!,
                    onAuthenticated: () {
                      setState(() => _authenticated = true);
                      appCubit.loadGroups();
                    },
                  ),
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({
    required this.store,
    required this.onLocaleChanged,
    super.key,
  });

  final DemoStore store;
  final ValueChanged<Locale> onLocaleChanged;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    context.read<AppCubit>().loadContacts();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _selectTab(int target, {bool animate = true}) {
    if (target == _selectedIndex) return;
    setState(() => _selectedIndex = target);
    if (animate) {
      _pageController.animateToPage(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
    if (target == 2) context.read<AppCubit>().loadGroups();
  }

  Future<void> _createGroup() async {
    final l10n = AppLocalizations.of(context)!;
    final input = await showCreateGroupSheet(
      context,
      contacts: context.read<AppCubit>().state.contacts,
    );
    if (input == null || !mounted) return;
    final created = await context.read<AppCubit>().createGroup(
          name: input.name,
          memberNames: input.memberNames,
          members: input.members,
          emoji: input.emoji,
          visibility: input.visibility,
          salarySplitEnabled: input.salarySplitEnabled,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          created ? l10n.groupCreated(input.name) : l10n.couldNotCreateGroup,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocListener<AppCubit, AppState>(
      listenWhen: (_, state) => state.navigationTarget != null,
      listener: (_, state) => _selectTab(state.navigationTarget!),
      child: Scaffold(
        body: SafeArea(
          child: PageView(
            controller: _pageController,
            onPageChanged: (index) => _selectTab(index, animate: false),
            children: [
              DashboardScreen(store: widget.store),
              StatusScreen(store: widget.store),
              MovementsScreen(store: widget.store),
              const ContactsScreen(),
              ProfileScreen(
                store: widget.store,
                onLocaleChanged: widget.onLocaleChanged,
              ),
            ],
          ),
        ),
        floatingActionButton: _selectedIndex == 0
            ? FloatingActionButton.extended(
                key: const Key('create-group-button'),
                onPressed: _createGroup,
                icon: const Icon(Icons.add_rounded),
                label: Text(l10n.newGroup),
              )
            : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) {
            _selectTab(index);
            if (index == 1) {
              context.read<AppCubit>().loadInbox();
            }
            if (index == 2) context.read<AppCubit>().loadGroups();
          },
          destinations: [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: l10n.home,
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long_rounded),
              label: l10n.inbox,
            ),
            NavigationDestination(
              icon: Icon(Icons.swap_horiz_outlined),
              selectedIcon: Icon(Icons.swap_horiz_rounded),
              label: l10n.movements,
            ),
            NavigationDestination(
              icon: Icon(Icons.contacts_outlined),
              selectedIcon: Icon(Icons.contacts_rounded),
              label: l10n.contacts,
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: l10n.profile,
            ),
          ],
        ),
      ),
    );
  }
}

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

class _BalanceOverview extends StatelessWidget {
  const _BalanceOverview({required this.owedToYou, required this.youOwe});

  final int owedToYou;
  final int youOwe;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors.primary, const Color(0xFF004B43)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.acrossAllGroups,
            style: TextStyle(color: colors.onPrimary.withValues(alpha: 0.8)),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _BalanceMetric(
                  label: l10n.youAreOwed,
                  value: formatMoney(owedToYou),
                  icon: Icons.south_west_rounded,
                ),
              ),
              Container(
                width: 1,
                height: 48,
                color: colors.onPrimary.withValues(alpha: 0.2),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 18),
                  child: _BalanceMetric(
                    label: l10n.youOwe,
                    value: formatMoney(youOwe),
                    icon: Icons.north_east_rounded,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BalanceMetric extends StatelessWidget {
  const _BalanceMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onPrimary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 17, color: color.withValues(alpha: 0.8)),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(color: color.withValues(alpha: 0.8))),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
        ),
      ],
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.balance,
    required this.onTap,
  });

  final ExpenseGroup group;
  final int balance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final balanceColor = balance >= 0 ? colors.primary : colors.error;
    final balanceLabel = balance > 0
        ? l10n.groupBalanceOwed
        : balance < 0
            ? l10n.groupBalanceYouOwe
            : l10n.groupBalanceSettled;

    return Card(
      child: InkWell(
        key: Key('group-${group.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Text(group.emoji, style: const TextStyle(fontSize: 27)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      l10n.groupSummary(
                          group.members.length, group.expenses.length),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatMoney(balance.abs()),
                    style: TextStyle(
                      color: balanceColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    balanceLabel,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

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

class InvitationDetailsScreen extends StatelessWidget {
  const InvitationDetailsScreen({required this.invitation, super.key});

  final GroupInvitation invitation;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.invitationDetails)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          CircleAvatar(
            radius: 32,
            child: Text(invitation.group.emoji,
                style: const TextStyle(fontSize: 28)),
          ),
          const SizedBox(height: 16),
          Text(invitation.group.name,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(l10n.sharedGroupInvitation, textAlign: TextAlign.center),
          const SizedBox(height: 32),
          Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text(l10n.responseRequired),
              subtitle: Text(l10n.returnToInbox),
            ),
          ),
        ],
      ),
    );
  }
}

class ContactBalanceDetailsScreen extends StatelessWidget {
  const ContactBalanceDetailsScreen(
      {required this.store, required this.status, super.key});

  final DemoStore store;
  final ContactStatus status;

  List<_GroupBalance> _groupBalances() {
    final balances = <_GroupBalance>[];
    for (final group in store.groups) {
      Member? member;
      for (final candidate in group.members) {
        if (candidate.id == status.member.id) {
          member = candidate;
          break;
        }
      }
      if (member == null) continue;
      final amount = store.balances(group)[member.id] ?? 0;
      if (amount == 0) continue;
      final contactMember = member;
      final concepts = group.expenses
          .where((expense) =>
              expense.payerId == contactMember.id ||
              expense.participantIds.contains(contactMember.id))
          .toList();
      balances.add(_GroupBalance(group, contactMember, amount, concepts));
    }
    return balances;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppCubit, AppState>(
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final balances = _groupBalances();
    final currentAmount =
        balances.fold<int>(0, (total, balance) => total + balance.amount);
    return Scaffold(
      appBar: AppBar(title: Text(status.member.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Text(l10n.balanceDetails,
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(formatMoney(currentAmount.abs()),
              style: Theme.of(context).textTheme.headlineMedium),
          if (currentAmount == 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(l10n.settledUp),
            ),
          const SizedBox(height: 24),
          Text(l10n.byGroup, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (balances.isEmpty)
            Text(l10n.noActiveBalances)
          else
            for (final balance in balances)
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: CircleAvatar(child: Text(balance.group.emoji)),
                      title: Text(balance.group.name),
                      subtitle: Text(balance.amount < 0
                          ? l10n.memberOwesYou(status.member.name)
                          : l10n.youOweMember(status.member.name)),
                      trailing: Text(formatMoney(balance.amount.abs()),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => GroupDetailScreen(
                            store: store,
                            groupId: balance.group.id,
                          ),
                        ),
                      ),
                    ),
                    if (balance.concepts.isNotEmpty) ...[
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(l10n.concepts,
                              style: Theme.of(context).textTheme.labelLarge),
                        ),
                      ),
                      for (final expense in balance.concepts)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.receipt_long_outlined),
                          title: Text(expense.description),
                          trailing: Text(formatMoney(expense.amountCents)),
                        ),
                    ],
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          key: Key('request-payment-${balance.group.id}'),
                          onPressed: () => showSettlementSheet(
                              context,
                              store,
                              balance.group,
                              balance.member,
                              balance.amount, onSettled: () {
                            if (context.mounted) Navigator.of(context).pop();
                            context.read<AppCubit>().showMovements();
                          }),
                          icon: const Icon(Icons.qr_code_2_rounded),
                          label: Text(balance.amount < 0
                              ? l10n.requestPayment
                              : l10n.payContact(status.member.name)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _GroupBalance {
  const _GroupBalance(this.group, this.member, this.amount, this.concepts);

  final ExpenseGroup group;
  final Member member;
  final int amount;
  final List<Expense> concepts;
}

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
          detail: l10n.memberPaid(displayName(expense.payerId)),
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

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    required this.store,
    required this.onLocaleChanged,
    super.key,
  });

  final DemoStore store;
  final ValueChanged<Locale> onLocaleChanged;
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppCubit, AppState>(
      builder: (context, state) {
        final l10n = AppLocalizations.of(context)!;
        final user = state.user;
        final name = user?.name ?? l10n.yourAccount;
        final initials = name
            .trim()
            .split(RegExp(r'\s+'))
            .map((part) => part.isEmpty ? '' : part[0])
            .join()
            .toUpperCase();
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
          children: [
            Text(
              l10n.profile,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 24),
            CircleAvatar(
                radius: 42, child: Text(initials.isEmpty ? '?' : initials)),
            const SizedBox(height: 12),
            Text(
              name,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 28),
            if (user != null)
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.email_outlined),
                      title: Text(l10n.email),
                      trailing: Text(user.email),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.phone_outlined),
                      title: Text(l10n.mobileNumber),
                      trailing: Text(user.phone),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 18),
            Text(l10n.contacts,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(l10n.contactsDescription,
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 10),
            OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ContactsScreen(),
                      ),
                    ),
                icon: const Icon(Icons.contacts_outlined),
                label: Text(l10n.manageContacts)),
            if (state.contacts.isNotEmpty)
              Card(
                  child: Column(children: [
                for (final contact in state.contacts)
                  ListTile(
                      leading: CircleAvatar(
                          child:
                              Text(contact.name.substring(0, 1).toUpperCase())),
                      title: Text(contact.name),
                      subtitle: Text(contact.phone),
                      trailing: const Icon(Icons.person_add_alt_1_rounded))
              ])),
            const SizedBox(height: 18),
            Card(
              child: ListTile(
                key: const Key('language-settings-button'),
                leading: const Icon(Icons.language_outlined),
                title: Text(l10n.language),
                subtitle: Text(l10n.languageDescription),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (sheetContext) {
                    final selected =
                        Localizations.localeOf(context).languageCode;
                    return SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l10n.chooseLanguage,
                                style: Theme.of(context).textTheme.titleLarge),
                            RadioGroup<String>(
                              groupValue: selected,
                              onChanged: (language) {
                                if (language == null) return;
                                onLocaleChanged(Locale(language));
                                Navigator.pop(sheetContext);
                              },
                              child: Column(
                                children: [
                                  RadioListTile<String>(
                                    value: 'es',
                                    title: Text(l10n.spanish),
                                  ),
                                  RadioListTile<String>(
                                    value: 'en',
                                    title: Text(l10n.english),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 18),
            Card(
              child: ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: Text(l10n.paymentProvider),
                subtitle: Text(l10n.simulatedProvider),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  showAboutDialog(
                    context: context,
                    applicationName: l10n.appTitle,
                    applicationVersion: '0.1.0',
                    children: [
                      Text(l10n.aboutSimulatedProvider),
                    ],
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
