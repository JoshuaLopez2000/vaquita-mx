import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:vaquita_mx/src/offline_database.dart';
import 'package:vaquita_mx/src/api_client.dart';
import 'package:vaquita_mx/src/models.dart';

class DemoStore extends ChangeNotifier {
  DemoStore.seeded()
      : _apiClient = null,
        _offlineDatabase = null,
        _offlineFirst = false,
        groups = _seedGroups();

  DemoStore.remote(this._apiClient)
      : _offlineDatabase = null,
        _offlineFirst = false,
        groups = [];

  DemoStore.offline(this._apiClient, this._offlineDatabase)
      : _offlineFirst = true,
        groups = [];

  static const seedUserId = 'me';
  final ApiClient? _apiClient;
  final OfflineDatabase? _offlineDatabase;
  final bool _offlineFirst;
  final List<ExpenseGroup> groups;
  final List<AppContact> contacts = [];
  final List<ContactStatus> contactStatus = [];
  final List<GroupInvitation> invitations = [];
  int _sequence = 100;
  int? _requestedTab;
  bool isLoading = false;
  String? errorMessage;
  final Set<String> _syncEnabledInMemory = {};
  final Set<String> _serverSyncedGroupIds = {};
  bool _syncing = false;
  bool _syncRequested = false;

  bool get isRemote => _apiClient != null;
  bool get isOfflineFirst => _offlineFirst;
  bool get isAuthenticated => _apiClient?.user != null;
  ApiClient? get apiClient => _apiClient;

  bool canUseServerFeatures(ExpenseGroup group) {
    if (!isAuthenticated) return false;
    return !_offlineFirst ||
        !group.id.startsWith('local_') ||
        _serverSyncedGroupIds.contains(group.id);
  }

  bool canRequestPayment(ExpenseGroup group) =>
      group.visibility == 'shared' && canUseServerFeatures(group);

  String get currentUserId => _apiClient?.userId ?? seedUserId;
  AppUser? get authenticatedUser => _apiClient?.user;
  Member get currentUser => Member(
        id: currentUserId,
        userId: _apiClient?.userId ?? '',
        name: _apiClient?.user?.name ?? 'You',
      );

  Future<void> initialize() async {
    if (_offlineDatabase == null) return;
    _serverSyncedGroupIds.addAll(await _offlineDatabase.syncedGroupIds());
    groups
      ..clear()
      ..addAll(await _offlineDatabase.loadGroups());
    notifyListeners();
  }

  void showMovements() {
    _requestedTab = 2;
    notifyListeners();
  }

  int? takeRequestedTab() {
    final tab = _requestedTab;
    _requestedTab = null;
    return tab;
  }

  ExpenseGroup groupById(String id) =>
      groups.firstWhere((group) => group.id == id);

