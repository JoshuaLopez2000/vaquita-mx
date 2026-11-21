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

http.Response _loginOk(String accountId, String name, String email) =>
    http.Response(
      jsonEncode({
        'access_token': 'token-$accountId',
        'refresh_token': 'refresh-$accountId',
        'user': {
          'id': accountId,
          'name': name,
          'email': email,
          'phone': '5512345678',
          'salary_cents': 0,
        },
      }),
      200,
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets(
      'add expense form previews percentages and centavos, validates 100%, and saves percentage split',
      (tester) async {
    final store = DemoStore.seeded();
    await store.createGroup(
      name: 'Trio',
      memberNames: const ['Beto', 'Carla'],
      emoji: 'P',
      visibility: 'personal',
      salarySplitEnabled: false,
    );
    final cubit = AppCubit(store);
    addTearDown(() async {
      await cubit.close();
      store.dispose();
    });
    final group = store.groups.first;
    final m0 = group.members[0].id;
    final m1 = group.members[1].id;
    final m2 = group.members[2].id;

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

    await tester.tap(find.byKey(const Key('add-expense-button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('expense-description-field')),
      'Pizza night',
    );
    await tester.enterText(
      find.byKey(const Key('expense-amount-field')),
      '10.00',
    );
    await tester.pump();

    // Switch to Percentage mode; auto-populates equal 33.34 / 33.33 / 33.33
    // and previews resulting centavos immediately.
    await tester.tap(find.text('Percentage'));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('expense-percentage-$m0')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(Key('expense-percentage-preview-$m0'))).data,
      r'$3.34',
    );
    expect(
      tester.widget<Text>(find.byKey(Key('expense-percentage-preview-$m1'))).data,
      r'$3.33',
    );
    expect(
      tester.widget<Text>(find.byKey(Key('expense-percentage-preview-$m2'))).data,
      r'$3.33',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('expense-percentage-remaining'))).data,
      'Remaining: 0.00%',
    );

    // Invalid total (90%) blocks submission and shows actionable error.
    await tester.enterText(find.byKey(Key('expense-percentage-$m0')), '50');
    await tester.enterText(find.byKey(Key('expense-percentage-$m1')), '30');
    await tester.enterText(find.byKey(Key('expense-percentage-$m2')), '10');
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('expense-percentage-remaining'))).data,
      'Remaining: 10.00%',
    );

    await tester.ensureVisible(find.byKey(const Key('add-expense-submit')));
    await tester.tap(find.byKey(const Key('add-expense-submit')));
    await tester.pumpAndSettle();
    expect(
      find.text('Percentages must be greater than 0% and add up to exactly 100.00%.'),
      findsOneWidget,
    );

    // Fix to 50 / 30 / 20 and verify live preview updates before submit.
    await tester.enterText(find.byKey(Key('expense-percentage-$m2')), '20');
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(Key('expense-percentage-preview-$m0'))).data,
      r'$5.00',
    );
    expect(
      tester.widget<Text>(find.byKey(Key('expense-percentage-preview-$m1'))).data,
      r'$3.00',
    );
    expect(
      tester.widget<Text>(find.byKey(Key('expense-percentage-preview-$m2'))).data,
      r'$2.00',
    );

    await tester.ensureVisible(find.byKey(const Key('add-expense-submit')));
    await tester.tap(find.byKey(const Key('add-expense-submit')));
    await tester.pumpAndSettle();

    final created = store.groupById(group.id).expenses.first;
    expect(created.description, 'Pizza night');
    expect(created.splitMode, 'percentage');
    expect(created.percentages, {m0: 5000, m1: 3000, m2: 2000});
    expect(created.shares, {m0: 500, m1: 300, m2: 200});

    // Open details sheet and verify percentage mode + stored percentages show.
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pizza night'));
    await tester.pumpAndSettle();
    expect(find.text('Percentage split'), findsOneWidget);
    expect(find.text('50.00% of total'), findsOneWidget);
    expect(find.text('30.00% of total'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('20.00% of total'), findsOneWidget);
  });

  test(
      'persists local percentage expense across restart and uploads percentages on opt-in sync idempotently',
      () async {
    final dir = await Directory.systemTemp.createTemp('vaquita-pct-local-');
    final dbPath = p.join(dir.path, 'app.db');
    final syncPayloads = <Map<String, dynamic>>[];

    // 1. Local-only before sign-in: create group and percentage expense.
    final db1 = await OfflineDatabase.open(databasePath: dbPath);
    final store1 = DemoStore.offline(null, db1);
    await store1.initialize();
    await store1.createGroup(
      name: 'Roadtrip',
      memberNames: const ['Beto', 'Carla'],
      emoji: 'R',
      visibility: 'personal',
      salarySplitEnabled: false,
    );
    final localGroup = store1.groups.single;
    final m0 = localGroup.members[0].id;
    final m1 = localGroup.members[1].id;
    final m2 = localGroup.members[2].id;

    expect(
      await store1.addExpense(
        groupId: localGroup.id,
        description: 'Gas',
        amountCents: 1000,
        payerId: m0,
        payers: [ExpensePayer(memberId: m0, amountCents: 1000)],
        participantIds: [m0, m1, m2],
        splitMode: 'percentage',
        percentages: [
          ExpensePercentage(memberId: m0, percentageBps: 3334),
          ExpensePercentage(memberId: m1, percentageBps: 3333),
          ExpensePercentage(memberId: m2, percentageBps: 3333),
        ],
      ),
      isTrue,
    );
    expect(store1.balances(localGroup), {m0: 666, m1: -333, m2: -333});
    store1.dispose();
    await db1.close();

    // 2. Restart app, sign in, and opt in to sync local groups.
    final storage = _MemoryStorage();
    final client = ApiClient(
      baseUrl: 'http://example.test',
      storage: storage,
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/auth/login') {
          return _loginOk('user-1', 'Ana', 'ana@example.test');
        }
        if (request.method == 'POST' &&
            request.url.path == '/api/v1/offline-sync/groups') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          syncPayloads.add(body);
          final groups = (body['groups'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
          return http.Response(
            jsonEncode({
              'groups': [
                for (final g in groups)
                  {'local_group_id': g['id'], 'remote_group_id': g['id']},
              ],
            }),
            200,
          );
        }
        if (request.method == 'GET' && request.url.path == '/api/v1/groups') {
          return http.Response(jsonEncode({'groups': <Object>[]}), 200);
        }
        throw StateError('Unexpected: ${request.method} ${request.url}');
      }),
    );

    final db2 = await OfflineDatabase.open(databasePath: dbPath);
    final store2 = DemoStore.offline(client, db2);
    await store2.initialize();

    // Persisted across restart with identical percentages, shares, and balances.
    final restored = store2.groupById(localGroup.id);
    expect(restored.expenses.single.splitMode, 'percentage');
    expect(restored.expenses.single.percentages, {m0: 3334, m1: 3333, m2: 3333});
    expect(restored.expenses.single.shares, {m0: 334, m1: 333, m2: 333});
    expect(store2.balances(restored), {m0: 666, m1: -333, m2: -333});

    await client.login(email: 'ana@example.test', password: 'secret');
    expect(await store2.syncLocalGroups(enable: true), isTrue);
    expect(syncPayloads, hasLength(1));
    final uploadedExpense =
        ((syncPayloads.single['groups'] as List<dynamic>).single
            as Map<String, dynamic>)['expenses'][0] as Map<String, dynamic>;
    expect(uploadedExpense['split_mode'], 'percentage');
    expect(uploadedExpense['percentages'], {m0: 3334, m1: 3333, m2: 3333});

    // Retry syncLocalGroups is a safe no-op once synced.
    expect(await store2.syncLocalGroups(), isTrue);
    expect(syncPayloads, hasLength(1));

    store2.dispose();
    client.close();
    await db2.close();
    await dir.delete(recursive: true);
  });

  test(
      'queues offline percentage expense on server-backed group, preserves pending across load, and replays with identical idempotency key',
      () async {
    final dir = await Directory.systemTemp.createTemp('vaquita-pct-server-');
    final dbPath = p.join(dir.path, 'app.db');
    final storage = _MemoryStorage();
    final serverExpenses = <Map<String, dynamic>>[];
    final recordedKeys = <String>[];
    final recordedBodies = <Map<String, dynamic>>[];
    var online = true;
    var failFirstPost500 = true;

    ApiClient makeClient() => ApiClient(
          baseUrl: 'http://example.test',
          storage: storage,
          client: MockClient((request) async {
            if (request.url.path == '/api/v1/auth/login') {
              return _loginOk('user-1', 'Ana', 'ana@example.test');
            }
            if (!online) throw const SocketException('offline');
            if (request.method == 'GET' &&
                request.url.path == '/api/v1/groups') {
              return http.Response(
                jsonEncode({
                  'groups': [
                    {
                      'id': 'group-srv-1',
                      'name': 'Roomies',
                      'emoji': 'H',
                      'visibility': 'shared',
                      'members': [
                        {'id': 'user-1', 'user_id': 'user-1', 'name': 'Ana'},
                        {'id': 'member-2', 'name': 'Beto'},
                      ],
                      'expenses': serverExpenses,
                      'settlements': <Object>[],
                    },
                  ],
                }),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }
            if (request.method == 'GET' &&
                request.url.path == '/api/v1/status') {
              return http.Response(jsonEncode({'statuses': <Object>[]}), 200);
            }
            if (request.method == 'POST' &&
                request.url.path == '/api/v1/groups/group-srv-1/expenses') {
              recordedKeys.add(request.headers['Idempotency-Key']!);
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              recordedBodies.add(body);
              if (failFirstPost500) {
                failFirstPost500 = false;
                return http.Response(
                  jsonEncode({'code': 'server_error', 'message': 'retry'}),
                  500,
                );
              }
              serverExpenses.add({
                'id': 'exp-srv-1',
                'description': body['description'],
                'amount_cents': body['amount_cents'],
                'payer_id': body['payer_id'],
                'payers': body['payers'],
                'participant_ids': body['participant_ids'],
                'split_mode': body['split_mode'],
                'percentages': {'user-1': 7000, 'member-2': 3000},
                'shares': {'user-1': 701, 'member-2': 300},
                'created_at': DateTime.utc(2026, 11, 21).toIso8601String(),
              });
              return http.Response(jsonEncode({'id': 'exp-srv-1'}), 201);
            }
            throw StateError('Unexpected: ${request.method} ${request.url}');
          }),
        );

    final db1 = await OfflineDatabase.open(databasePath: dbPath);
    final client1 = makeClient();
    await client1.login(email: 'ana@example.test', password: 'secret');
    final store1 = DemoStore.offline(client1, db1);
    await store1.initialize();
    await store1.load();

    // Go offline and record percentage expense on server-backed group.
    online = false;
    store1.setConnectivityOnline(false);
    expect(
      await store1.addExpense(
        groupId: 'group-srv-1',
        description: 'Internet',
        amountCents: 1001,
        payerId: 'user-1',
        payers: const [ExpensePayer(memberId: 'user-1', amountCents: 1001)],
        participantIds: const ['user-1', 'member-2'],
        splitMode: 'percentage',
        percentages: const [
          ExpensePercentage(memberId: 'user-1', percentageBps: 7000),
          ExpensePercentage(memberId: 'member-2', percentageBps: 3000),
        ],
      ),
      isTrue,
    );
    expect(store1.lastMutationQueuedOffline, isTrue);
    expect(store1.pendingMutationCountForGroup('group-srv-1'), 1);
    expect(
      store1.balances(store1.groupById('group-srv-1')),
      const {'user-1': 300, 'member-2': -300},
    );

    // Come back online: load() must keep pending local copy until outbox drains.
    online = true;
    store1.setConnectivityOnline(true);
    await store1.load();
    expect(store1.groupById('group-srv-1').expenses, hasLength(1));

    // First sync attempt hits transient 500 -> stays pending.
    expect(await store1.syncPendingMutations(), isFalse);
    expect(store1.pendingMutationCountForGroup('group-srv-1'), 1);

    // Second sync attempt succeeds with the EXACT same Idempotency-Key.
    expect(await store1.syncPendingMutations(), isTrue);
    expect(store1.pendingMutationCountForGroup('group-srv-1'), 0);
    expect(recordedKeys, hasLength(2));
    expect(recordedKeys[0], recordedKeys[1]);
    expect(recordedBodies.last['split_mode'], 'percentage');
    expect(recordedBodies.last['percentages'], [
      {'member_id': 'user-1', 'percentage_bps': 7000},
      {'member_id': 'member-2', 'percentage_bps': 3000},
    ]);
    final syncedExpense = store1.groupById('group-srv-1').expenses.single;
    expect(syncedExpense.id, 'exp-srv-1');
    expect(syncedExpense.shares, const {'user-1': 701, 'member-2': 300});
    expect(syncedExpense.percentages, const {'user-1': 7000, 'member-2': 3000});

    store1.dispose();
    client1.close();
    await db1.close();
    await dir.delete(recursive: true);
  });
}
