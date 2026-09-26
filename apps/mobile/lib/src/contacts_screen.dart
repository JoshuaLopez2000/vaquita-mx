import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vaquita_mx/src/features/app/application/app_cubit.dart';
import 'package:vaquita_mx/src/features/app/application/app_state.dart';
import 'package:vaquita_mx/src/models.dart';

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
    final name = TextEditingController();
    final phone = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add contact'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 12),
          TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration:
                  const InputDecoration(labelText: 'Mexican mobile number')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (saved == true && mounted) {
      final success = await context
          .read<AppCubit>()
          .saveContact(name.text.trim(), phone.text.trim());
      if (mounted && !success) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not save contact.')));
      }
    }
    name.dispose();
    phone.dispose();
  }

  Future<void> _removeContact(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove contact?'),
        content:
            const Text('This will not remove them from any existing groups.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<AppCubit>().removeContact(id);
    }
  }

  Future<void> _importFromPhone() async {
    final cubit = context.read<AppCubit>();
    try {
      final raw =
          await _phoneContacts.invokeMethod<List<dynamic>>('getContacts');
      if (!mounted) return;
      final contacts = (raw ?? const [])
          .whereType<Map<dynamic, dynamic>>()
          .map((entry) => _PhoneContact(
              name: entry['name'] as String? ?? '',
              phone: entry['phone'] as String? ?? ''))
          .where(
              (contact) => contact.name.isNotEmpty && contact.phone.isNotEmpty)
          .toList();
      final selected = await _selectContacts(contacts);
      if (!mounted || selected == null || selected.isEmpty) return;
      final saved = await cubit.saveContacts(selected
          .map((contact) =>
              AppContact(id: '', name: contact.name, phone: contact.phone))
          .toList());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(saved
                ? '${selected.length} contacts imported.'
                : 'Could not import contacts.')));
      }
    } on PlatformException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error.message ?? 'Contacts permission was denied.')));
      }
    }
  }

  Future<List<_PhoneContact>?> _selectContacts(List<_PhoneContact> contacts) {
    final selected = <int>{};
    return showModalBottomSheet<List<_PhoneContact>>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .78,
            child: Column(children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Text('Import contacts',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
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
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () => Navigator.pop(sheetContext,
                          selected.map((index) => contacts[index]).toList()),
                  child: Text('Import ${selected.length} selected'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Contacts'),
          actions: [
            IconButton(
              tooltip: 'Import from phone',
              onPressed: _importFromPhone,
              icon: const Icon(Icons.contact_phone_outlined),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _addContact,
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: const Text('Add contact'),
        ),
        body: BlocBuilder<AppCubit, AppState>(
          builder: (context, state) {
            if (state.contacts.isEmpty) {
              return const Center(child: Text('No contacts saved yet.'));
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
              itemCount: state.contacts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final contact = state.contacts[index];
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                        child:
                            Text(contact.name.substring(0, 1).toUpperCase())),
                    title: Text(contact.name),
                    subtitle: Text(contact.phone),
                    trailing: IconButton(
                      tooltip: 'Remove contact',
                      icon: const Icon(Icons.delete_outline),
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

class _PhoneContact {
  const _PhoneContact({required this.name, required this.phone});

  final String name;
  final String phone;
}
