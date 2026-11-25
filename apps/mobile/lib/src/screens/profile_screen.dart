part of '../app.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    required this.store,
    required this.onLocaleChanged,
    required this.onSignOut,
    required this.onAuthenticate,
    required this.onSync,
    super.key,
  });

  final DemoStore store;
  final ValueChanged<Locale> onLocaleChanged;
  final Future<void> Function(bool allDevices) onSignOut;
  final Future<void> Function() onAuthenticate;
  final Future<void> Function() onSync;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppCubit, AppState>(
      builder: (context, state) {
        final l10n = AppLocalizations.of(context)!;
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final vColors = VaquitaColors.of(context);
        final user = state.user;
        final name = user?.name ?? l10n.yourAccount;
        final initials = name
            .trim()
            .split(RegExp(r'\s+'))
            .map((part) => part.isEmpty ? '' : part[0])
            .join()
            .toUpperCase();

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Text(
              l10n.profile,
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [vColors.heroStart, vColors.heroEnd],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        initials.isEmpty ? '?' : initials,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: vColors.onHero,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: user != null
                                  ? vColors.positiveContainer
                                  : colors.secondaryContainer,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  user != null
                                      ? Icons.cloud_done_outlined
                                      : Icons.phone_android_rounded,
                                  size: 14,
                                  color: user != null
                                      ? vColors.onPositiveContainer
                                      : colors.onSecondaryContainer,
                                ),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    user != null
                                        ? user.email
                                        : l10n.offlineModeNotice,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: user != null
                                          ? vColors.onPositiveContainer
                                          : colors.onSecondaryContainer,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.accountSection,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (user == null && store.apiClient != null)
              Card(
                child: ListTile(
                  key: const Key('login-signup-button'),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  leading: Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.login_rounded,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                  title: Text(
                    l10n.loginOrSignUp,
                    style: theme.textTheme.titleSmall,
                  ),
                  subtitle: Text(l10n.loginOrSignUpDescription),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: onAuthenticate,
                ),
              ),
            if (user != null)
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.email_outlined),
                      title: Text(l10n.email),
                      subtitle: Text(user.email),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.phone_outlined),
                      title: Text(l10n.mobileNumber),
                      subtitle: Text(user.phone),
                    ),
                  ],
                ),
              ),
            if (user != null && store.isOfflineFirst) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('sync-local-groups-button'),
                onPressed: onSync,
                icon: const Icon(Icons.sync_rounded),
                label: Text(l10n.syncLocalGroupsButton),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              l10n.contacts,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.contactsDescription,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ContactsScreen(),
                ),
              ),
              icon: const Icon(Icons.contacts_outlined),
              label: Text(l10n.manageContacts),
            ),
            if (state.contacts.isNotEmpty) ...[
              const SizedBox(height: 10),
              Card(
                child: Column(
                  children: [
                    for (var i = 0; i < state.contacts.length; i++) ...[
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: colors.primaryContainer,
                          foregroundColor: colors.onPrimaryContainer,
                          child: Text(
                            state.contacts[i].name.trim().isEmpty
                                ? '?'
                                : state.contacts[i].name
                                    .trim()
                                    .substring(0, 1)
                                    .toUpperCase(),
                          ),
                        ),
                        title: Text(state.contacts[i].name),
                        subtitle: Text(state.contacts[i].phone),
                      ),
                      if (i != state.contacts.length - 1)
                        const Divider(height: 1, indent: 72),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              l10n.preferencesSection,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  ListTile(
                    key: const Key('language-settings-button'),
                    leading: const Icon(Icons.language_outlined),
                    title: Text(l10n.language),
                    subtitle: Text(l10n.languageDescription),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => showModalBottomSheet<void>(
                      context: context,
                      showDragHandle: true,
                      builder: (sheetContext) {
                        final selected =
                            Localizations.localeOf(context).languageCode;
                        return SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.chooseLanguage,
                                  style: theme.textTheme.titleLarge,
                                ),
                                const SizedBox(height: 8),
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
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(
                      Icons.shield_outlined,
                      color: vColors.warning,
                    ),
                    title: Text(l10n.paymentProvider),
                    subtitle: Text(l10n.simulatedProvider),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      showAboutDialog(
                        context: context,
                        applicationIcon: const VaquitaLogoMark(size: 48),
                        applicationName: l10n.appTitle,
                        applicationVersion: '0.1.0',
                        children: [
                          Text(l10n.aboutSimulatedProvider),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            if (user != null) ...[
              const SizedBox(height: 22),
              Text(
                l10n.securitySection,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      key: const Key('sign-out-button'),
                      leading: const Icon(Icons.logout_rounded),
                      title: Text(l10n.signOut),
                      subtitle: Text(l10n.signOutDescription),
                      onTap: () => onSignOut(false),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      key: const Key('sign-out-all-button'),
                      leading: Icon(
                        Icons.phonelink_erase_rounded,
                        color: colors.error,
                      ),
                      title: Text(
                        l10n.signOutAll,
                        style: TextStyle(color: colors.error),
                      ),
                      subtitle: Text(l10n.signOutAllDescription),
                      onTap: () => onSignOut(true),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
