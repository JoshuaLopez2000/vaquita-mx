import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaquita_mx/src/app.dart';
import 'package:vaquita_mx/src/models.dart';
import 'package:vaquita_mx/src/store.dart';

void main() {
  testWidgets('shows balances, groups, and navigation', (tester) async {
    await tester.pumpWidget(VaquitaApp(store: DemoStore.seeded()));

    expect(find.text('VAQUITA MX'), findsOneWidget);
    expect(find.text('Weekend in CDMX'), findsOneWidget);
    expect(find.text('Apartment'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Inbox'), findsOneWidget);
    expect(find.text('Movements'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
  });

  testWidgets('shows an empty state in the inbox tab', (tester) async {
    await tester.pumpWidget(VaquitaApp(store: DemoStore.seeded()));

    await tester.tap(find.text('Inbox'));
    await tester.pumpAndSettle();

    expect(find.text('You\'re all caught up'), findsOneWidget);
    expect(
      find.text('Invitations and contact balances will appear here.'),
      findsOneWidget,
    );
  });

  testWidgets('shows group expenses in the movements tab', (tester) async {
    await tester.pumpWidget(VaquitaApp(store: DemoStore.seeded()));

    await tester.tap(find.text('Movements'));
    await tester.pumpAndSettle();

    expect(find.text('Tacos and drinks'), findsOneWidget);
  });

  testWidgets('opens balance details from an inbox card', (tester) async {
    final store = DemoStore.seeded();
    store.contactStatus.add(const ContactStatus(
      member: Member(id: 'ana', name: 'Ana'),
      amountCents: 32000,
    ));
    await tester.pumpWidget(VaquitaApp(store: store));

    await tester.tap(find.text('Inbox'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ana'));
    await tester.pumpAndSettle();

    expect(find.text('Balance details'), findsOneWidget);
    expect(find.text('Weekend in CDMX'), findsOneWidget);
    expect(find.text('Tacos and drinks'), findsOneWidget);
    expect(
        find.byKey(const Key('request-payment-cdmx-weekend')), findsOneWidget);
    await tester.tap(find.byKey(const Key('request-payment-cdmx-weekend')));
    await tester.pumpAndSettle();
    expect(find.text('Request from Ana'), findsOneWidget);
    expect(find.text('Simulate payment'), findsOneWidget);
    await tester.tap(find.byKey(const Key('settle-ana')));
    await tester.pumpAndSettle();
    expect(find.text('Movements'), findsWidgets);
    expect(find.text('Ana paid You'), findsOneWidget);
    expect(find.byKey(const Key('request-payment-cdmx-weekend')), findsNothing);
    expect(find.text('Ana'), findsNothing);
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

  testWidgets('shows pending invitations in the group member list',
      (tester) async {
    final store = DemoStore.seeded();
    store.groupById('cdmx-weekend').members.add(
          const Member(id: 'pending-member', name: 'Lucía', accepted: false),
        );
    await tester.pumpWidget(VaquitaApp(store: store));

    await tester.tap(find.byKey(const Key('group-cdmx-weekend')));
    await tester.pumpAndSettle();

    expect(find.text('Lucía'), findsOneWidget);
    expect(find.text('Invitation pending'), findsOneWidget);
  });
}
