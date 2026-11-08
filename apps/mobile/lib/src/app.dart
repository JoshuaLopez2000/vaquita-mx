import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
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
import 'package:vaquita_mx/src/offline_database.dart';
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
  DemoStore? store;
  AppCubit? appCubit;
  late final bool _ownsStore;
  var _restoringSession = true;
  var _locale = const Locale('es');
  String? _initializationError;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  void _setLocale(Locale locale) => setState(() => _locale = locale);

  @override
  void initState() {
    super.initState();
    _ownsStore = widget.store == null;
    if (_ownsStore) {
      _initializeStore();
    } else {
      store = widget.store!;
      appCubit = AppCubit(store!);
      _restoringSession = false;
    }
  }

  Future<void> _initializeStore() async {
    try {
      final api = ApiClient(baseUrl: VaquitaApp.apiBaseUrl);
      api.onSessionInvalidated = _handleInvalidSession;
      final database = kIsWeb ? null : await OfflineDatabase.open();
      final initializedStore = DemoStore.offline(api, database);
      final initializedCubit = AppCubit(initializedStore);
      await initializedStore.initialize();
      final restored = await api.restoreSession();
      store = initializedStore;
      appCubit = initializedCubit;
      if (restored) {
        await initializedStore.refreshAuthentication();
        initializedStore.load();
      }
      if (!kIsWeb) _listenForReconnects();
    } catch (error) {
      _initializationError = error.toString();
    }
    if (!mounted) return;
    setState(() {
      _restoringSession = false;
    });
  }

  void _handleInvalidSession() {
    if (!mounted) return;
    unawaited(store?.refreshAuthentication());
  }

  void _listenForReconnects() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      _syncWhenOnline,
      onError: (Object error, StackTrace stackTrace) {
        store?.reportConnectivityError();
      },
    );
    unawaited(Connectivity().checkConnectivity().then(_syncWhenOnline));
  }

  Future<void> _syncWhenOnline(List<ConnectivityResult> results) async {
    if (results.any((result) => result != ConnectivityResult.none) &&
        store?.isAuthenticated == true) {
      await store?.syncLocalGroups();
    }
  }

  Future<void> _signOut(bool allDevices) async {
    try {
      await store?.apiClient?.signOut(allDevices: allDevices);
    } finally {
      await store?.refreshAuthentication();
    }
  }

  @override
  void dispose() {
    unawaited(_connectivitySubscription?.cancel());
    appCubit?.close();
    if (_ownsStore) {
      store?.dispose();
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

    final materialApp = MaterialApp(
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
          : _initializationError != null
              ? Scaffold(
                  body: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_initializationError!),
                    ),
                  ),
                )
              : BlocProvider.value(
                  value: appCubit!,
                  child: AppShell(
                    store: store!,
                    onLocaleChanged: _setLocale,
                    onSignOut: _signOut,
                  ),
                ),
    );
    return appCubit == null
        ? materialApp
        : BlocProvider.value(value: appCubit!, child: materialApp);
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
      allowShared: widget.store.isAuthenticated,
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

  Future<void> _authenticate() async {
    final api = widget.store.apiClient;
    if (api == null) return;
    final cubit = context.read<AppCubit>();
    final navigator = Navigator.of(context);
    await navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AuthScreen(
          api: api,
          onAuthenticated: () async {
            await widget.store.refreshAuthentication();
            await cubit.loadGroups();
          },
        ),
      ),
    );
    if (!mounted || !widget.store.isAuthenticated) return;
    final l10n = AppLocalizations.of(context)!;
    final shouldSync = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.syncLocalGroupsTitle),
        content: Text(l10n.syncLocalGroupsDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.later),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.syncNow),
          ),
        ],
      ),
    );
    if (!mounted || shouldSync != true) return;
    final synced = await cubit.syncLocalGroups(enable: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(synced ? l10n.syncCompleted : l10n.syncFailed)),
    );
  }

  Future<void> _syncNow() async {
    final l10n = AppLocalizations.of(context)!;
    final cubit = context.read<AppCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final synced = await cubit.syncLocalGroups(enable: true);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(synced ? l10n.syncCompleted : l10n.syncFailed)),
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
                onAuthenticate: _authenticate,
                onSync: _syncNow,
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
