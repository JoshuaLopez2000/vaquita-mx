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
}
