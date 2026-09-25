import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaquita_mx/src/app.dart';
import 'package:vaquita_mx/src/store.dart';

void main() {
  testWidgets('shows balances, groups, and navigation', (tester) async {
    await tester.pumpWidget(VaquitaApp(store: DemoStore.seeded()));

    expect(find.text('VAQUITA MX'), findsOneWidget);
    expect(find.text('Weekend in CDMX'), findsOneWidget);
    expect(find.text('Apartment'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
  });

  testWidgets('creates a new group from the home screen', (tester) async {
    await tester.pumpWidget(VaquitaApp(store: DemoStore.seeded()));

    await tester.tap(find.byKey(const Key('create-group-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('group-name-field')),
      'Birthday dinner',
    );
    await tester.enterText(
      find.byKey(const Key('group-members-field')),
      'Laura',
    );
    await tester.enterText(find.byType(TextField).at(3), '55 0000 0099');
    await tester.tap(find.byKey(const Key('create-group-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Birthday dinner'), findsOneWidget);
    expect(find.text('2 members · 0 expenses'), findsOneWidget);
  });

  testWidgets('opens a group and adds an expense', (tester) async {
    await tester.pumpWidget(VaquitaApp(store: DemoStore.seeded()));

    await tester.tap(find.byKey(const Key('group-cdmx-weekend')));
    await tester.pumpAndSettle();
    expect(find.text('Weekend in CDMX'), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-expense-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('expense-description-field')),
      'Coffee',
    );
    await tester.enterText(
      find.byKey(const Key('expense-amount-field')),
      '240',
    );
    await tester.ensureVisible(find.byKey(const Key('add-expense-submit')));
    await tester.tap(find.byKey(const Key('add-expense-submit')));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Coffee'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Coffee'), findsOneWidget);
    expect(find.text(r'$240.00'), findsOneWidget);
  });
}
