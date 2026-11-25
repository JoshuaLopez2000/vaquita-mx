import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vaquita_mx/l10n/app_localizations.dart';
import 'package:vaquita_mx/src/features/app/application/app_cubit.dart';
import 'package:vaquita_mx/src/features/app/application/app_state.dart';
import 'package:vaquita_mx/src/models.dart';
import 'package:vaquita_mx/src/widgets/vaquita_brand.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  static const _phoneContacts = MethodChannel('mx.vaquita.vaquita_mx/contacts');

  @override
  void initState() {
    super.initState();
    context.read<AppCubit>().loadContacts();
  }

  Future<void> _addContact() async {
    final l10n = AppLocalizations.of(context)!;
    final name = TextEditingController();
    final phone = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.addContact),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: l10n.accountName,
                prefixIcon: const Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: l10n.mexicanMobileNumber,
                prefixIcon: const Icon(Icons.phone_iphone_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    if (saved == true && mounted) {
      final success = await context
          .read<AppCubit>()
          .saveContact(name.text.trim(), phone.text.trim());
      if (mounted && !success) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.couldNotSaveContact)));
      }
    }
    name.dispose();
    phone.dispose();
  }

  Future<void> _removeContact(String id) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.removeContact),
        content: Text(l10n.removeContactDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.remove),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<AppCubit>().removeContact(id);
    }
  }

  Future<void> _importFromPhone() async {
    final l10n = AppLocalizations.of(context)!;
    final cubit = context.read<AppCubit>();
    try {
      final raw =
          await _phoneContacts.invokeMethod<List<dynamic>>('getContacts');
      if (!mounted) return;
      final contacts = (raw ?? const [])
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (entry) => _PhoneContact(
              name: entry['name'] as String? ?? '',
              phone: entry['phone'] as String? ?? '',
            ),
          )
          .where(
            (contact) => contact.name.isNotEmpty && contact.phone.isNotEmpty,
          )
          .toList();
      final selected = await _selectContacts(contacts);
      if (!mounted || selected == null || selected.isEmpty) return;
      final saved = await cubit.saveContacts(
        selected
            .map(
              (contact) =>
                  AppContact(id: '', name: contact.name, phone: contact.phone),
            )
            .toList(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              saved
                  ? l10n.importSelected(selected.length)
                  : l10n.couldNotImportContacts,
            ),
          ),
        );
      }
    } on PlatformException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message ?? l10n.contactsPermissionDenied),
          ),
        );
      }
    }
  }

  Future<List<_PhoneContact>?> _selectContacts(List<_PhoneContact> contacts) {
    final l10n = AppLocalizations.of(context)!;
    final selected = <int>{};
    return showModalBottomSheet<List<_PhoneContact>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .78,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                  child: Text(
                    l10n.importContacts,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: contacts.length,
                    itemBuilder: (_, index) => CheckboxListTile(
                      value: selected.contains(index),
                      title: Text(contacts[index].name),
                      subtitle: Text(contacts[index].phone),
                      onChanged: (value) => setSheetState(() {
                        if (value ?? false) {
                          selected.add(index);
                        } else {
                          selected.remove(index);
                        }
                      }),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: FilledButton(
                    onPressed: selected.isEmpty
                        ? null
                        : () => Navigator.pop(
                              sheetContext,
                              selected.map((index) => contacts[index]).toList(),
                            ),
                    child: Text(l10n.importSelected(selected.length)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.contacts),
        actions: [
          IconButton(
            tooltip: l10n.importFromPhone,
            onPressed: _importFromPhone,
            icon: const Icon(Icons.contact_phone_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addContact,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: Text(l10n.addContact),
      ),
      body: BlocBuilder<AppCubit, AppState>(
        builder: (context, state) {
          if (state.contacts.isEmpty) {
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 80),
                child: VaquitaEmptyState(
                  icon: Icons.contacts_outlined,
                  title: l10n.noContactsSaved,
                  description: l10n.noContactsDescription,
                  action: OutlinedButton.icon(
                    onPressed: _importFromPhone,
                    icon: const Icon(Icons.contact_phone_outlined),
                    label: Text(l10n.importFromPhone),
                  ),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
            itemCount: state.contacts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final contact = state.contacts[index];
              final initial = contact.name.trim().isEmpty
                  ? '?'
                  : contact.name.trim().substring(0, 1).toUpperCase();
              return Card(
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  leading: CircleAvatar(
                    backgroundColor: colors.primaryContainer,
                    foregroundColor: colors.onPrimaryContainer,
                    child: Text(
                      initial,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  title: Text(
                    contact.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(contact.phone),
                  trailing: IconButton(
                    tooltip: l10n.removeContactTooltip,
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () => _removeContact(contact.id),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _PhoneContact {
  const _PhoneContact({required this.name, required this.phone});

  final String name;
  final String phone;
}