  Future<void> load() async {
    final api = _apiClient;
    if (api == null || api.user == null) return;
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final loaded = await api.listGroups();
      if (_offlineFirst) {
        for (final group in loaded) {
          final index = groups.indexWhere((local) => local.id == group.id);
          final hasPendingChanges =
              await _offlineDatabase?.isPending(group.id) ?? false;
          if (index >= 0 && hasPendingChanges) {
            continue;
          } else if (index >= 0) {
            groups[index] = group;
          } else {
            groups.add(group);
          }
          if (group.id.startsWith('local_')) {
            _serverSyncedGroupIds.add(group.id);
          }
          await _offlineDatabase?.saveGroup(group, needsSync: false);
        }
      } else {
        groups
          ..clear()
          ..addAll(loaded);
      }
    } on ApiException catch (error) {
      errorMessage = error.code;
    } catch (_) {
      errorMessage = 'server_unavailable';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> syncLocalGroups({bool enable = false}) async {
    final api = _apiClient;
    if (api == null || api.user == null || !_offlineFirst) return false;
    if (_syncing) {
      _syncRequested = true;
      return true;
    }
    isLoading = true;
    _syncing = true;
    errorMessage = null;
    notifyListeners();
    try {
      final accountId = api.userId;
      if (accountId == null) return false;
      if (enable) {
        _syncEnabledInMemory.add(accountId);
        await _offlineDatabase?.setSyncEnabled(accountId, true);
      } else {
        final enabled = _offlineDatabase != null
            ? await _offlineDatabase.syncEnabled(accountId)
            : _syncEnabledInMemory.contains(accountId);
        if (!enabled) return true;
      }

      do {
        _syncRequested = false;
        final pending =
            await _offlineDatabase?.groupsPendingSync() ?? List.of(groups);
        if (pending.isEmpty) break;
        final revisions = <String, int>{
          for (final group in pending)
            group.id: await _offlineDatabase?.revision(group.id) ?? 1,
        };
        final syncedIds = await api.syncLocalGroups(pending);
        for (final group in pending) {
          final remoteId = syncedIds[group.id];
          if (remoteId == null) {
            throw const FormatException('Sync response omitted a local group');
          }
          await _offlineDatabase?.markSynced(
              group.id, remoteId, revisions[group.id]!);
          if (await _offlineDatabase?.isPending(group.id) ?? false) {
            _serverSyncedGroupIds.remove(group.id);
          } else {
            _serverSyncedGroupIds.add(group.id);
          }
        }
      } while (_offlineDatabase != null &&
          (_syncRequested || await _offlineDatabase.hasPendingGroups()));
      await load();
      return true;
    } on ApiException catch (error) {
      errorMessage = error.code;
      return false;
    } catch (_) {
      errorMessage = 'server_request_failed';
      return false;
    } finally {
      _syncing = false;
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> findContacts(List<String> phones) async {
    final api = _apiClient;
    if (api == null || api.user == null) return;
    contacts
      ..clear()
      ..addAll(await api.matchContacts(phones));
    notifyListeners();
  }

  Future<void> loadContacts() async {
    final api = _apiClient;
    if (api == null || api.user == null) return;
    contacts
      ..clear()
      ..addAll(await api.listContacts());
    notifyListeners();
  }

  Future<bool> saveContact(String name, String phone) async {
    return saveContacts([AppContact(id: '', name: name, phone: phone)]);
  }

  Future<bool> saveContacts(List<AppContact> newContacts) async {
    if (_apiClient == null || _offlineFirst) {
      contacts.addAll(newContacts.map((contact) => AppContact(
          id: _nextId('contact'), name: contact.name, phone: contact.phone)));
      notifyListeners();
      return true;
    }
    return _syncContacts(() async {
      await _apiClient.saveContacts(newContacts);
    });
  }

  Future<bool> removeContact(String contactId) async {
    if (_apiClient == null || _offlineFirst) {
      contacts.removeWhere((contact) => contact.id == contactId);
      notifyListeners();
      return true;
    }
    return _syncContacts(() => _apiClient.removeContact(contactId));
  }

  Future<bool> _syncContacts(Future<void> Function() mutation) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      await mutation();
      await loadContacts();
      return true;
    } on ApiException catch (error) {
      errorMessage = error.code;
      return false;
    } catch (_) {
      errorMessage = 'server_request_failed';
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createGroup({
    required String name,
    required List<String> memberNames,
    String emoji = '',
    String visibility = 'personal',
    bool salarySplitEnabled = false,
    List<Map<String, String>>? members,
  }) async {
    if (!isAuthenticated) {
      visibility = 'personal';
      salarySplitEnabled = false;
    }
    if (_apiClient != null && !_offlineFirst) {
      return _sync(
        () => _apiClient.createGroup(
            name: name,
            memberNames: memberNames,
            emoji: emoji,
            visibility: visibility,
            salarySplitEnabled: salarySplitEnabled,
            members: members),
      );
    }
    final id = _offlineFirst ? _newLocalId('local_group') : _nextId('group');
    final localMembers = <Member>[
      Member(
        id: _offlineFirst ? seedUserId : currentUserId,
        userId: _apiClient?.userId ?? '',
        name: _apiClient?.user?.name ?? 'You',
      )
    ];
    final drafts = members ??
        memberNames
            .map((name) => <String, String>{'name': name, 'phone': ''})
            .toList();
    for (final draft in drafts) {
      final rawName = draft['name'] ?? '';
      final trimmed = rawName.trim();
      if (trimmed.isEmpty || trimmed.toLowerCase() == 'you') continue;
      localMembers.add(Member(
        id: _offlineFirst ? _newLocalId('local_member') : _nextId('member'),
        name: trimmed,
        phone: draft['phone'] ?? '',
        accepted: true,
      ));
    }
    final group = ExpenseGroup(
      id: id,
      name: name.trim(),
      emoji: emoji.trim(),
      members: localMembers,
      visibility: visibility,
      salarySplitEnabled: salarySplitEnabled,
    );
    groups.insert(
      0,
      group,
    );
    await _persistGroup(group);
    notifyListeners();
    return true;
  }

  Future<bool> updateGroup(String groupId, Map<String, dynamic> input) async {
    if (_apiClient != null && !_offlineFirst) {
      return _sync(() => _apiClient.updateGroup(groupId, input));
    }
    if (!_offlineFirst) return false;
    final group = groupById(groupId);
    final index = groups.indexOf(group);
    groups[index] = ExpenseGroup(
      id: group.id,
      name: input['name'] as String? ?? group.name,
      emoji: input['emoji'] as String? ?? group.emoji,
      visibility: input['visibility'] as String? ?? group.visibility,
      salarySplitEnabled:
          input['salary_split_enabled'] as bool? ?? group.salarySplitEnabled,
      members: group.members,
      expenses: group.expenses,
      settlements: group.settlements,
      paymentRelations: group.paymentRelations,
      balances: group.balances,
    );
    await _persistGroup(groups[index]);
    notifyListeners();
    return true;
  }

  Future<bool> addMember(String groupId, String name, String phone) async {
    if (_apiClient != null && !_offlineFirst) {
      return _sync(
          () => _apiClient.addMember(groupId, name: name, phone: phone));
    }
    if (!_offlineFirst) return false;
    final group = groupById(groupId);
    group.members.add(Member(
      id: _newLocalId('local_member'),
      name: name.trim(),
      phone: phone.trim(),
      accepted: true,
    ));
    await _persistGroup(group);
    notifyListeners();
    return true;
  }

  Future<bool> updateMember(
      String groupId, String memberId, Map<String, dynamic> input) async {
    if (_apiClient != null && !_offlineFirst) {
      return _sync(() => _apiClient.updateMember(groupId, memberId, input));
    }
    if (!_offlineFirst) return false;
    final group = groupById(groupId);
    final index = group.members.indexWhere((member) => member.id == memberId);
    if (index < 0) return false;
    final member = group.members[index];
    group.members[index] = Member(
      id: member.id,
      userId: member.userId,
      name: input['name'] as String? ?? member.name,
      phone: input['phone'] as String? ?? member.phone,
      active: member.active,
      accepted: member.accepted,
      salarySharing: input['salary_sharing'] as bool? ?? member.salarySharing,
    );
    await _persistGroup(group);
    notifyListeners();
    return true;
  }

  Future<void> loadStatus() async {
    final api = _apiClient;
    if (api == null || api.user == null) return;
    final rows = await api.status();
    contactStatus
      ..clear()
      ..addAll(rows.map(ContactStatus.fromJson));
    notifyListeners();
  }

  Future<void> loadInvitations() async {
    final api = _apiClient;
    if (api == null || api.user == null) return;
    invitations
      ..clear()
      ..addAll(await api.invitations());
    notifyListeners();
  }

  Future<bool> respondInvitation(String groupId, bool accept) async {
    final api = _apiClient;
    if (api == null || api.user == null) return false;
    final updated = await _sync(() => api.respondInvitation(groupId, accept));
    if (updated) await loadInvitations();
    return updated;
  }

  Future<bool> addExpense({
    required String groupId,
    required String description,
    required int amountCents,
    required String payerId,
    required List<ExpensePayer> payers,
    required List<String> participantIds,
    String splitMode = 'equal',
    List<ExpenseShare> shares = const [],
    bool splitOverpayment = true,
  }) async {
    if (_apiClient != null && !_offlineFirst) {
      return _sync(
        () => _apiClient.addExpense(
          groupId: groupId,
          description: description,
          amountCents: amountCents,
          payerId: payerId,
          payers: payers,
          participantIds: participantIds,
          splitMode: splitMode,
          shares: shares,
          splitOverpayment: splitOverpayment,
        ),
      );
    }
    groupById(groupId).expenses.insert(
          0,
          Expense(
            id: _offlineFirst
                ? _newLocalId('local_expense')
                : _nextId('expense'),
            description: description.trim(),
            amountCents: amountCents,
            payerId: payerId,
            payers: List.unmodifiable(payers),
            participantIds: List.unmodifiable(participantIds),
            splitMode: splitMode,
            shares: {
              for (final share in shares) share.memberId: share.amountCents
            },
            splitOverpayment: splitOverpayment,
            createdAt: DateTime.now(),
          ),
        );
    await _persistGroup(groupById(groupId));
    notifyListeners();
    return true;
  }

  Future<bool> removeMember(String groupId, String memberId) async {
    if (_apiClient != null && !_offlineFirst) {
      return _sync(() => _apiClient.removeMember(groupId, memberId));
    }
    final group = groupById(groupId);
    final index = group.members.indexWhere((member) => member.id == memberId);
    if (index < 0) return false;
    final removed = group.members[index];
    group.members[index] = Member(
      id: removed.id,
      userId: removed.userId,
      name: removed.name,
      phone: removed.phone,
      active: false,
      salarySharing: removed.salarySharing,
      accepted: removed.accepted,
    );
    await _persistGroup(group);
    notifyListeners();
    return true;
  }

  Future<bool> settleBalance({
    required String groupId,
    required String memberId,
    int? amountCents,
  }) async {
    final group = groupById(groupId);
    if (_apiClient != null && canUseServerFeatures(group)) {
      final settled = await _sync(
        () => _apiClient.settleBalance(
          groupId: groupId,
          memberId: memberId,
          amountCents: amountCents,
        ),
      );
      if (settled) await loadStatus();
      return settled;
    }
    final selfId = _selfMember(group)?.id ?? currentUserId;
    final memberBalance = balances(group)[memberId] ?? 0;
    // The signed-in user settles a bilateral debt: a negative balance means
    // the user owes, and any direction is paid by its absolute value.
    final outstanding = memberBalance < 0 ? -memberBalance : memberBalance;
    final amount = amountCents ?? outstanding;
    if (amount <= 0 || amount > outstanding) return false;
    group.settlements.insert(
      0,
      Settlement(
        id: _offlineFirst
            ? _newLocalId('local_settlement')
            : _nextId('settlement'),
        fromMemberId: memberBalance < 0 ? memberId : selfId,
        toMemberId: memberBalance < 0 ? selfId : memberId,
        amountCents: amount,
        createdAt: DateTime.now(),
      ),
    );
    await _persistGroup(group);
    _refreshLocalStatus();
    notifyListeners();
    return true;
  }

  Future<bool> confirmReceivedPayment({
    required String groupId,
    required String debtorId,
    int? amountCents,
  }) async {
    final group = groupById(groupId);
    if (_apiClient != null && canUseServerFeatures(group)) {
      return _sync(() => _apiClient.confirmReceivedPayment(
            groupId: groupId,
            debtorId: debtorId,
            amountCents: amountCents,
          ));
    }
    final selfId = _selfMember(group)?.id ?? currentUserId;
    final debtorIndex =
        group.members.indexWhere((member) => member.id == debtorId);
    if (debtorIndex < 0) return false;
    final outstanding = balanceWith(
      group,
      group.members[debtorIndex],
    );
    final amount = amountCents ?? outstanding;
    if (outstanding <= 0 || amount <= 0 || amount > outstanding) return false;
    group.settlements.insert(
      0,
      Settlement(
        id: _offlineFirst
            ? _newLocalId('local_settlement')
            : _nextId('settlement'),
        fromMemberId: debtorId,
        toMemberId: selfId,
        amountCents: amount,
        createdAt: DateTime.now(),
      ),
    );
    await _persistGroup(group);
    _refreshLocalStatus();
    notifyListeners();
    return true;
  }

  void _refreshLocalStatus() {
    final combined = <String, ContactStatus>{};
    for (final group in groups) {
      for (final member in group.members) {
        if (member.id == currentUserId || member.userId == currentUserId) {
          continue;
        }
        // ContactStatus is expressed from the signed-in user's perspective:
        // positive means the user owes the contact.
        final amount = -balanceWith(group, member);
        if (amount == 0) continue;
        final previous = combined[member.id];
        combined[member.id] = ContactStatus(
          member: member,
          amountCents: (previous?.amountCents ?? 0) + amount,
        );
      }
    }
    contactStatus
      ..clear()
      ..addAll(combined.values.where((status) => status.amountCents != 0));
  }

  Map<String, int> balances(ExpenseGroup group) {
    if (_apiClient != null && !_offlineFirst) {
      return Map.unmodifiable(group.balances);
    }
    return _localBalances(group);
  }

  Future<bool> requestPayment({
    required String groupId,
    required String debtorId,
    required int amountCents,
  }) {
    final api = _apiClient;
    if (api == null || !canRequestPayment(groupById(groupId))) {
      return Future.value(false);
    }
    return _sync(() => api.requestPayment(
          groupId: groupId,
          debtorId: debtorId,
          amountCents: amountCents,
        ));
  }

  // Positive means the contact owes the signed-in user; negative means the
  // signed-in user owes the contact. Remote relations are server-authoritative.
  int balanceWith(ExpenseGroup group, Member contact) {
    final self = _selfMember(group);
    if (self == null) return 0;
    final selfID = self.id;
    final relations = paymentRelations(group);
    for (final relation in relations) {
      if (relation.fromMemberId == contact.id &&
          relation.toMemberId == selfID) {
        return relation.amountCents;
      }
      if (relation.fromMemberId == selfID &&
          relation.toMemberId == contact.id) {
        return -relation.amountCents;
      }
    }
    return 0;
  }

  List<PaymentRelation> paymentRelations(ExpenseGroup group) =>
      _apiClient != null && !_offlineFirst
          ? group.paymentRelations
          : _localPaymentRelations(group);

  List<PaymentRelation> _localPaymentRelations(ExpenseGroup group) {
    final edges = <String, Map<String, int>>{};
    void add(String from, String to, int amount) {
      if (from == to || amount == 0) return;
      final outgoing = edges.putIfAbsent(from, () => <String, int>{});
      outgoing[to] = (outgoing[to] ?? 0) + amount;
    }

    for (final expense in group.expenses) {
      final payers = expense.payers.isEmpty
          ? [
              ExpensePayer(
                  memberId: expense.payerId, amountCents: expense.amountCents)
            ]
          : expense.payers;
      final credits = <String, int>{
        for (final payer in payers) payer.memberId: payer.amountCents
      };
      for (final share in _localExpenseShares(expense).entries) {
        var owed = share.value;
        for (final payer in payers) {
          final available = credits[payer.memberId] ?? 0;
          final amount = owed < available ? owed : available;
          if (amount > 0) add(share.key, payer.memberId, amount);
          owed -= amount;
          credits[payer.memberId] = available - amount;
          if (owed == 0) break;
        }
      }
    }
    for (final settlement in group.settlements) {
      add(
        settlement.fromMemberId,
        settlement.toMemberId,
        -settlement.amountCents,
      );
    }
    final relations = <PaymentRelation>[];
    final members = group.members
        .where((member) => member.active && member.accepted)
        .toList();
    for (var fromIndex = 0; fromIndex < members.length; fromIndex++) {
      final from = members[fromIndex];
      for (final to in members.skip(fromIndex + 1)) {
        final amount =
            (edges[from.id]?[to.id] ?? 0) - (edges[to.id]?[from.id] ?? 0);
        if (amount > 0) {
          relations.add(PaymentRelation(
            fromMemberId: from.id,
            toMemberId: to.id,
            amountCents: amount,
          ));
        } else if (amount < 0) {
          relations.add(PaymentRelation(
            fromMemberId: to.id,
            toMemberId: from.id,
            amountCents: -amount,
          ));
        }
      }
    }
    return relations;
  }

  Map<String, int> _localBalances(ExpenseGroup group) {
    final result = {for (final member in group.members) member.id: 0};
    for (final expense in group.expenses) {
      final payers = expense.payers.isEmpty
          ? [
              ExpensePayer(
                  memberId: expense.payerId, amountCents: expense.amountCents)
            ]
          : expense.payers;
      for (final payer in payers) {
        result[payer.memberId] =
            (result[payer.memberId] ?? 0) + payer.amountCents;
      }
      final shares = _localExpenseShares(expense);
      for (final entry in shares.entries) {
        final participantId = entry.key;
        final share = entry.value;
        result[participantId] = (result[participantId] ?? 0) - share;
      }
    }
    for (final settlement in group.settlements) {
      result[settlement.fromMemberId] =
          (result[settlement.fromMemberId] ?? 0) + settlement.amountCents;
      result[settlement.toMemberId] =
          (result[settlement.toMemberId] ?? 0) - settlement.amountCents;
    }
    return result;
  }

  int _allocatedExpenseAmount(Expense expense) {
    if (!expense.splitOverpayment) return expense.amountCents;
    final paid = expense.payers.isEmpty
        ? expense.amountCents
        : expense.payers.fold<int>(
            0,
            (sum, payer) => sum + payer.amountCents,
          );
    return paid > expense.amountCents ? paid : expense.amountCents;
  }

  Map<String, int> _localExpenseShares(Expense expense) {
    if (expense.splitMode != 'exact') {
      if (expense.shares.isNotEmpty &&
          (expense.splitMode == 'salary' ||
              expense.consumptionShares.isNotEmpty)) {
        return expense.shares;
      }
      return _equalShares(
        _allocatedExpenseAmount(expense),
        expense.participantIds,
      );
    }

    final consumption = expense.consumptionShares.isNotEmpty
        ? expense.consumptionShares
        : expense.shares;
    final allocated = Map<String, int>.from(consumption);
    final extra = _allocatedExpenseAmount(expense) - expense.amountCents;
    if (extra <= 0) return allocated;

    final eligible = [
      for (final id in expense.participantIds)
        if ((consumption[id] ?? 0) > 0) id,
    ];
    final weight = eligible.fold<int>(
      0,
      (total, id) => total + consumption[id]!,
    );
    if (weight <= 0) {
      return _equalShares(
          _allocatedExpenseAmount(expense), expense.participantIds);
    }

    var used = 0;
    for (final id in eligible) {
      final portion = (BigInt.from(extra) *
              BigInt.from(consumption[id]!) ~/
              BigInt.from(weight))
          .toInt();
      allocated[id] = (allocated[id] ?? 0) + portion;
      used += portion;
    }
    for (final id in eligible) {
      if (used == extra) break;
      allocated[id] = allocated[id]! + 1;
      used++;
    }
    return allocated;
  }

  Map<String, int> _equalShares(int amountCents, List<String> participantIds) {
    if (participantIds.isEmpty) return const {};
    final shares = <String, int>{};
    final baseShare = amountCents ~/ participantIds.length;
    var remainder = amountCents % participantIds.length;
    for (final participantId in participantIds) {
      shares[participantId] = baseShare + (remainder > 0 ? 1 : 0);
      if (remainder > 0) remainder--;
    }
    return shares;
  }

  int currentUserBalance(ExpenseGroup group) {
    final member = _selfMember(group);
    return member == null ? 0 : balances(group)[member.id] ?? 0;
  }

  Member? _selfMember(ExpenseGroup group) {
    for (final member in group.members) {
      if (member.userId == currentUserId || member.id == currentUserId) {
        return member;
      }
    }
    if (_offlineFirst) {
      for (final member in group.members) {
        if (member.id == seedUserId) return member;
      }
      if (group.members.isNotEmpty && group.members.first.userId.isEmpty) {
        return group.members.first;
      }
    }
    return null;
  }

  Future<bool> _sync(Future<void> Function() mutation) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      await mutation();
      if (_offlineFirst) {
        await load();
      } else {
        final loaded = await _apiClient!.listGroups();
        groups
          ..clear()
          ..addAll(loaded);
      }
      return true;
    } on ApiException catch (error) {
      errorMessage = error.code;
      return false;
    } catch (_) {
      errorMessage = 'server_request_failed';
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _persistGroup(ExpenseGroup group) async {
    await _offlineDatabase?.saveGroup(group);
    _serverSyncedGroupIds.remove(group.id);
    if (_offlineFirst && isAuthenticated) {
      unawaited(syncLocalGroups());
    }
  }

  Future<void> refreshAuthentication() async {
    final user = _apiClient?.user;
    if (_offlineFirst && user != null) {
      for (final group in groups) {
        final index = group.members.indexWhere(
          (member) => member.id == seedUserId || member.userId == user.id,
        );
        if (index < 0) continue;
        final existing = group.members[index];
        if (existing.userId == user.id && existing.name == user.name) continue;
        group.members[index] = Member(
          id: existing.id,
          userId: user.id,
          name: user.name,
          phone: user.phone,
          active: existing.active,
          accepted: existing.accepted,
          salarySharing: existing.salarySharing,
        );
        await _persistGroup(group);
      }
    }
    notifyListeners();
  }

  void reportConnectivityError() {
    errorMessage = 'server_unavailable';
    notifyListeners();
  }

  String _newLocalId(String prefix) {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return '${prefix}_${bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join()}_${_sequence++}';
  }

  @override
  void dispose() {
    _apiClient?.close();
    unawaited(_offlineDatabase?.close());
    super.dispose();
  }

  String _nextId(String prefix) => '${prefix}_${_sequence++}';

  static List<ExpenseGroup> _seedGroups() {
    const you = Member(id: seedUserId, name: 'You');
    const ana = Member(id: 'ana', name: 'Ana');
    const diego = Member(id: 'diego', name: 'Diego');
    const sofia = Member(id: 'sofia', name: 'Sofía');
    const marco = Member(id: 'marco', name: 'Marco');
    final now = DateTime.now();

    return [
      ExpenseGroup(
        id: 'cdmx-weekend',
        name: 'Weekend in CDMX',
        emoji: '🌮',
        members: [you, ana, diego, sofia],
        expenses: [
          Expense(
            id: 'expense_tacos',
            description: 'Tacos and drinks',
            amountCents: 128000,
            payerId: seedUserId,
            participantIds: const [seedUserId, 'ana', 'diego', 'sofia'],
            createdAt: now.subtract(const Duration(hours: 3)),
          ),
          Expense(
            id: 'expense_museum',
            description: 'Museum tickets',
            amountCents: 36000,
            payerId: 'ana',
            participantIds: const [seedUserId, 'ana', 'diego'],
            createdAt: now.subtract(const Duration(days: 1)),
          ),
        ],
      ),
      ExpenseGroup(
        id: 'apartment',
        name: 'Apartment',
        emoji: '🏠',
        members: [you, marco],
        expenses: [
          Expense(
            id: 'expense_internet',
            description: 'Internet — September',
            amountCents: 64900,
            payerId: 'marco',
            participantIds: const [seedUserId, 'marco'],
            createdAt: now.subtract(const Duration(days: 4)),
          ),
        ],
      ),
    ];
  }
}
