class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.salaryCents,
  });

  final String id;
  final String name;
  final String email;
  final String phone;
  final int salaryCents;

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        name: json['name'] as String,
        email: json['email'] as String,
        phone: json['phone'] as String? ?? '',
        salaryCents: json['salary_cents'] as int? ?? 0,
      );
}

class Member {
  const Member(
      {required this.id,
      required this.name,
      this.userId = '',
      this.phone = '',
      this.active = true,
      this.salarySharing = false,
      this.accepted = true});

  final String id;
  final String userId;
  final String name;
  final String phone;
  final bool active;
  final bool salarySharing;
  final bool accepted;

  factory Member.fromJson(Map<String, dynamic> json) => Member(
        id: json['id'] as String,
        userId: json['user_id'] as String? ?? '',
        name: json['name'] as String,
        phone: json['phone'] as String? ?? '',
        active: json['active'] as bool? ?? true,
        salarySharing: json['salary_sharing'] as bool? ?? false,
        accepted: json['accepted'] as bool? ?? true,
      );

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

class AppContact {
  const AppContact({required this.id, required this.name, required this.phone});
  final String id;
  final String name;
  final String phone;
  factory AppContact.fromJson(Map<String, dynamic> json) => AppContact(
      id: json['id'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String);
}

class ContactStatus {
  const ContactStatus({required this.member, required this.amountCents});
  final Member member;
  final int amountCents;
  factory ContactStatus.fromJson(Map<String, dynamic> json) => ContactStatus(
      member: Member.fromJson(json['member'] as Map<String, dynamic>),
      amountCents: json['amount_cents'] as int);
}

class GroupInvitation {
  const GroupInvitation({required this.group, required this.member});
  final ExpenseGroup group;
  final Member member;
  factory GroupInvitation.fromJson(Map<String, dynamic> json) =>
      GroupInvitation(
          group: ExpenseGroup.fromJson(json['group'] as Map<String, dynamic>),
          member: Member.fromJson(json['member'] as Map<String, dynamic>));
}

class Expense {
  const Expense({
    required this.id,
    required this.description,
    required this.amountCents,
    required this.payerId,
    required this.participantIds,
    required this.createdAt,
    this.splitMode = 'equal',
    this.shares = const {},
  });

  final String id;
  final String description;
  final int amountCents;
  final String payerId;
  final List<String> participantIds;
  final DateTime createdAt;
  final String splitMode;
  final Map<String, int> shares;

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
        id: json['id'] as String,
        description: json['description'] as String,
        amountCents: json['amount_cents'] as int,
        payerId: json['payer_id'] as String,
        participantIds:
            (json['participant_ids'] as List<dynamic>).cast<String>(),
        createdAt: DateTime.parse(json['created_at'] as String),
        splitMode: json['split_mode'] as String? ?? 'equal',
        shares: ((json['shares'] as Map<String, dynamic>?) ?? const {})
            .map((key, value) => MapEntry(key, value as int)),
      );
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

  factory Settlement.fromJson(Map<String, dynamic> json) => Settlement(
        id: json['id'] as String,
        fromMemberId: json['from_member_id'] as String,
        toMemberId: json['to_member_id'] as String,
        amountCents: json['amount_cents'] as int,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class PaymentRelation {
  const PaymentRelation({
    required this.fromMemberId,
    required this.toMemberId,
    required this.amountCents,
  });

  final String fromMemberId;
  final String toMemberId;
  final int amountCents;

  factory PaymentRelation.fromJson(Map<String, dynamic> json) =>
      PaymentRelation(
        fromMemberId: json['from_member_id'] as String,
        toMemberId: json['to_member_id'] as String,
        amountCents: json['amount_cents'] as int,
      );
}

class ExpenseGroup {
  ExpenseGroup({
    required this.id,
    required this.name,
    required this.emoji,
    required this.members,
    this.visibility = 'personal',
    this.salarySplitEnabled = false,
    this.salarySplitAvailable = false,
    Map<String, int>? balances,
    List<Expense>? expenses,
    List<Settlement>? settlements,
    List<PaymentRelation>? paymentRelations,
  })  : expenses = expenses ?? [],
        settlements = settlements ?? [],
        paymentRelations = paymentRelations ?? [],
        balances = balances ?? {};

  final String id;
  final String name;
  final String emoji;
  final List<Member> members;
  final String visibility;
  final bool salarySplitEnabled;
  final bool salarySplitAvailable;
  final List<Expense> expenses;
  final List<Settlement> settlements;
  final List<PaymentRelation> paymentRelations;
  final Map<String, int> balances;

  factory ExpenseGroup.fromJson(Map<String, dynamic> json) => ExpenseGroup(
        id: json['id'] as String,
        name: json['name'] as String,
        emoji: json['emoji'] as String,
        visibility: json['visibility'] as String? ?? 'personal',
        salarySplitEnabled: json['salary_split_enabled'] as bool? ?? false,
        salarySplitAvailable: json['salary_split_available'] as bool? ?? false,
        balances: ((json['balances'] as Map<String, dynamic>?) ?? const {})
            .map((key, value) => MapEntry(key, value as int)),
        members: ((json['members'] as List<dynamic>?) ?? const [])
            .map((value) => Member.fromJson(value as Map<String, dynamic>))
            .toList(),
        expenses: ((json['expenses'] as List<dynamic>?) ?? const [])
            .map((value) => Expense.fromJson(value as Map<String, dynamic>))
            .toList(),
        settlements: ((json['settlements'] as List<dynamic>?) ?? const [])
            .map((value) => Settlement.fromJson(value as Map<String, dynamic>))
            .toList(),
        paymentRelations:
            ((json['payment_relations'] as List<dynamic>?) ?? const [])
                .map((value) =>
                    PaymentRelation.fromJson(value as Map<String, dynamic>))
                .toList(),
      );

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
