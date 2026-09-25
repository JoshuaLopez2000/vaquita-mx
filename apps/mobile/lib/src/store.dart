import 'package:flutter/foundation.dart';
import 'package:vaquita_mx/src/api_client.dart';
import 'package:vaquita_mx/src/models.dart';

class DemoStore extends ChangeNotifier {
  DemoStore.seeded()
      : _apiClient = null,
        groups = _seedGroups();

  DemoStore.remote(this._apiClient) : groups = [];

  static const currentUserId = 'me';
  final ApiClient? _apiClient;
  final List<ExpenseGroup> groups;
  final List<AppContact> contacts = [];
  int _sequence = 100;
  bool isLoading = false;
  String? errorMessage;

  bool get isRemote => _apiClient != null;
  ApiClient? get apiClient => _apiClient;

  Member get currentUser => const Member(id: currentUserId, name: 'You');

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
  }) async {
    if (_apiClient != null) {
      return _sync(
        () => _apiClient.createGroup(name: name, memberNames: memberNames),
      );
    }
    final id = _nextId('group');
    final members = <Member>[currentUser];
    for (final rawName in memberNames) {
      final trimmed = rawName.trim();
      if (trimmed.isEmpty || trimmed.toLowerCase() == 'you') continue;
      members.add(Member(id: _nextId('member'), name: trimmed));
    }
    groups.insert(
      0,
      ExpenseGroup(
        id: id,
        name: name.trim(),
        emoji: _emojiFor(groups.length),
        members: members,
      ),
    );
    notifyListeners();
    return true;
  }

  Future<bool> addExpense({
    required String groupId,
    required String description,
    required int amountCents,
    required String payerId,
    required List<String> participantIds,
  }) async {
    if (_apiClient != null) {
      return _sync(
        () => _apiClient.addExpense(
          groupId: groupId,
          description: description,
          amountCents: amountCents,
          payerId: payerId,
          participantIds: participantIds,
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

  int currentUserBalance(ExpenseGroup group) =>
      balances(group)[currentUserId] ?? 0;

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
    const you = Member(id: currentUserId, name: 'You');
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
            payerId: currentUserId,
            participantIds: const [currentUserId, 'ana', 'diego', 'sofia'],
            createdAt: now.subtract(const Duration(hours: 3)),
          ),
          Expense(
            id: 'expense_museum',
            description: 'Museum tickets',
            amountCents: 36000,
            payerId: 'ana',
            participantIds: const [currentUserId, 'ana', 'diego'],
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
            participantIds: const [currentUserId, 'marco'],
            createdAt: now.subtract(const Duration(days: 4)),
          ),
        ],
      ),
    ];
  }
}
