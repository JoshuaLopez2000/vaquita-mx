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
  bool isLoading = false;
  String? errorMessage;

  bool get isRemote => _apiClient != null;
  ApiClient? get apiClient => _apiClient;

  String get currentUserId => _apiClient?.userId ?? seedUserId;
  Member get currentUser => Member(id: currentUserId, name: 'You');

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
      errorMessage = error.message;
    } catch (_) {
      errorMessage = 'Cannot reach the Vaquita server. Is Docker running?';
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
        emoji: _emojiFor(groups.length),
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
    required List<String> participantIds,
    String splitMode = 'equal',
  }) async {
    if (_apiClient != null) {
      return _sync(
        () => _apiClient.addExpense(
          groupId: groupId,
          description: description,
          amountCents: amountCents,
          payerId: payerId,
          participantIds: participantIds,
          splitMode: splitMode,
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
            participantIds: List.unmodifiable(participantIds),
            createdAt: DateTime.now(),
          ),
        );
    notifyListeners();
    return true;
  }

  Future<bool> removeMember(String groupId, String memberId) async {
    if (_apiClient != null)
      return _sync(() => _apiClient.removeMember(groupId, memberId));
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
      return _sync(
        () => _apiClient.settleBalance(
          groupId: groupId,
          memberId: memberId,
        ),
      );
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
    notifyListeners();
    return true;
  }

  Map<String, int> balances(ExpenseGroup group) {
    final result = {for (final member in group.members) member.id: 0};
    for (final expense in group.expenses) {
      result[expense.payerId] =
          (result[expense.payerId] ?? 0) + expense.amountCents;
      final count = expense.participantIds.length;
      if (count == 0) continue;
      final baseShare = expense.amountCents ~/ count;
      var remainder = expense.amountCents % count;
      for (final participantId in expense.participantIds) {
        final share = baseShare + (remainder > 0 ? 1 : 0);
        if (remainder > 0) remainder--;
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
      errorMessage = error.message;
      return false;
    } catch (_) {
      errorMessage = 'The server request failed. Check Docker and try again.';
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

  static String _emojiFor(int index) {
    const choices = ['🍜', '🏠', '🎁', '🏖️', '🎮', '🚗'];
    return choices[index % choices.length];
  }

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
