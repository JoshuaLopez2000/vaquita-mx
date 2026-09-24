class Member {
  const Member({required this.id, required this.name});

  final String id;
  final String name;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

class Expense {
  const Expense({
    required this.id,
    required this.description,
    required this.amountCents,
    required this.payerId,
    required this.participantIds,
    required this.createdAt,
  });

  final String id;
  final String description;
  final int amountCents;
  final String payerId;
  final List<String> participantIds;
  final DateTime createdAt;
}

class Settlement {
  const Settlement({
    required this.id,
    required this.fromMemberId,
    required this.toMemberId,
    required this.amountCents,
    required this.createdAt,
  });

  final String id;
  final String fromMemberId;
  final String toMemberId;
  final int amountCents;
  final DateTime createdAt;
}

class ExpenseGroup {
  ExpenseGroup({
    required this.id,
    required this.name,
    required this.emoji,
    required this.members,
    List<Expense>? expenses,
    List<Settlement>? settlements,
  })  : expenses = expenses ?? [],
        settlements = settlements ?? [];

  final String id;
  final String name;
  final String emoji;
  final List<Member> members;
  final List<Expense> expenses;
  final List<Settlement> settlements;

  int get totalSpentCents => expenses.fold(
        0,
        (total, expense) => total + expense.amountCents,
      );
}

String formatMoney(int cents) {
  final negative = cents < 0;
  final absolute = cents.abs();
  final pesos = absolute ~/ 100;
  final decimal = (absolute % 100).toString().padLeft(2, '0');
  final digits = pesos.toString();
  final groups = <String>[];
  for (var end = digits.length; end > 0; end -= 3) {
    final start = (end - 3).clamp(0, digits.length);
    groups.insert(0, digits.substring(start, end));
  }
  return '${negative ? '-' : ''}\$${groups.join(',')}.$decimal';
}
