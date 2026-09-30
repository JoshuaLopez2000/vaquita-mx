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

part 'screens/dashboard_screen.dart';
part 'screens/inbox_screen.dart';
part 'screens/movements_screen.dart';
part 'screens/profile_screen.dart';
part 'screens/invitation_details_screen.dart';
part 'screens/contact_balance_details_screen.dart';
part 'widgets/balance_overview.dart';
part 'widgets/balance_metric.dart';
part 'widgets/group_card.dart';

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
      store.apiClient!.onSessionInvalidated = _handleInvalidSession;
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

  void _handleInvalidSession() {
    if (!mounted) return;
    setState(() => _authenticated = false);
  }

  Future<void> _signOut(bool allDevices) async {
    await store.apiClient?.signOut(allDevices: allDevices);
    if (!mounted) return;
    setState(() => _authenticated = false);
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
                ? AppShell(
                    store: store,
                    onLocaleChanged: _setLocale,
                    onSignOut: _signOut,
                  )
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
    required this.onSignOut,
    super.key,
  });

  final DemoStore store;
  final ValueChanged<Locale> onLocaleChanged;
  final Future<void> Function(bool allDevices) onSignOut;

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
                onSignOut: widget.onSignOut,
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
