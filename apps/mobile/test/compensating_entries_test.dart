import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vaquita_mx/l10n/app_localizations.dart';
import 'package:vaquita_mx/src/api_client.dart';
import 'package:vaquita_mx/src/features/app/application/app_cubit.dart';
import 'package:vaquita_mx/src/group_detail_screen.dart';
import 'package:vaquita_mx/src/models.dart';
import 'package:vaquita_mx/src/offline_database.dart';
import 'package:vaquita_mx/src/store.dart';

class _MemoryStorage implements SessionStorage {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

http.Response _jsonResponse(Object body, [int statusCode = 200]) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      statusCode,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

http.Response _loginOk(String accountId, String name, String email) =>
    _jsonResponse({
      'access_token': 'token-$accountId',
      'refresh_token': 'refresh-$accountId',
      'user': {
        'id': accountId,
        'name': name,
        'email': email,
        'phone': '5512345678',
        'salary_cents': 0,
      },
    });

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets(
      'reversing expense and settlement keeps history visible, marks reversed, and updates balances',
      (tester) async {
    final store = DemoStore.seeded();
    await store.createGroup(
      name: 'Cena',
      memberNames: const ['Beto'],
      emoji: '🍽️',
      visibility: 'personal',
      salarySplitEnabled: false,
    );
    final cubit = AppCubit(store);
    addTearDown(() async {
      await cubit.close();
      store.dispose();
    });

    final group = store.groups.first;
    final selfId = group.members[0].id;
    final betoId = group.members[1].id;

    expect(
      await store.addExpense(
        groupId: group.id,
        description: 'Tacos',
        amountCents: 1000,
        payerId: selfId,
        payers: [ExpensePayer(memberId: selfId, amountCents: 1000)],
        participantIds: [selfId, betoId],
      ),
      isTrue,
    );
    expect(
      await store.confirmReceivedPayment(
        groupId: group.id,
        debtorId: betoId,
        amountCents: 200,
      ),
      isTrue,
    );
    final expense = store.groupById(group.id).expenses.single;
    final settlement = store.groupById(group.id).settlements.single;
    expect(
        store.balances(store.groupById(group.id)), {selfId: 300, betoId: -300});

    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GroupDetailScreen(store: store, groupId: group.id),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Reverse the settlement first and confirm debt returns to 500.
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('settlement-card-${settlement.id}')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('reverse-settlement-${settlement.id}')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('reversal-reason-input')),
      'Bounced transfer',
    );
    await tester.tap(find.byKey(const Key('confirm-reversal-button')));
    await tester.pumpAndSettle();

    expect(store.groupById(group.id).settlements.length, 1);
    expect(store.groupById(group.id).settlementReversals.length, 1);
    expect(
        store.balances(store.groupById(group.id)), {selfId: 500, betoId: -500});
    expect(find.text('Reversed'), findsOneWidget);

    // Reverse the expense and confirm balances reach zero while expense remains visible.
    await tester.tap(find.byKey(Key('expense-card-${expense.id}')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('reverse-expense-${expense.id}')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('reversal-reason-input')),
      'Wrong total',
    );
    await tester.tap(find.byKey(const Key('confirm-reversal-button')));
    await tester.pumpAndSettle();

    final after = store.groupById(group.id);
    expect(after.expenses.length, 1);
    expect(after.expenseReversals.length, 1);
    expect(after.totalSpentCents, 0);
    expect(store.balances(after), {selfId: 0, betoId: 0});
    expect(find.text('Tacos'), findsOneWidget);

