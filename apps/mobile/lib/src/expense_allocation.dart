import 'package:vaquita_mx/src/models.dart';

/// Shared client-side rules for every expense split method.
///
/// The server remains authoritative. This helper gives the form immediate,
/// matching feedback while users choose payers and edit a split, and keeps
/// offline/local ledger math identical to the server.
abstract final class ExpenseAllocation {
  /// 100.00% expressed in integer basis points (0.01% precision).
  static const percentageTotalBps = 10000;

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

  /// Parses a fixed-point percentage with up to two decimal places into
  /// integer basis points (100 bps = 1.00%, max 10000 bps = 100.00%).
  /// Never uses floating-point arithmetic.
  static int? parsePercentageBps(String input, {bool allowZero = false}) {
    final normalized = input.replaceAll(',', '').trim();
    final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(normalized);
    if (match == null) return null;
    final whole = int.tryParse(match.group(1)!);
    final fractional = int.tryParse((match.group(2) ?? '').padRight(2, '0'));
    if (whole == null || fractional == null || whole > 100) return null;
    final bps = whole * 100 + fractional;
    if (bps > percentageTotalBps) return null;
    if (bps == 0) return allowZero ? 0 : null;
    return bps > 0 ? bps : null;
  }

  /// Formats integer basis points as a fixed two-decimal percentage string
  /// (for example, 3334 -> "33.34", 5000 -> "50.00").
  static String formatPercentageBps(int bps) {
    final sign = bps < 0 ? '-' : '';
    final absolute = bps.abs();
    return '$sign${absolute ~/ 100}.${(absolute % 100).toString().padLeft(2, '0')}';
  }

  /// Splits 10000 basis points deterministically across participants in order.
  static List<int> equalPercentageBps(int participantCount) {
    if (participantCount <= 0 || participantCount > percentageTotalBps) {
      return const [];
    }
    final base = percentageTotalBps ~/ participantCount;
    final remainder = percentageTotalBps % participantCount;
    return [
      for (var index = 0; index < participantCount; index++)
        base + (index < remainder ? 1 : 0),
    ];
  }

  /// Allocates [allocationTotalCents] using fixed-point integer basis points.
  ///
  /// Each participant receives `floor(total * bps / 10000)` and leftover
  /// centavos are assigned one per participant ordered by largest exact
  /// remainder `(total * bps) % 10000` descending, breaking ties by stored
  /// [participantIds] order ascending. Matches the Go server implementation.
  static Map<String, int>? percentageShares({
    required int allocationTotalCents,
    required List<String> participantIds,
    required Map<String, int> percentagesBps,
  }) {
    if (allocationTotalCents <= 0 ||
        participantIds.isEmpty ||
        percentagesBps.length != participantIds.length) {
      return null;
    }
    final seen = <String>{};
    var totalBps = 0;
    for (final id in participantIds) {
      if (id.isEmpty || !seen.add(id)) return null;
      final bps = percentagesBps[id];
      if (bps == null || bps <= 0 || bps > percentageTotalBps) return null;
      totalBps += bps;
    }
    if (totalBps != percentageTotalBps) return null;

    final denom = BigInt.from(percentageTotalBps);
    final totalBig = BigInt.from(allocationTotalCents);
    final shares = <String, int>{};
    final ranks = <({int index, String memberId, int remainder})>[];
    var used = 0;

    for (var index = 0; index < participantIds.length; index++) {
      final id = participantIds[index];
      final product = totalBig * BigInt.from(percentagesBps[id]!);
      final quotient = (product ~/ denom).toInt();
      final remainder = (product % denom).toInt();
      shares[id] = quotient;
      used += quotient;
      ranks.add((index: index, memberId: id, remainder: remainder));
    }

    final leftover = allocationTotalCents - used;
    if (leftover < 0 || leftover > participantIds.length) return null;
    if (leftover > 0) {
      ranks.sort((a, b) {
        final byRemainder = b.remainder.compareTo(a.remainder);
        return byRemainder != 0 ? byRemainder : a.index.compareTo(b.index);
      });
      for (var i = 0; i < leftover; i++) {
        final id = ranks[i].memberId;
        shares[id] = shares[id]! + 1;
      }
    }
    return shares;
  }

  /// Computes final immutable centavo shares for a percentage expense,
  /// allocating any split overpayment separately with the same weights so
  /// every participant's overpayment share is non-negative.
  static Map<String, int>? percentageFinalShares({
    required int amountCents,
    required int paidAmountCents,
    required bool splitOverpayment,
    required List<String> participantIds,
    required Map<String, int> percentagesBps,
  }) {
    if (amountCents <= 0 || paidAmountCents < amountCents) return null;
    final consumption = percentageShares(
      allocationTotalCents: amountCents,
      participantIds: participantIds,
      percentagesBps: percentagesBps,
    );
    if (consumption == null) return null;
    if (!splitOverpayment || paidAmountCents == amountCents) {
      return consumption;
    }
    final extra = percentageShares(
      allocationTotalCents: paidAmountCents - amountCents,
      participantIds: participantIds,
      percentagesBps: percentagesBps,
    );
    if (extra == null) return null;
    return {
      for (final id in participantIds) id: consumption[id]! + extra[id]!,
    };
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
