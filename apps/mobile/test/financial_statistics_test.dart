import 'package:flutter_test/flutter_test.dart';
import 'package:vaquita_mx/src/financial_statistics.dart';
import 'package:vaquita_mx/src/models.dart';

void main() {
  test('reports zero for expenses without retained or distributed excess', () {
    final statistics = OverpaymentStatistics.forExpenses(
      const [],
      now: DateTime(2026, 10, 6),
      thisMonthOnly: false,
    );

    expect(statistics.totalCents, 0);
    expect(statistics.retainedByMember, isEmpty);
  });

  test('attributes a single payer retained excess', () {
    final statistics = OverpaymentStatistics.forExpenses(
      [
        Expense(
          id: 'retained',
          description: 'Coffee',
          amountCents: 10000,
          payerId: 'ana',
          participantIds: const ['ana'],
          createdAt: DateTime(2026, 10, 3),
          splitOverpayment: false,
          retainedOverpayments: const [
            ExpensePayer(memberId: 'ana', amountCents: 500),
          ],
        ),
      ],
      now: DateTime(2026, 10, 6),
      thisMonthOnly: false,
    );

    expect(statistics.retainedCents, 500);
    expect(statistics.retainedByMember, {'ana': 500});
  });

  test('separates distributed and retained overpayments by period and payer',
      () {
    final statistics = OverpaymentStatistics.forExpenses(
      [
        Expense(
          id: 'distributed',
          description: 'Dinner',
          amountCents: 10000,
          payerId: 'ana',
          participantIds: const ['ana'],
          createdAt: DateTime(2026, 10, 2),
          paidAmountCents: 11000,
          overpaymentCents: 1000,
          splitOverpayment: true,
        ),
        Expense(
          id: 'retained',
          description: 'Coffee',
          amountCents: 10000,
          payerId: 'ana',
          participantIds: const ['ana', 'diego'],
          createdAt: DateTime(2026, 10, 3),
          paidAmountCents: 11000,
          overpaymentCents: 1000,
          splitOverpayment: false,
          retainedOverpayments: const [
            ExpensePayer(memberId: 'ana', amountCents: 600),
            ExpensePayer(memberId: 'diego', amountCents: 400),
          ],
        ),
        Expense(
          id: 'older',
          description: 'Older',
          amountCents: 10000,
          payerId: 'ana',
          participantIds: const ['ana'],
          createdAt: DateTime(2026, 9, 30),
          paidAmountCents: 10500,
          overpaymentCents: 500,
          splitOverpayment: false,
          retainedOverpayments: const [
            ExpensePayer(memberId: 'ana', amountCents: 500),
          ],
        ),
      ],
      now: DateTime(2026, 10, 6),
      thisMonthOnly: true,
    );

    expect(statistics.distributedCents, 1000);
    expect(statistics.retainedCents, 1000);
    expect(statistics.retainedByMember, {'ana': 600, 'diego': 400});
    expect(statistics.totalCents, 2000);
  });
}
