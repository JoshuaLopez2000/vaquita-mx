part of '../sheets.dart';

class _CreateGroupSheet extends StatefulWidget {
  const _CreateGroupSheet({
    required this.contacts,
    required this.allowShared,
  });

  final List<AppContact> contacts;
  final bool allowShared;

  @override
  State<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<_CreateGroupSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _memberNameController = TextEditingController();
  final _memberPhoneController = TextEditingController();
  final _members = <GroupMemberDraft>[];
  final _emojiController = TextEditingController();
  var _visibility = 'personal';
  var _salarySplits = false;

  @override
  void dispose() {
    _nameController.dispose();
    _memberNameController.dispose();
    _memberPhoneController.dispose();
    _emojiController.dispose();
    super.dispose();
  }

  void _submit() {
    final l10n = AppLocalizations.of(context)!;
    if (!_formKey.currentState!.validate()) return;
    final pendingName = _memberNameController.text.trim();
    final pendingPhone = _memberPhoneController.text.trim();
    if (pendingName.isNotEmpty || pendingPhone.isNotEmpty) {
      if (pendingName.isEmpty || pendingPhone.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.memberNeedsNamePhone)),
        );
        return;
      }
      _members.add(GroupMemberDraft(name: pendingName, phone: pendingPhone));
    }
    if (_members.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.addAtLeastOneMember)),
      );
      return;
    }
    Navigator.pop(
      context,
      NewGroupInput(
        name: _nameController.text.trim(),
        memberNames: _members.map((member) => member.name).toList(),
        members: List.unmodifiable(
          _members
              .map((member) => {'name': member.name, 'phone': member.phone})
              .toList(),
        ),
        emoji: _emojiController.text.trim(),
        visibility: _visibility,
        salarySplitEnabled: _salarySplits,
      ),
    );
  }

  void _addMember() {
    final l10n = AppLocalizations.of(context)!;
    final name = _memberNameController.text.trim();
    final phone = _memberPhoneController.text.trim();
    if (name.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.enterNamePhone)),
      );
      return;
    }
    setState(() {
      _members.add(GroupMemberDraft(name: name, phone: phone));
      _memberNameController.clear();
      _memberPhoneController.clear();
    });
  }

  void _toggleContact(AppContact contact) {
    setState(() {
      final index =
          _members.indexWhere((member) => member.phone == contact.phone);
      if (index >= 0) {
        _members.removeAt(index);
      } else {
        _members
            .add(GroupMemberDraft(name: contact.name, phone: contact.phone));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SheetHandle(),
              Text(
                l10n.createAGroup,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                l10n.createGroupDescription,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                key: const Key('group-name-field'),
                controller: _nameController,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: l10n.groupName,
                  hintText: l10n.beachWeekend,
                  prefixIcon: const Icon(Icons.groups_rounded),
                ),
                validator: (value) => value == null || value.trim().length < 2
                    ? l10n.enterGroupName
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('group-emoji-picker'),
                controller: _emojiController,
                readOnly: true,
                onTap: () async {
                  final selected = await showGroupEmojiPicker(context);
                  if (selected != null) _emojiController.text = selected;
                },
                decoration: InputDecoration(
                  labelText: l10n.groupIcon,
                  prefixIcon: const Icon(Icons.emoji_emotions_outlined),
                  suffixIcon: const Icon(Icons.expand_more_rounded),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? l10n.groupIcon
                    : null,
              ),
              const SizedBox(height: 12),
              if (widget.allowShared) ...[
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'personal',
                      icon: const Icon(Icons.lock_outline_rounded, size: 18),
                      label: Text(l10n.personal),
                    ),
                    ButtonSegment(
                      value: 'shared',
                      icon: const Icon(Icons.groups_outlined, size: 18),
                      label: Text(l10n.shared),
                    ),
                  ],
                  selected: {_visibility},
                  onSelectionChanged: (value) =>
                      setState(() => _visibility = value.first),
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _salarySplits,
                  title: Text(l10n.allowSalarySplits),
                  subtitle: Text(l10n.salaryOptInOnly),
                  onChanged: (value) => setState(() => _salarySplits = value),
                ),
                if (_salarySplits) ...[
                  const SalaryInferenceNotice(),
                  const SizedBox(height: 8),
                ],
              ],
              if (widget.contacts.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.addSavedContacts,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final contact in widget.contacts)
                      FilterChip(
                        label: Text(contact.name),
                        selected: _members
                            .any((member) => member.phone == contact.phone),
                        onSelected: (_) => _toggleContact(contact),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              TextFormField(
                key: const Key('group-members-field'),
                controller: _memberNameController,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _addMember(),
                decoration: InputDecoration(
                  labelText: l10n.memberName,
                  hintText: l10n.memberNamesExample,
                  prefixIcon: const Icon(Icons.person_add_alt_1_rounded),
                ),
                validator: (_) => null,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _memberPhoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: l10n.mexicanMobileNumber,
                  prefixIcon: const Icon(Icons.phone_iphone_rounded),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: l10n.addMember,
                    onPressed: _addMember,
                  ),
                ),
                onSubmitted: (_) => _addMember(),
              ),
              if (_members.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (var index = 0; index < _members.length; index++)
                        InputChip(
                          label: Text(
                            _members[index].phone.isEmpty
                                ? _members[index].name
                                : '${_members[index].name} · ${_members[index].phone}',
                          ),
                          onDeleted: () =>
                              setState(() => _members.removeAt(index)),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              FilledButton.icon(
                key: const Key('create-group-submit'),
                onPressed: _submit,
                icon: const Icon(Icons.add_rounded),
                label: Text(l10n.createGroup),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
