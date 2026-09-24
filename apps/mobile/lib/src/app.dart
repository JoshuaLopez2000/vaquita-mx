import 'package:flutter/material.dart';
import 'package:vaquita_mx/src/api_client.dart';
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
  late final bool _ownsStore;

  @override
  void initState() {
    super.initState();
    _ownsStore = widget.store == null;
    store = widget.store ??
        DemoStore.remote(ApiClient(baseUrl: VaquitaApp.apiBaseUrl));
    if (_ownsStore) {
      store.load();
    }
  }

  @override
  void dispose() {
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

    return MaterialApp(
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
      home: AppShell(store: store),
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

  Future<void> _createGroup() async {
    final input = await showCreateGroupSheet(context);
    if (input == null || !mounted) return;
    final created = await widget.store.createGroup(
      name: input.name,
      memberNames: input.memberNames,
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
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _selectedIndex,
          children: [
            DashboardScreen(store: widget.store),
            ActivityScreen(store: widget.store),
            const ProfileScreen(),
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
          setState(() => _selectedIndex = index);
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
            label: 'Activity',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({required this.store, super.key});

  final DemoStore store;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
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

class ActivityScreen extends StatelessWidget {
  const ActivityScreen({required this.store, super.key});

  final DemoStore store;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final rows = [
          for (final group in store.groups)
            for (final expense in group.expenses)
              (group: group, expense: expense),
        ]..sort((a, b) => b.expense.createdAt.compareTo(a.expense.createdAt));

        return CustomScrollView(
          slivers: [
            SliverAppBar.large(
              title: const Text('Activity'),
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              sliver: SliverList.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final row = rows[index];
                  final payer = row.group.members
                      .firstWhere((member) => member.id == row.expense.payerId);
                  return Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 7,
                      ),
                      leading: CircleAvatar(child: Text(row.group.emoji)),
                      title: Text(row.expense.description),
                      subtitle:
                          Text('${row.group.name} · paid by ${payer.name}'),
                      trailing: Text(
                        formatMoney(row.expense.amountCents),
                        style: const TextStyle(fontWeight: FontWeight.w700),
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

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
        const CircleAvatar(radius: 42, child: Text('YO')),
        const SizedBox(height: 12),
        Text(
          'Demo user',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 28),
        Card(
          child: Column(
            children: [
              const ListTile(
                leading: Icon(Icons.language_rounded),
                title: Text('Language'),
                trailing: Text('English'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.cloud_outlined),
                title: const Text('API environment'),
                subtitle: const Text(VaquitaApp.apiBaseUrl),
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Text('DEMO'),
                ),
              ),
            ],
          ),
        ),
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
  }
}
