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

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'phone': phone,
        'salary_cents': salaryCents,
      };
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'name': name,
        'phone': phone,
        'active': active,
        'salary_sharing': salarySharing,
        'accepted': accepted,
      };

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
    this.payers = const [],
    required this.participantIds,
    required this.createdAt,
    this.splitMode = 'equal',
    this.shares = const {},
    this.paidAmountCents = 0,
    this.consumptionShares = const {},
    this.overpaymentCents = 0,
    this.overpaymentShares = const {},
    this.splitOverpayment = true,
    this.retainedOverpayments = const [],
  });

  final String id;
  final String description;
  final int amountCents;
  final String payerId;
  final List<ExpensePayer> payers;
  final List<String> participantIds;
  final DateTime createdAt;
  final String splitMode;
  final Map<String, int> shares;
  final int paidAmountCents;
  final Map<String, int> consumptionShares;
  final int overpaymentCents;
  final Map<String, int> overpaymentShares;
  final bool splitOverpayment;
  final List<ExpensePayer> retainedOverpayments;

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
        id: json['id'] as String,
        description: json['description'] as String,
        amountCents: json['amount_cents'] as int,
        payerId: json['payer_id'] as String,
        payers: ((json['payers'] as List<dynamic>?) ?? const [])
            .map(
                (value) => ExpensePayer.fromJson(value as Map<String, dynamic>))
            .toList(),
        participantIds:
            (json['participant_ids'] as List<dynamic>).cast<String>(),
        createdAt: DateTime.parse(json['created_at'] as String),
        splitMode: json['split_mode'] as String? ?? 'equal',
        shares: ((json['shares'] as Map<String, dynamic>?) ?? const {})
            .map((key, value) => MapEntry(key, value as int)),
        paidAmountCents: json['paid_amount_cents'] as int? ?? 0,
        consumptionShares:
            ((json['consumption_shares'] as Map<String, dynamic>?) ?? const {})
                .map((key, value) => MapEntry(key, value as int)),
        overpaymentCents: json['overpayment_cents'] as int? ?? 0,
        overpaymentShares:
            ((json['overpayment_shares'] as Map<String, dynamic>?) ?? const {})
                .map((key, value) => MapEntry(key, value as int)),
        splitOverpayment: json['split_overpayment'] as bool? ?? true,
        retainedOverpayments:
            ((json['retained_overpayments'] as List<dynamic>?) ?? const [])
                .map((value) =>
                    ExpensePayer.fromJson(value as Map<String, dynamic>))
                .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'description': description,
        'amount_cents': amountCents,
        'payer_id': payerId,
        'payers': payers.map((payer) => payer.toJson()).toList(),
        'participant_ids': participantIds,
        'created_at': createdAt.toIso8601String(),
        'split_mode': splitMode,
        'shares': shares,
        'paid_amount_cents': paidAmountCents,
        'consumption_shares': consumptionShares,
        'overpayment_cents': overpaymentCents,
        'overpayment_shares': overpaymentShares,
        'split_overpayment': splitOverpayment,
        'retained_overpayments':
            retainedOverpayments.map((payer) => payer.toJson()).toList(),
      };
}

class ExpensePayer {
  const ExpensePayer({required this.memberId, required this.amountCents});

  final String memberId;
  final int amountCents;

  factory ExpensePayer.fromJson(Map<String, dynamic> json) => ExpensePayer(
        memberId: json['member_id'] as String,
        amountCents: json['amount_cents'] as int,
      );

  Map<String, dynamic> toJson() => {
        'member_id': memberId,
        'amount_cents': amountCents,
      };
}

class ExpenseShare {
  const ExpenseShare({required this.memberId, required this.amountCents});

  final String memberId;
  final int amountCents;
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'from_member_id': fromMemberId,
        'to_member_id': toMemberId,
        'amount_cents': amountCents,
        'created_at': createdAt.toIso8601String(),
      };
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'visibility': visibility,
        'salary_split_enabled': salarySplitEnabled,
        'salary_split_available': salarySplitAvailable,
        'members': members.map((member) => member.toJson()).toList(),
        'expenses': expenses.map((expense) => expense.toJson()).toList(),
        'settlements':
            settlements.map((settlement) => settlement.toJson()).toList(),
        'balances': balances,
        'payment_relations': paymentRelations
            .map((relation) => {
                  'from_member_id': relation.fromMemberId,
                  'to_member_id': relation.toMemberId,
                  'amount_cents': relation.amountCents,
                })
            .toList(),
      };

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
