part of '../app.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    required this.store,
    required this.onLocaleChanged,
    required this.onSignOut,
    super.key,
  });

  final DemoStore store;
  final ValueChanged<Locale> onLocaleChanged;
  final Future<void> Function(bool allDevices) onSignOut;
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
            if (store.isRemote) ...[
              const SizedBox(height: 18),
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
                      leading: const Icon(Icons.phonelink_erase_rounded),
                      title: Text(l10n.signOutAll),
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