    // Reopening the reversed expense shows the audit card and hides reversal buttons.
    await tester.tap(find.byKey(Key('expense-card-${expense.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Reversed record'), findsOneWidget);
    expect(find.text('Reason: Wrong total'), findsOneWidget);
    expect(find.byKey(Key('reverse-expense-${expense.id}')), findsNothing);
  });

  testWidgets(
      'reverse and replace adjusts already-settled participants to proportional new debt or credit in favor',
      (tester) async {
    final store = DemoStore.seeded();
    await store.createGroup(
      name: 'Suscripciones',
      memberNames: const ['Beto', 'Carla'],
      emoji: '📺',
      visibility: 'personal',
      salarySplitEnabled: false,
    );
    final cubit = AppCubit(store);
    addTearDown(() async {
      await cubit.close();
      store.dispose();
    });

    final group = store.groups.first;
    final selfId = group.members[0].id;
    final betoId = group.members[1].id;
    final carlaId = group.members[2].id;

    // 1. Original $10.00 percentage expense (50% You, 30% Beto, 20% Carla).
    expect(
      await store.addExpense(
        groupId: group.id,
        description: 'Plan familiar',
        amountCents: 1000,
        payerId: selfId,
        payers: [ExpensePayer(memberId: selfId, amountCents: 1000)],
        participantIds: [selfId, betoId, carlaId],
        splitMode: 'percentage',
        percentages: [
          ExpensePercentage(memberId: selfId, percentageBps: 5000),
          ExpensePercentage(memberId: betoId, percentageBps: 3000),
          ExpensePercentage(memberId: carlaId, percentageBps: 2000),
        ],
      ),
      isTrue,
    );
    final exp1 = store.groupById(group.id).expenses.single;

    // Beto pays his full $3.00 share; Carla has not paid yet.
    expect(
      await store.confirmReceivedPayment(
        groupId: group.id,
        debtorId: betoId,
        amountCents: 300,
      ),
      isTrue,
    );
    expect(store.balances(store.groupById(group.id)), {
      selfId: 200,
      betoId: 0,
      carlaId: -200,
    });

    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GroupDetailScreen(store: store, groupId: group.id),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 2. Reverse & replace with HIGHER total ($15.00) editing ONLY the amount field.
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('expense-card-${exp1.id}')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('reverse-replace-expense-${exp1.id}')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('reversal-reason-input')),
      'Subio la tarifa',
    );
    await tester.tap(find.byKey(const Key('confirm-reversal-button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('expense-amount-field')),
      '15.00',
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('add-expense-submit')));
    await tester.tap(find.byKey(const Key('add-expense-submit')));
    await tester.pumpAndSettle();

    final afterHigher = store.groupById(group.id);
    final exp2 = afterHigher.replacementForExpense(exp1.id)!;
    expect(exp2.amountCents, 1500);
    expect(exp2.paidAmountCents, 1500);
    // Beto already paid $3.00, new share is 30% of $15.00 = $4.50 -> owes $1.50.
    // Carla unpaid -> owes 20% of $15.00 = $3.00.
    expect(store.balances(afterHigher), {
      selfId: 450,
      betoId: -150,
      carlaId: -300,
    });
    expect(store.balanceWith(afterHigher, group.members[1]), 150);

    // 3. Reverse & replace with LOWER total ($5.00) editing ONLY the amount field.
    await tester.tap(find.byKey(Key('expense-card-${exp2.id}')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('reverse-replace-expense-${exp2.id}')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('reversal-reason-input')),
      'Descuento aplicado',
    );
    await tester.tap(find.byKey(const Key('confirm-reversal-button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('expense-amount-field')),
      '5.00',
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('add-expense-submit')));
    await tester.tap(find.byKey(const Key('add-expense-submit')));
    await tester.pumpAndSettle();

    final afterLower = store.groupById(group.id);
    final exp3 = afterLower.replacementForExpense(exp2.id)!;
    expect(exp3.amountCents, 500);
    expect(exp3.paidAmountCents, 500);
    // Beto already paid $3.00, new share is 30% of $5.00 = $1.50 -> +$1.50 credit in his favor!
    // Carla unpaid -> owes 20% of $5.00 = $1.00.
    expect(store.balances(afterLower), {
      selfId: -50,
      betoId: 150,
      carlaId: -100,
    });
    expect(store.balanceWith(afterLower, group.members[1]), -150);
    expect(store.balanceWith(afterLower, group.members[2]), 100);
    final betoStatus =
        store.contactStatus.firstWhere((c) => c.member.id == betoId);
    expect(betoStatus.amountCents, 150);
  });

  test(
      'persists local reversals and replacements across restart and uploads them on opt-in sync idempotently',
      () async {
    final dir = await Directory.systemTemp.createTemp('vaquita-rev-local-');
    final dbPath = p.join(dir.path, 'app.db');
    final syncPayloads = <Map<String, dynamic>>[];

    final db1 = await OfflineDatabase.open(databasePath: dbPath);
    final store1 = DemoStore.offline(null, db1);
    await store1.initialize();
    await store1.createGroup(
      name: 'Viaje',
      memberNames: const ['Luis'],
      emoji: '✈️',
      visibility: 'personal',
      salarySplitEnabled: false,
    );
    final group = store1.groups.single;
    final selfId = group.members[0].id;
    final luisId = group.members[1].id;

    // 1. Original expense + partial settlement + reversal + replacement expense + replacement settlement.
    expect(
      await store1.addExpense(
        groupId: group.id,
        description: 'Hotel equivocado',
        amountCents: 1000,
        payerId: luisId,
        payers: [ExpensePayer(memberId: luisId, amountCents: 1000)],
        participantIds: [selfId, luisId],
      ),
      isTrue,
    );
    final exp1 = store1.groupById(group.id).expenses.single;
    expect(
      await store1.settleBalance(
        groupId: group.id,
        memberId: luisId,
        amountCents: 300,
      ),
      isTrue,
    );
    final set1 = store1.groupById(group.id).settlements.single;
    expect(
      await store1.reverseSettlement(
        groupId: group.id,
        settlementId: set1.id,
        reason: 'Pago equivocado',
      ),
      isTrue,
    );
    // Duplicate local reversal is rejected.
    expect(
      await store1.reverseSettlement(
        groupId: group.id,
        settlementId: set1.id,
        reason: 'Repetido',
      ),
      isFalse,
    );
    expect(store1.errorMessage, 'already_reversed');

    expect(
      await store1.reverseExpense(
        groupId: group.id,
        expenseId: exp1.id,
        reason: 'Monto mal capturado',
      ),
      isTrue,
    );
    expect(store1.balances(store1.groupById(group.id)), {selfId: 0, luisId: 0});

    // Separate replacement expense + replacement settlement.
    expect(
      await store1.addExpense(
        groupId: group.id,
        description: 'Hotel correcto',
        amountCents: 800,
        payerId: luisId,
        payers: [ExpensePayer(memberId: luisId, amountCents: 800)],
        participantIds: [selfId, luisId],
        replacesExpenseId: exp1.id,
      ),
      isTrue,
    );
    expect(
      await store1.settleBalance(
        groupId: group.id,
        memberId: luisId,
        amountCents: 400,
        replacesSettlementId: set1.id,
      ),
      isTrue,
    );
    expect(store1.balances(store1.groupById(group.id)), {selfId: 0, luisId: 0});
    store1.dispose();
    await db1.close();

    // 2. Restart from SQLite, verify persistence, sign in, and sync idempotently.
    final storage = _MemoryStorage();
    final client = ApiClient(
      baseUrl: 'http://example.test',
      storage: storage,
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/auth/login') {
          return _loginOk('user-1', 'Sofía', 'sofia@example.test');
        }
        if (request.method == 'POST' &&
            request.url.path == '/api/v1/offline-sync/groups') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          syncPayloads.add(body);
          final groups =
              (body['groups'] as List<dynamic>).cast<Map<String, dynamic>>();
          return _jsonResponse({
            'groups': [
              for (final g in groups)
                {'local_group_id': g['id'], 'remote_group_id': g['id']},
            ],
          });
        }
        if (request.method == 'GET' && request.url.path == '/api/v1/groups') {
          return _jsonResponse({'groups': []});
        }
        return _jsonResponse({'code': 'not_found'}, 404);
      }),
    );

    final db2 = await OfflineDatabase.open(databasePath: dbPath);
    final store2 = DemoStore.offline(client, db2);
    await store2.initialize();

    final restored = store2.groups.single;
    expect(restored.expenses.length, 2);
    expect(restored.expenseReversals.length, 1);
    expect(restored.settlements.length, 2);
    expect(restored.settlementReversals.length, 1);
    expect(
        restored.replacementForExpense(exp1.id)?.description, 'Hotel correcto');
    expect(restored.replacementForSettlement(set1.id)?.amountCents, 400);
    expect(store2.balances(restored), {selfId: 0, luisId: 0});

    await client.login(email: 'sofia@example.test', password: 'password1');
    await store2.refreshAuthentication();
    expect(await store2.syncLocalGroups(enable: true), isTrue);
    expect(syncPayloads.length, 1);

    final uploadedGroup = (syncPayloads.single['groups'] as List<dynamic>)
        .single as Map<String, dynamic>;
    expect((uploadedGroup['expense_reversals'] as List<dynamic>).length, 1);
    expect((uploadedGroup['settlement_reversals'] as List<dynamic>).length, 1);
    final uploadedExpenses = (uploadedGroup['expenses'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(
      uploadedExpenses.any((e) => e['replaces_expense_id'] == exp1.id),
      isTrue,
    );

    // Re-running sync is idempotent and does not re-upload already synced revisions.
    expect(await store2.syncLocalGroups(), isTrue);
    expect(syncPayloads.length, 1);

    store2.dispose();
    await db2.close();
    await dir.delete(recursive: true);
  });

  test(
      'queues server-group reversals offline, preserves pending state across load, and replays with stable Idempotency-Key',
      () async {
    final dir = await Directory.systemTemp.createTemp('vaquita-rev-outbox-');
    final dbPath = p.join(dir.path, 'app.db');
    final seenExpenseKeys = <String>[];
    final seenSettlementKeys = <String>[];
    var failTransient = true;
    var serverReversedExpense = false;
    var serverReversedSettlement = false;

    Map<String, dynamic> serverGroupJson() => {
          'id': 'group_srv_1',
          'name': 'Roomies',
          'emoji': '🏠',
          'visibility': 'shared',
          'salary_split_enabled': false,
          'salary_split_available': false,
          'members': [
            {
              'id': 'user-1',
              'user_id': 'user-1',
              'role': 'owner',
              'name': 'Ana',
              'active': true,
              'accepted': true,
            },
            {
              'id': 'member-2',
              'user_id': 'user-2',
              'role': 'member',
              'name': 'Beto',
              'active': true,
              'accepted': true,
            },
          ],
          'expenses': [
            {
              'id': 'expense_srv_1',
              'description': 'Luz',
              'amount_cents': 1000,
              'payer_id': 'user-1',
              'payers': [
                {'member_id': 'user-1', 'amount_cents': 1000},
              ],
              'participant_ids': ['user-1', 'member-2'],
              'split_mode': 'equal',
              'shares': {'user-1': 500, 'member-2': 500},
              'created_at': '2026-11-21T10:00:00Z',
            },
          ],
          'expense_reversals': [
            if (serverReversedExpense)
              {
                'id': 'expense_reversal_srv_1',
                'original_expense_id': 'expense_srv_1',
                'actor_user_id': 'user-1',
                'actor_member_id': 'user-1',
                'reason': 'Recibo duplicado',
                'created_at': '2026-11-21T10:10:00Z',
              },
          ],
          'settlements': [
            {
              'id': 'settlement_srv_1',
              'from_member_id': 'member-2',
              'to_member_id': 'user-1',
              'amount_cents': 200,
              'created_at': '2026-11-21T10:05:00Z',
            },
          ],
          'settlement_reversals': [
            if (serverReversedSettlement)
              {
                'id': 'settlement_reversal_srv_1',
                'original_settlement_id': 'settlement_srv_1',
                'actor_user_id': 'user-1',
                'actor_member_id': 'user-1',
                'reason': 'Transferencia cancelada',
                'created_at': '2026-11-21T10:09:00Z',
              },
          ],
          'balances': {
            'user-1': serverReversedExpense
                ? (serverReversedSettlement ? 0 : -200)
                : (serverReversedSettlement ? 500 : 300),
            'member-2': serverReversedExpense
                ? (serverReversedSettlement ? 0 : 200)
                : (serverReversedSettlement ? -500 : -300),
          },
          'payment_relations': const [],
        };

    final storage = _MemoryStorage();
    final client = ApiClient(
      baseUrl: 'http://example.test',
      storage: storage,
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/auth/login') {
          return _loginOk('user-1', 'Ana', 'ana@example.test');
        }
        if (request.method == 'GET' && request.url.path == '/api/v1/groups') {
          return _jsonResponse({
            'groups': [serverGroupJson()]
          });
        }
        if (request.method == 'GET' && request.url.path == '/api/v1/status') {
          return _jsonResponse({'contacts': []});
        }
        if (request.method == 'POST' &&
            request.url.path ==
                '/api/v1/groups/group_srv_1/settlements/settlement_srv_1/reversals') {
          seenSettlementKeys.add(request.headers['Idempotency-Key'] ?? '');
          if (failTransient) {
            return _jsonResponse({'code': 'service_unavailable'}, 503);
          }
          serverReversedSettlement = true;
          return _jsonResponse(serverGroupJson(), 201);
        }
        if (request.method == 'POST' &&
            request.url.path ==
                '/api/v1/groups/group_srv_1/expenses/expense_srv_1/reversals') {
          seenExpenseKeys.add(request.headers['Idempotency-Key'] ?? '');
          serverReversedExpense = true;
          return _jsonResponse(serverGroupJson(), 201);
        }
        return _jsonResponse({'code': 'not_found'}, 404);
      }),
    );

    final db = await OfflineDatabase.open(databasePath: dbPath);
    final store = DemoStore.offline(client, db);
    await store.initialize();
    await client.login(email: 'ana@example.test', password: 'password1');
    await store.load();

    // Go offline and queue both settlement and expense reversals.
    store.setConnectivityOnline(false);
    expect(
      await store.reverseSettlement(
        groupId: 'group_srv_1',
        settlementId: 'settlement_srv_1',
        reason: 'Transferencia cancelada',
      ),
      isTrue,
    );
    expect(store.lastMutationQueuedOffline, isTrue);
    expect(
      await store.reverseExpense(
        groupId: 'group_srv_1',
        expenseId: 'expense_srv_1',
        reason: 'Recibo duplicado',
      ),
      isTrue,
    );
    expect(store.pendingMutationCountForGroup('group_srv_1'), 2);
    expect(store.balances(store.groupById('group_srv_1')),
        {'user-1': 0, 'member-2': 0});

    // Adding an offline expense cannot be reversed until it receives a server ID.
    expect(
      await store.addExpense(
        groupId: 'group_srv_1',
        description: 'Agua offline',
        amountCents: 200,
        payerId: 'user-1',
        payers: [const ExpensePayer(memberId: 'user-1', amountCents: 200)],
        participantIds: const ['user-1', 'member-2'],
      ),
      isTrue,
    );
    final pendingLocalExp = store
        .groupById('group_srv_1')
        .expenses
        .firstWhere((e) => e.id.startsWith('local_expense_'));
    expect(
      await store.reverseExpense(
        groupId: 'group_srv_1',
        expenseId: pendingLocalExp.id,
        reason: 'Todavía no sincroniza',
      ),
      isFalse,
    );
    expect(store.errorMessage, 'sync_required_before_reversal');

    // Discard the extra offline expense mutation so only the two reversals remain.
    final extraMutation = store.pendingMutations
        .firstWhere((m) => m.localEntityId == pendingLocalExp.id);
    await store.discardFailedMutation(extraMutation.id);

    // load() while pending mutations exist must keep local pending state authoritative.
    await store.load();
    expect(store.groupById('group_srv_1').expenseReversals.length, 1);
    expect(store.groupById('group_srv_1').settlementReversals.length, 1);

    // Reconnect: first attempt hits 503, second attempt replays with identical Idempotency-Key.
    store.setConnectivityOnline(true);
    expect(await store.syncPendingMutations(), isFalse);
    expect(seenSettlementKeys.length, 1);
    expect(store.pendingMutationCountForGroup('group_srv_1'), 2);

    failTransient = false;
    expect(await store.syncPendingMutations(), isTrue);
    expect(seenSettlementKeys.length, 2);
    expect(seenSettlementKeys[0], seenSettlementKeys[1]);
    expect(seenSettlementKeys[0], isNotEmpty);
    expect(seenExpenseKeys.length, 1);
    expect(seenExpenseKeys[0], isNotEmpty);
    expect(store.pendingMutationCountForGroup('group_srv_1'), 0);

    final synced = store.groupById('group_srv_1');
    expect(synced.expenseReversals.single.id, 'expense_reversal_srv_1');
    expect(synced.settlementReversals.single.id, 'settlement_reversal_srv_1');
    expect(store.balances(synced), {'user-1': 0, 'member-2': 0});

    store.dispose();
    await db.close();
    await dir.delete(recursive: true);
  });

  test('shared-group debtor cannot reverse a settlement received by creditor',
      () async {
    final storage = _MemoryStorage();
    final client = ApiClient(
      baseUrl: 'http://example.test',
      storage: storage,
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/auth/login') {
          return _loginOk('user-beto', 'Beto', 'beto@example.test');
        }
        if (request.method == 'GET' && request.url.path == '/api/v1/groups') {
          return _jsonResponse({
            'groups': [
              {
                'id': 'group_shared_1',
                'name': 'Shared',
                'emoji': '🏠',
                'visibility': 'shared',
                'members': [
                  {
                    'id': 'user-ana',
                    'user_id': 'user-ana',
                    'role': 'owner',
                    'name': 'Ana',
                    'active': true,
                    'accepted': true,
                  },
                  {
                    'id': 'member-beto',
                    'user_id': 'user-beto',
                    'role': 'member',
                    'name': 'Beto',
                    'active': true,
                    'accepted': true,
                  },
                ],
                'expenses': [
                  {
                    'id': 'exp-1',
                    'description': 'Gas',
                    'amount_cents': 1000,
                    'payer_id': 'user-ana',
                    'payers': [
                      {'member_id': 'user-ana', 'amount_cents': 1000},
                    ],
                    'participant_ids': ['user-ana', 'member-beto'],
                    'split_mode': 'equal',
                    'shares': {'user-ana': 500, 'member-beto': 500},
                    'created_at': '2026-11-21T10:00:00Z',
                  },
                ],
                'settlements': [
                  {
                    'id': 'set-1',
                    'from_member_id': 'member-beto',
                    'to_member_id': 'user-ana',
                    'amount_cents': 500,
                    'created_at': '2026-11-21T10:05:00Z',
                  },
                ],
                'balances': {'user-ana': 0, 'member-beto': 0},
                'payment_relations': const [],
              },
            ],
          });
        }
        return _jsonResponse({'code': 'not_found'}, 404);
      }),
    );

    final store = DemoStore.offline(client, null);
    await client.login(email: 'beto@example.test', password: 'password1');
    await store.load();
    final group = store.groupById('group_shared_1');
    expect(store.canReverseExpense(group, group.expenses.single), isTrue);
    expect(
        store.canReverseSettlement(group, group.settlements.single), isFalse);
    expect(
      await store.reverseSettlement(
        groupId: group.id,
        settlementId: 'set-1',
        reason: 'Debtor attempt',
      ),
      isFalse,
    );
    expect(store.errorMessage, 'resource_not_found');
    store.dispose();
  });
}
