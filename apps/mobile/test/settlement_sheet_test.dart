import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaquita_mx/src/app.dart';
import 'package:vaquita_mx/src/store.dart';

void main() {
  // The Apartment seed leaves the signed-in user owing Marco $324.50
  // (32,450 centavos), so the settlement sheet runs in the debtor flow.
  Future<void> openMarcoSettlementSheet(WidgetTester tester, DemoStore store) async {
    await tester.pumpWidget(VaquitaApp(store: store));
    await tester.tap(find.text('Apartment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pagar'));
    await tester.pumpAndSettle();
    // The settle button may sit below the fold inside the scrollable sheet.
    await tester.ensureVisible(find.byKey(const Key('settle-marco')));
    await tester.pumpAndSettle();
  }

  testWidgets('prefills the outstanding balance and records a partial settlement', (tester) async {
    final store = DemoStore.seeded();
    await openMarcoSettlementSheet(tester, store);

    expect(find.byKey(const Key('settlement-amount')), findsOneWidget);
    final controller = tester.widget<TextField>(find.byKey(const Key('settlement-amount'))).controller!;
    expect(controller.text, '324.50');

    await tester.enterText(find.byKey(const Key('settlement-amount')), '100');
    await tester.tap(find.byKey(const Key('settle-marco')));
    await tester.pumpAndSettle();

    final group = store.groupById('apartment');
    expect(group.settlements, hasLength(1));
    expect(group.settlements.first.amountCents, 10000);
    final balances = store.balances(group);
    // Marco remains the creditor for the unpaid 224.50 remainder.
    expect(balances['marco'], 22450);
    expect(balances['me'], -22450);
  });

  testWidgets('rejects an amount above the outstanding balance', (tester) async {
    final store = DemoStore.seeded();
    await openMarcoSettlementSheet(tester, store);

    await tester.enterText(find.byKey(const Key('settlement-amount')), '500');
    await tester.ensureVisible(find.byKey(const Key('settle-marco')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settle-marco')));
    await tester.pumpAndSettle();

    expect(find.text('Introduce un monto hasta el saldo pendiente.'), findsOneWidget);
    expect(store.groupById('apartment').settlements, isEmpty);
  });

  testWidgets('settle everything fills the full outstanding amount', (tester) async {
    final store = DemoStore.seeded();
    await openMarcoSettlementSheet(tester, store);

    await tester.enterText(find.byKey(const Key('settlement-amount')), '10');
    await tester.ensureVisible(find.byKey(const Key('settle-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settle-all')));
    await tester.pumpAndSettle();
    final controller = tester.widget<TextField>(find.byKey(const Key('settlement-amount'))).controller!;
    expect(controller.text, '324.50');

    await tester.ensureVisible(find.byKey(const Key('settle-marco')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settle-marco')));
    await tester.pumpAndSettle();

    final group = store.groupById('apartment');
    expect(group.settlements, hasLength(1));
    expect(group.settlements.first.amountCents, 32450);
    expect(store.balances(group)['marco'], 0);
  });
}
