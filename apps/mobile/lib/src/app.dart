import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vaquita_mx/src/api_client.dart';
import 'package:vaquita_mx/src/auth_screen.dart';
import 'package:vaquita_mx/src/contacts_screen.dart';
import 'package:vaquita_mx/src/features/app/application/app_cubit.dart';
import 'package:vaquita_mx/src/features/app/application/app_state.dart';
import 'package:vaquita_mx/src/group_detail_screen.dart';
import 'package:vaquita_mx/src/models.dart';
import 'package:vaquita_mx/src/sheets.dart';
import 'package:vaquita_mx/src/store.dart';

class VaquitaApp extends StatefulWidget {
  const VaquitaApp({this.store, super.key});

  final DemoStore? store;

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8080',
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
        title: 'Vaquita MX',
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
                ? AppShell(store: store)
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
  const AppShell({required this.store, super.key});

  final DemoStore store;

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
          created ? '${input.name} created.' : 'Could not create the group.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              ProfileScreen(store: widget.store),
            ],
          ),
        ),
        floatingActionButton: _selectedIndex == 0
            ? FloatingActionButton.extended(
                key: const Key('create-group-button'),
                onPressed: _createGroup,
                icon: const Icon(Icons.add_rounded),
                label: const Text('New group'),
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
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long_rounded),
              label: 'Inbox',
            ),
            NavigationDestination(
              icon: Icon(Icons.swap_horiz_outlined),
              selectedIcon: Icon(Icons.swap_horiz_rounded),
              label: 'Movements',
            ),
            NavigationDestination(
              icon: Icon(Icons.contacts_outlined),
              selectedIcon: Icon(Icons.contacts_rounded),
              label: 'Contacts',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Profile',
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
                        Text('No groups yet',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        const Text(
                            'Create a group and select contacts to get started.',
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
                            'VAQUITA MX',
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
                            'Good afternoon 👋',
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
                    const CircleAvatar(
                      radius: 23,
                      child: Text('YO'),
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
                      title: Text(store.errorMessage!),
                      trailing: TextButton(
                        onPressed: store.load,
                        child: const Text('Retry'),
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
                        'Your groups',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    Text('${store.groups.length} active'),
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
            'Across all groups',
            style: TextStyle(color: colors.onPrimary.withValues(alpha: 0.8)),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _BalanceMetric(
                  label: 'You are owed',
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
                    label: 'You owe',
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
    final colors = Theme.of(context).colorScheme;
    final balanceColor = balance >= 0 ? colors.primary : colors.error;
    final balanceLabel = balance > 0
        ? 'you are owed'
        : balance < 0
            ? 'you owe'
            : 'settled up';

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
                      '${group.members.length} members · ${group.expenses.length} expenses',
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
    setState(() => _respondingInvitationId = invitation.group.id);
    final updated = await context
        .read<AppCubit>()
        .respondToInvitation(invitation.group.id, accept);
    if (!mounted) return;
    setState(() => _respondingInvitationId = null);
    if (updated) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(accept
            ? 'You joined ${invitation.group.name}.'
            : 'Invitation to ${invitation.group.name} declined.'),
      ));
    } else if (widget.store.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.store.errorMessage!)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppCubit, AppState>(
      builder: (context, _) {
        final rows = widget.store.contactStatus;

        return CustomScrollView(
          slivers: [
            SliverAppBar.large(
              title: const Text('Inbox'),
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
                        'You\'re all caught up',
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Invitations and contact balances will appear here.',
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
                                        Text('Join ${invite.group.name}?',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium),
                                        const Text('Shared group invitation'),
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
                                      child: const Text('Decline'),
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
                                          : const Text('Accept invitation'),
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
                            ? 'You owe this contact'
                            : 'This contact owes you'),
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
    return Scaffold(
      appBar: AppBar(title: const Text('Invitation details')),
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
          const Text('Shared group invitation', textAlign: TextAlign.center),
          const SizedBox(height: 32),
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Response required'),
              subtitle:
                  Text('Return to Inbox to accept or decline this invitation.'),
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
    final balances = _groupBalances();
    final currentAmount =
        balances.fold<int>(0, (total, balance) => total + balance.amount);
    return Scaffold(
      appBar: AppBar(title: Text(status.member.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Text('Balance details',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(formatMoney(currentAmount.abs()),
              style: Theme.of(context).textTheme.headlineMedium),
          if (currentAmount == 0)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Settled up'),
            ),
          const SizedBox(height: 24),
          Text('By group', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (balances.isEmpty)
            const Text('No active group balances to show.')
          else
            for (final balance in balances)
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: CircleAvatar(child: Text(balance.group.emoji)),
                      title: Text(balance.group.name),
                      subtitle: Text(balance.amount < 0
                          ? '${status.member.name} owes you'
                          : 'You owe ${status.member.name}'),
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
                          child: Text('Concepts',
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
                              ? 'Request payment'
                              : 'Pay ${status.member.name}'),
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

  List<_Movement> _items() {
    final items = <_Movement>[];
    for (final group in store.groups) {
      final members = {for (final member in group.members) member.id: member};
      for (final expense in group.expenses) {
        items.add(_Movement(
          group: group,
          title: expense.description,
          detail: '${members[expense.payerId]?.name ?? 'A member'} paid',
          amountCents: expense.amountCents,
          occurredAt: expense.createdAt,
          isSettlement: false,
        ));
      }
      for (final settlement in group.settlements) {
        final from = members[settlement.fromMemberId]?.name ?? 'A member';
        final to = members[settlement.toMemberId]?.name ?? 'a member';
        items.add(_Movement(
          group: group,
          title: '$from paid $to',
          detail: 'Settlement',
          amountCents: settlement.amountCents,
          occurredAt: settlement.createdAt,
          isSettlement: true,
        ));
      }
    }
    items.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return items;
  }

  String _relativeDate(DateTime value) {
    final date = value.toLocal();
    final today = DateUtils.dateOnly(DateTime.now());
    final daysAgo = today.difference(DateUtils.dateOnly(date)).inDays;
    if (daysAgo == 0) return 'Today';
    if (daysAgo == 1) return 'Yesterday';
    if (daysAgo < 7) return '$daysAgo days ago';
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppCubit, AppState>(
      builder: (context, _) {
        final items = _items();
        return CustomScrollView(
          slivers: [
            SliverAppBar.large(
              title: const Text('Movements'),
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
                        Text('No movements yet',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 8),
                        const Text(
                          'Expenses and settlements from your groups will appear here.',
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
                        subtitle: Text(
                            '${item.group.emoji} ${item.group.name} · ${item.detail} · ${_relativeDate(item.occurredAt)}'),
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
  const ProfileScreen({required this.store, super.key});

  final DemoStore store;
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppCubit, AppState>(
      builder: (context, state) {
        final user = state.user;
        final name = user?.name ?? 'Your account';
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
              'Profile',
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
                      title: const Text('Email'),
                      trailing: Text(user.email),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.phone_outlined),
                      title: const Text('Mobile number'),
                      trailing: Text(user.phone),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 18),
            Text('Contacts',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
                'Find people already using Vaquita. Your contacts are matched only after you choose this.',
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 10),
            OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ContactsScreen(),
                      ),
                    ),
                icon: const Icon(Icons.contacts_outlined),
                label: const Text('Manage contacts')),
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
                leading: const Icon(Icons.shield_outlined),
                title: const Text('Payment provider'),
                subtitle: const Text('Simulated — no real money moves'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  showAboutDialog(
                    context: context,
                    applicationName: 'Vaquita MX',
                    applicationVersion: '0.1.0',
                    children: const [
                      Text(
                        'This build demonstrates the future CoDi collection flow with a simulated provider.',
                      ),
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
