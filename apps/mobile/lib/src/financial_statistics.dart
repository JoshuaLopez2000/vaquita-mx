import 'package:vaquita_mx/src/models.dart';

class OverpaymentStatistics {
  const OverpaymentStatistics({
    required this.distributedCents,
    required this.retainedCents,
    required this.retainedByMember,
  });

  final int distributedCents;
  final int retainedCents;
  final Map<String, int> retainedByMember;

  int get totalCents => distributedCents + retainedCents;

  static OverpaymentStatistics forExpenses(
    Iterable<Expense> expenses, {
    required DateTime now,
    required bool thisMonthOnly,
    Set<String> reversedExpenseIds = const {},
  }) {
    var distributedCents = 0;
    var retainedCents = 0;
    final retainedByMember = <String, int>{};
    for (final expense in expenses) {
      if (reversedExpenseIds.contains(expense.id)) {
        continue;
      }
      final created = expense.createdAt.toLocal();
      if (thisMonthOnly &&
          (created.year != now.year || created.month != now.month)) {
        continue;
      }
      if (expense.splitOverpayment) {
        distributedCents += expense.overpaymentCents;
        continue;
      }
      for (final retained in expense.retainedOverpayments) {
        retainedCents += retained.amountCents;
        retainedByMember.update(
          retained.memberId,
          (amount) => amount + retained.amountCents,
          ifAbsent: () => retained.amountCents,
        );
      }
    }
    return OverpaymentStatistics(
      distributedCents: distributedCents,
      retainedCents: retainedCents,
      retainedByMember: retainedByMember,
    );
  }
}
