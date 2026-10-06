import 'package:vaquita_mx/src/models.dart';

/// Shared client-side rules for every expense split method.
///
/// The server remains authoritative. This helper gives the form immediate,
/// matching feedback while users choose payers and edit a split.
abstract final class ExpenseAllocation {
  /// Returns the amount every split method must allocate, or null when payer
  /// contributions are invalid or do not cover the entered expense total.
  static int? total({
    required int expenseTotalCents,
    required List<ExpensePayer> payers,
  }) {
    if (expenseTotalCents <= 0 || payers.isEmpty) return null;
    var total = 0;
    final ids = <String>{};
    for (final payer in payers) {
      if (payer.memberId.isEmpty ||
          payer.amountCents <= 0 ||
          !ids.add(payer.memberId)) {
        return null;
      }
      total += payer.amountCents;
    }
    return total >= expenseTotalCents ? total : null;
  }

  /// Allocates every centavo deterministically in participant order.
  static List<int> equalShares({
    required int allocationTotalCents,
    required int participantCount,
  }) {
    if (allocationTotalCents <= 0 || participantCount <= 0) return const [];
    final base = allocationTotalCents ~/ participantCount;
    final remainder = allocationTotalCents % participantCount;
    return [
      for (var index = 0; index < participantCount; index++)
        base + (index < remainder ? 1 : 0),
    ];
  }

  static bool exactSharesMatch({
    required int? allocatedCents,
    required int? allocationTotalCents,
  }) =>
      allocatedCents != null && allocatedCents == allocationTotalCents;

  static bool canAllocateExactOverpayment({
    required int expenseTotalCents,
    required List<ExpensePayer> payers,
    required Map<String, int> consumption,
  }) {
    final allocated = total(
      expenseTotalCents: expenseTotalCents,
      payers: payers,
    );
    if (allocated == null ||
        consumption.values.fold(0, (sum, value) => sum + value) !=
            expenseTotalCents) {
      return false;
    }
    if (allocated == expenseTotalCents) {
      return true;
    }
    return consumption.values.any((value) => value > 0);
  }
}
