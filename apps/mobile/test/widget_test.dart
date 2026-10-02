import 'package:flutter/material.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
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
    expect(find.text('Inicio'), findsOneWidget);
    expect(find.text('Bandeja'), findsOneWidget);
    expect(find.text('Movimientos'), findsOneWidget);
    expect(find.text('Contactos'), findsOneWidget);
    expect(find.text('Perfil'), findsOneWidget);
  });

  testWidgets('shows an empty state in the inbox tab', (tester) async {
    await tester.pumpWidget(VaquitaApp(store: DemoStore.seeded()));

    await tester.tap(find.text('Bandeja'));
    await tester.pumpAndSettle();

    expect(find.text('Estás al día'), findsOneWidget);
    expect(
      find.text('Las invitaciones y los saldos de contactos aparecerán aquí.'),
      findsOneWidget,
    );
  });

  testWidgets('shows group expenses in the movements tab', (tester) async {
    await tester.pumpWidget(VaquitaApp(store: DemoStore.seeded()));

    await tester.tap(find.text('Movimientos'));
    await tester.pumpAndSettle();

    expect(find.text('Tacos and drinks'), findsOneWidget);
  });

  testWidgets('switches tabs when swiping', (tester) async {
    await tester.pumpWidget(VaquitaApp(store: DemoStore.seeded()));

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text('Bandeja'), findsWidgets);
  });

  testWidgets('changes the app language from profile settings', (tester) async {
    await tester.pumpWidget(VaquitaApp(store: DemoStore.seeded()));

    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language-settings-button')));
    await tester.pumpAndSettle();

    expect(find.text('Español'), findsOneWidget);
    expect(find.text('Inglés'), findsOneWidget);
    await tester.tap(find.text('Inglés'));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('opens balance details from an inbox card', (tester) async {
    final store = DemoStore.seeded();
    store.contactStatus.add(const ContactStatus(
      member: Member(id: 'ana', name: 'Ana'),
      amountCents: 32000,
    ));
    await tester.pumpWidget(VaquitaApp(store: store));

    await tester.tap(find.text('Bandeja'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ana'));
    await tester.pumpAndSettle();

    expect(find.text('Detalles del saldo'), findsOneWidget);
    expect(find.text('Weekend in CDMX'), findsOneWidget);
    expect(find.text('Tacos and drinks'), findsOneWidget);
    expect(
        find.byKey(const Key('request-payment-cdmx-weekend')), findsOneWidget);
    await tester.tap(find.byKey(const Key('request-payment-cdmx-weekend')));
    await tester.pumpAndSettle();
    expect(find.text('Solicitar a Ana'), findsOneWidget);
    expect(find.byKey(const Key('settle-ana')), findsOneWidget);
  });

  testWidgets('creates a new group from the home screen', (tester) async {
    await tester.pumpWidget(VaquitaApp(store: DemoStore.seeded()));

    await tester.tap(find.byKey(const Key('create-group-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('salary-inference-notice')), findsNothing);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('salary-inference-notice')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('group-name-field')),
      'Birthday dinner',
    );
    await tester.tap(find.byKey(const Key('group-emoji-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('😀').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('group-members-field')),
      'Laura',
    );
    await tester.enterText(find.byType(TextField).at(3), '55 0000 0099');
    await tester.ensureVisible(find.byKey(const Key('create-group-submit')));
    await tester.tap(find.byKey(const Key('create-group-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Birthday dinner'), findsOneWidget);
    expect(find.text('2 miembros · 0 gastos'), findsOneWidget);
  });

  testWidgets('requires an emoji before creating a group', (tester) async {
    await tester.pumpWidget(VaquitaApp(store: DemoStore.seeded()));

    await tester.tap(find.byKey(const Key('create-group-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('group-name-field')),
      'Birthday dinner',
    );
    await tester.tap(find.byKey(const Key('create-group-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Ícono del grupo'), findsAtLeastNWidgets(2));
  });

  testWidgets('opens the emoji picker when choosing a group icon',
      (tester) async {
    await tester.pumpWidget(VaquitaApp(store: DemoStore.seeded()));

    await tester.tap(find.byKey(const Key('create-group-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('group-emoji-picker')));
    await tester.pumpAndSettle();

    expect(find.byType(EmojiPicker), findsOneWidget);
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

  testWidgets('shows how an expense was split', (tester) async {
    await tester.pumpWidget(VaquitaApp(store: DemoStore.seeded()));

    await tester.tap(find.byKey(const Key('group-cdmx-weekend')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Tacos and drinks'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Tacos and drinks'));
    await tester.pumpAndSettle();

    expect(find.text('Detalles del gasto'), findsOneWidget);
    expect(find.text('División igualitaria'), findsOneWidget);
    expect(find.text('Parte de cada participante'), findsOneWidget);
    expect(find.text(r'$320.00'), findsWidgets);
  });

  testWidgets('shows exact salary-based participant shares', (tester) async {
    final store = DemoStore.seeded();
    store.groupById('cdmx-weekend').expenses.insert(
          0,
          Expense(
            id: 'salary-expense',
            description: 'Salary dinner',
            amountCents: 10000,
            payerId: DemoStore.seedUserId,
            participantIds: const [DemoStore.seedUserId, 'ana'],
            createdAt: DateTime(2026),
            splitMode: 'salary',
            shares: const {DemoStore.seedUserId: 2500, 'ana': 7500},
          ),
        );
    await tester.pumpWidget(VaquitaApp(store: store));

    await tester.tap(find.byKey(const Key('group-cdmx-weekend')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Salary dinner'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Salary dinner'));
    await tester.pumpAndSettle();

    expect(find.text('División por salario'), findsOneWidget);
    expect(find.text(r'$25.00'), findsOneWidget);
    expect(find.text(r'$75.00'), findsOneWidget);
  });

  testWidgets('lists pending bilateral payments from the group',
      (tester) async {
    await tester.pumpWidget(VaquitaApp(store: DemoStore.seeded()));

    await tester.tap(find.byKey(const Key('group-cdmx-weekend')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('group-balance-card')));
    await tester.pumpAndSettle();

    expect(find.text('Pagos pendientes'), findsOneWidget);
    expect(find.text('Ana paga a Tú'), findsOneWidget);
    expect(find.text(r'$200.00'), findsOneWidget);
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
    expect(find.text('Invitación pendiente'), findsOneWidget);
  });

  testWidgets('can dismiss group configuration while editing', (tester) async {
    await tester.pumpWidget(VaquitaApp(store: DemoStore.seeded()));

    await tester.tap(find.byKey(const Key('group-cdmx-weekend')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Opciones del grupo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar grupo y agregar contactos'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('salary-inference-notice')), findsNothing);
    await tester.enterText(find.byType(TextField).first, 'Updated weekend');

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    expect(find.text('Weekend in CDMX'), findsOneWidget);
  });

  testWidgets('shows salary inference notice for salary-based groups',
      (tester) async {
    final store = DemoStore.seeded();
    store.groups.insert(
      0,
      ExpenseGroup(
        id: 'salary-group',
        name: 'Salary group',
        emoji: '\u{1F4B0}',
        members: const [
          Member(id: DemoStore.seedUserId, name: 'You'),
          Member(id: 'ana', name: 'Ana'),
        ],
        visibility: 'shared',
        salarySplitEnabled: true,
        salarySplitAvailable: true,
      ),
    );
    await tester.pumpWidget(VaquitaApp(store: store));

    await tester.tap(find.byKey(const Key('group-salary-group')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Opciones del grupo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar grupo y agregar contactos'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('salary-inference-notice')), findsOneWidget);
  });
}
