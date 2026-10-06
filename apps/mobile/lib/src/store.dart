import 'package:flutter/foundation.dart';
import 'package:vaquita_mx/src/api_client.dart';
import 'package:vaquita_mx/src/models.dart';

class DemoStore extends ChangeNotifier {
  DemoStore.seeded()
      : _apiClient = null,
        groups = _seedGroups();

  DemoStore.remote(this._apiClient) : groups = [];

  static const seedUserId = 'me';
  final ApiClient? _apiClient;
  final List<ExpenseGroup> groups;
  final List<AppContact> contacts = [];
  final List<ContactStatus> contactStatus = [];
  final List<GroupInvitation> invitations = [];
  int _sequence = 100;
  int? _requestedTab;
  bool isLoading = false;
  String? errorMessage;

  bool get isRemote => _apiClient != null;
  ApiClient? get apiClient => _apiClient;

  String get currentUserId => _apiClient?.userId ?? seedUserId;
  AppUser? get authenticatedUser => _apiClient?.user;
  Member get currentUser => Member(id: currentUserId, name: 'You');

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
    if (_apiClient == null) return;
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final loaded = await _apiClient.listGroups();
      groups
        ..clear()
        ..addAll(loaded);
    } on ApiException catch (error) {
      errorMessage = error.code;
    } catch (_) {
      errorMessage = 'server_unavailable';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> findContacts(List<String> phones) async {
    if (_apiClient == null) return;
    contacts
      ..clear()
      ..addAll(await _apiClient.matchContacts(phones));
    notifyListeners();
  }

  Future<void> loadContacts() async {
    if (_apiClient == null) return;
    contacts
      ..clear()
      ..addAll(await _apiClient.listContacts());
    notifyListeners();
  }

  Future<bool> saveContact(String name, String phone) async {
    return saveContacts([AppContact(id: '', name: name, phone: phone)]);
  }

  Future<bool> saveContacts(List<AppContact> newContacts) async {
    if (_apiClient == null) {
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
    if (_apiClient == null) {
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
    if (_apiClient != null) {
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
    final id = _nextId('group');
    final localMembers = <Member>[currentUser];
    for (final rawName in memberNames) {
      final trimmed = rawName.trim();
      if (trimmed.isEmpty || trimmed.toLowerCase() == 'you') continue;
      localMembers.add(Member(id: _nextId('member'), name: trimmed));
    }
    groups.insert(
      0,
      ExpenseGroup(
        id: id,
        name: name.trim(),
        emoji: emoji.trim(),
        members: localMembers,
      ),
    );
    notifyListeners();
    return true;
  }

  Future<bool> updateGroup(String groupId, Map<String, dynamic> input) =>
      _apiClient != null
          ? _sync(() => _apiClient.updateGroup(groupId, input))
          : Future.value(false);
  Future<bool> addMember(String groupId, String name, String phone) =>
      _apiClient != null
          ? _sync(() => _apiClient.addMember(groupId, name: name, phone: phone))
          : Future.value(false);
  Future<bool> updateMember(
          String groupId, String memberId, Map<String, dynamic> input) =>
      _apiClient != null
          ? _sync(() => _apiClient.updateMember(groupId, memberId, input))
          : Future.value(false);

  Future<void> loadStatus() async {
    if (_apiClient == null) return;
    final rows = await _apiClient.status();
    contactStatus
      ..clear()
      ..addAll(rows.map(ContactStatus.fromJson));
    notifyListeners();
  }

  Future<void> loadInvitations() async {
    if (_apiClient == null) return;
    invitations
      ..clear()
      ..addAll(await _apiClient.invitations());
    notifyListeners();
  }

  Future<bool> respondInvitation(String groupId, bool accept) async {
    if (_apiClient == null) return false;
    final updated =
        await _sync(() => _apiClient.respondInvitation(groupId, accept));
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
  }) async {
    if (_apiClient != null) {
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
        ),
      );
    }
    groupById(groupId).expenses.insert(
          0,
          Expense(
            id: _nextId('expense'),
            description: description.trim(),
            amountCents: amountCents,
            payerId: payerId,
            payers: List.unmodifiable(payers),
            participantIds: List.unmodifiable(participantIds),
            splitMode: splitMode,
            shares: {for (final share in shares) share.memberId: share.amountCents},
            createdAt: DateTime.now(),
          ),
        );
    notifyListeners();
    return true;
  }

  Future<bool> removeMember(String groupId, String memberId) async {
    if (_apiClient != null) {
      return _sync(() => _apiClient.removeMember(groupId, memberId));
    }
    final group = groupById(groupId);
    final index = group.members.indexWhere((member) => member.id == memberId);
    if (index < 0) return false;
    group.members[index] = Member(
        id: group.members[index].id,
        name: group.members[index].name,
        active: false);
    notifyListeners();
    return true;
  }

  Future<bool> settleBalance({
    required String groupId,
    required String memberId,
  }) async {
    if (_apiClient != null) {
      final settled = await _sync(
        () => _apiClient.settleBalance(
          groupId: groupId,
          memberId: memberId,
        ),
      );
      if (settled) await loadStatus();
      return settled;
    }
    final group = groupById(groupId);
    final memberBalance = balances(group)[memberId] ?? 0;
    if (memberBalance == 0) return false;
    group.settlements.insert(
      0,
      Settlement(
        id: _nextId('settlement'),
        fromMemberId: memberBalance < 0 ? memberId : currentUserId,
        toMemberId: memberBalance < 0 ? currentUserId : memberId,
        amountCents: memberBalance.abs(),
        createdAt: DateTime.now(),
      ),
    );
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
    if (_apiClient != null) return Map.unmodifiable(group.balances);
    return _localBalances(group);
  }

  Future<bool> requestPayment({
    required String groupId,
    required String debtorId,
    required int amountCents,
  }) {
    if (_apiClient == null) return Future.value(false);
    return _sync(() => _apiClient.requestPayment(
          groupId: groupId,
          debtorId: debtorId,
          amountCents: amountCents,
        ));
  }

  // Positive means the contact owes the signed-in user; negative means the
  // signed-in user owes the contact. Remote relations are server-authoritative.
  int balanceWith(ExpenseGroup group, Member contact) {
    final self = group.members.where(
      (member) => member.userId == currentUserId || member.id == currentUserId,
    );
    if (self.isEmpty) return 0;
    final selfID = self.first.id;
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
      _apiClient != null
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
      for (final share in _equalShares(
        _allocatedExpenseAmount(expense),
        expense.participantIds,
      ).entries) {
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
      final shares = _equalShares(
        _allocatedExpenseAmount(expense),
        expense.participantIds,
      );
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
    final paid = expense.payers.isEmpty
        ? expense.amountCents
        : expense.payers.fold<int>(
            0,
            (sum, payer) => sum + payer.amountCents,
          );
    return paid > expense.amountCents ? paid : expense.amountCents;
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
    final member = group.members
        .where((member) =>
            member.userId == currentUserId || member.id == currentUserId)
        .toList();
    return member.isEmpty ? 0 : balances(group)[member.first.id] ?? 0;
  }

  Future<bool> _sync(Future<void> Function() mutation) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      await mutation();
      final loaded = await _apiClient!.listGroups();
      groups
        ..clear()
        ..addAll(loaded);
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

  @override
  void dispose() {
    _apiClient?.close();
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
