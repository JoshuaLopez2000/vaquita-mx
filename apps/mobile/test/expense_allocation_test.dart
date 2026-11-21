import 'package:flutter_test/flutter_test.dart';
import 'package:vaquita_mx/src/expense_allocation.dart';
import 'package:vaquita_mx/src/models.dart';

void main() {
  test('uses every payer centavo as the allocation total', () {
    const payers = [
      ExpensePayer(memberId: 'ana', amountCents: 7000),
      ExpensePayer(memberId: 'diego', amountCents: 8000),
    ];

    final total = ExpenseAllocation.total(
      expenseTotalCents: 10000,
      payers: payers,
    );

    expect(total, 15000);
    expect(
      ExpenseAllocation.equalShares(
        allocationTotalCents: total!,
        participantCount: 4,
      ),
      [3750, 3750, 3750, 3750],
    );
    expect(
      ExpenseAllocation.exactSharesMatch(
        allocatedCents: 15000,
        allocationTotalCents: total,
      ),
      isTrue,
    );
  });

  test('rejects payer totals below the entered expense total', () {
    expect(
      ExpenseAllocation.total(
        expenseTotalCents: 10000,
        payers: const [ExpensePayer(memberId: 'ana', amountCents: 9999)],
      ),
      isNull,
    );
  });

  group('percentage splitting', () {
    test('parses fixed-point percentages into basis points without floats', () {
      expect(ExpenseAllocation.parsePercentageBps('50'), 5000);
      expect(ExpenseAllocation.parsePercentageBps('33.34'), 3334);
      expect(ExpenseAllocation.parsePercentageBps('0.01'), 1);
      expect(ExpenseAllocation.parsePercentageBps('100'), 10000);
      expect(ExpenseAllocation.parsePercentageBps('100.00'), 10000);
      expect(ExpenseAllocation.parsePercentageBps('12.5'), 1250);
      expect(ExpenseAllocation.parsePercentageBps('0'), isNull);
      expect(ExpenseAllocation.parsePercentageBps('0', allowZero: true), 0);
      expect(ExpenseAllocation.parsePercentageBps('100.01'), isNull);
      expect(ExpenseAllocation.parsePercentageBps('33.333'), isNull);
      expect(ExpenseAllocation.parsePercentageBps('-10'), isNull);
      expect(ExpenseAllocation.parsePercentageBps('abc'), isNull);
    });

    test(
        'allocates repeating fractions, ties, and one-cent totals deterministically',
        () {
      expect(
        ExpenseAllocation.percentageShares(
          allocationTotalCents: 10000,
          participantIds: const ['ana', 'beto', 'carla'],
          percentagesBps: const {'ana': 5000, 'beto': 3000, 'carla': 2000},
        ),
        const {'ana': 5000, 'beto': 3000, 'carla': 2000},
      );

      // Repeating thirds: largest percentage gets the extra centavo regardless of position.
      expect(
        ExpenseAllocation.percentageShares(
          allocationTotalCents: 100,
          participantIds: const ['ana', 'beto', 'carla'],
          percentagesBps: const {'ana': 3333, 'beto': 3333, 'carla': 3334},
        ),
        const {'ana': 33, 'beto': 33, 'carla': 34},
      );

      // One-cent total goes to largest percentage.
      expect(
        ExpenseAllocation.percentageShares(
          allocationTotalCents: 1,
          participantIds: const ['ana', 'beto'],
          percentagesBps: const {'ana': 1000, 'beto': 9000},
        ),
        const {'ana': 0, 'beto': 1},
      );

      // Equal-remainder tie breaks by stored participant order.
      expect(
        ExpenseAllocation.percentageShares(
          allocationTotalCents: 1,
          participantIds: const ['ana', 'beto'],
          percentagesBps: const {'ana': 5000, 'beto': 5000},
        ),
        const {'ana': 1, 'beto': 0},
      );
      expect(
        ExpenseAllocation.percentageShares(
          allocationTotalCents: 1,
          participantIds: const ['beto', 'ana'],
          percentagesBps: const {'ana': 5000, 'beto': 5000},
        ),
        const {'beto': 1, 'ana': 0},
      );

      // Four-way tie on 5 centavos breaks in stored participant order.
      expect(
        ExpenseAllocation.percentageShares(
          allocationTotalCents: 5,
          participantIds: const ['d', 'b', 'a', 'c'],
          percentagesBps: const {'d': 2500, 'b': 2500, 'a': 2500, 'c': 2500},
        ),
        const {'d': 2, 'b': 1, 'a': 1, 'c': 1},
      );
    });

    test('rejects invalid percentage totals, zero values, and duplicates', () {
      expect(
        ExpenseAllocation.percentageShares(
          allocationTotalCents: 1000,
          participantIds: const ['ana', 'beto'],
          percentagesBps: const {'ana': 5000, 'beto': 4999},
        ),
        isNull,
      );
      expect(
        ExpenseAllocation.percentageShares(
          allocationTotalCents: 1000,
          participantIds: const ['ana', 'beto'],
          percentagesBps: const {'ana': 10000, 'beto': 0},
        ),
        isNull,
      );
      expect(
        ExpenseAllocation.percentageShares(
          allocationTotalCents: 1000,
          participantIds: const ['ana', 'ana'],
          percentagesBps: const {'ana': 10000},
        ),
        isNull,
      );
    });

    test('allocates split overpayment separately so shares never shrink', () {
      final consumption = ExpenseAllocation.percentageShares(
        allocationTotalCents: 3,
        participantIds: const ['a', 'b', 'c'],
        percentagesBps: const {'a': 4400, 'b': 4400, 'c': 1200},
      )!;
      final withTip = ExpenseAllocation.percentageFinalShares(
        amountCents: 3,
        paidAmountCents: 4,
        splitOverpayment: true,
        participantIds: const ['a', 'b', 'c'],
        percentagesBps: const {'a': 4400, 'b': 4400, 'c': 1200},
      )!;
      expect(withTip.values.reduce((a, b) => a + b), 4);
      for (final id in const ['a', 'b', 'c']) {
        expect(withTip[id]!, greaterThanOrEqualTo(consumption[id]!));
      }

      final retained = ExpenseAllocation.percentageFinalShares(
        amountCents: 3,
        paidAmountCents: 4,
        splitOverpayment: false,
        participantIds: const ['a', 'b', 'c'],
        percentagesBps: const {'a': 4400, 'b': 4400, 'c': 1200},
      )!;
      expect(retained, consumption);
    });
  });
}
