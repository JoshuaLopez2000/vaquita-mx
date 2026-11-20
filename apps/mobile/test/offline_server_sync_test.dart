import 'dart:async';
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
import 'package:vaquita_mx/src/app.dart';
import 'package:vaquita_mx/src/features/app/application/app_cubit.dart';
import 'package:vaquita_mx/src/group_detail_screen.dart';
import 'package:vaquita_mx/src/models.dart';
import 'package:vaquita_mx/src/offline_database.dart';
import 'package:vaquita_mx/src/store.dart';

class _MemorySessionStorage implements SessionStorage {
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

  test(
      'caches groups on first login, queues offline expense and receipt across restart, and syncs in FIFO order on reconnect',
      () async {
    final directory = await Directory.systemTemp.createTemp('vaquita-fifo-');
    final dbPath = p.join(directory.path, 'app.db');
    final storage = _MemorySessionStorage();
    final serverExpenses = <Map<String, dynamic>>[];
    final serverSettlements = <Map<String, dynamic>>[];
    final replayedPaths = <String>[];
    final replayedKeys = <String>[];
    var online = true;

    ApiClient makeClient() => ApiClient(
          baseUrl: 'http://example.test',
          storage: storage,
          client: MockClient((request) async {
            if (request.url.path == '/api/v1/auth/login') {
              return _loginOk('user-1', 'Ana', 'ana@example.test');
            }
            if (!online) {
              throw const SocketException('offline');
            }
            if (request.method == 'GET' && request.url.path == '/api/v1/groups') {
              return http.Response(
                jsonEncode({
                  'groups': [
                    {
                      'id': 'group-shared-1',
                      'name': 'CDMX Trip',
                      'emoji': '🌮',
                      'visibility': 'shared',
                      'members': [
                        {'id': 'user-1', 'user_id': 'user-1', 'name': 'Ana'},
                        {'id': 'member-2', 'name': 'Beto'},
                      ],
                      'expenses': serverExpenses,
                      'settlements': serverSettlements,
                    }
                  ],
                }),
                200,
                headers: const {
                  'content-type': 'application/json; charset=utf-8'
                },
              );
            }
            if (request.method == 'POST' &&
                request.url.path == '/api/v1/groups/group-shared-1/expenses') {
              replayedPaths.add(request.url.path);
              replayedKeys.add(request.headers['idempotency-key'] ?? '');
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              serverExpenses.add({
                'id': 'expense-server-1',
                'description': body['description'],
                'amount_cents': body['amount_cents'],
                'payer_id': body['payer_id'],
                'payers': body['payers'],
                'participant_ids': body['participant_ids'],
                'split_mode': body['split_mode'],
                'shares': {'user-1': 5000, 'member-2': 5000},
                'created_at': DateTime.utc(2026, 11, 20).toIso8601String(),
              });
              return http.Response(jsonEncode({'id': 'expense-server-1'}), 201);
            }
            if (request.method == 'POST' &&
                request.url.path ==
                    '/api/v1/groups/group-shared-1/settlements/received') {
              replayedPaths.add(request.url.path);
              replayedKeys.add(request.headers['idempotency-key'] ?? '');
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              expect(body['debtor_member_id'], 'member-2');
              expect(body['amount_cents'], 3000);
              serverSettlements.add({
                'id': 'settlement-server-1',
                'from_member_id': 'member-2',
                'to_member_id': 'user-1',
                'amount_cents': body['amount_cents'],
                'created_at': DateTime.utc(2026, 11, 20).toIso8601String(),
              });
              return http.Response(
                  jsonEncode({'id': 'settlement-server-1'}), 201);
            }
            if (request.method == 'GET' && request.url.path == '/api/v1/status') {
              return http.Response(jsonEncode({'contacts': <Object>[]}), 200);
            }
            throw StateError(
                'Unexpected request: ${request.method} ${request.url}');
          }),
        );

    // First login while online: fetch groups and cache to SQLite.
    var db = await OfflineDatabase.open(databasePath: dbPath);
    var client = makeClient();
    var store = DemoStore.offline(client, db);
    await store.initialize();
    await client.login(email: 'ana@example.test', password: 'password');
    await client.persistSession();
    await store.refreshAuthentication();
    await store.load();
    expect(store.groups, hasLength(1));
    expect(store.isServerBacked(store.groups.single), isTrue);
    // Explicitly confirm pre-login local-group sync opt-in is false.
    expect(await db.syncEnabled('user-1'), isFalse);

    // Go offline and add an expense + confirm received partial payment.
    online = false;
    store.setConnectivityOnline(false);

    expect(
      await store.addExpense(
        groupId: 'group-shared-1',
        description: 'Tacos',
        amountCents: 10000,
        payerId: 'user-1',
        payers: const [ExpensePayer(memberId: 'user-1', amountCents: 10000)],
        participantIds: const ['user-1', 'member-2'],
      ),
      isTrue,
    );
    expect(store.lastMutationQueuedOffline, isTrue);
    expect(
      store.balanceWith(
        store.groupById('group-shared-1'),
        store.groupById('group-shared-1').members[1],
      ),
      5000,
    );

    expect(
      await store.confirmReceivedPayment(
        groupId: 'group-shared-1',
        debtorId: 'member-2',
        amountCents: 3000,
      ),
      isTrue,
    );
    expect(store.lastMutationQueuedOffline, isTrue);
    expect(store.pendingMutationCountForGroup('group-shared-1'), 2);
    expect(
      store.balanceWith(
        store.groupById('group-shared-1'),
        store.groupById('group-shared-1').members[1],
      ),
      2000,
    );

    // Simulate full app restart while still offline.
    store.dispose();
    await db.close();

    db = await OfflineDatabase.open(databasePath: dbPath);
    client = makeClient();
    store = DemoStore.offline(client, db);
    await store.initialize();
    expect(await client.restoreSession(), isTrue);
    await store.refreshAuthentication();
    store.setConnectivityOnline(false);

    expect(store.groups, hasLength(1));
    expect(store.groupById('group-shared-1').expenses, hasLength(1));
    expect(store.groupById('group-shared-1').settlements, hasLength(1));
    expect(store.pendingMutations, hasLength(2));
    expect(
      store.balanceWith(
        store.groupById('group-shared-1'),
        store.groupById('group-shared-1').members[1],
      ),
      2000,
    );

    // Restore connectivity and flush queued mutations (without opt-in local sync).
    online = true;
    store.setConnectivityOnline(true);
    expect(await store.syncPendingMutations(), isTrue);

    expect(replayedPaths, [
      '/api/v1/groups/group-shared-1/expenses',
      '/api/v1/groups/group-shared-1/settlements/received',
    ]);
    expect(replayedKeys[0], matches(RegExp(r'^mobile-\d+-[0-9a-f]{32}$')));
    expect(replayedKeys[1], matches(RegExp(r'^mobile-\d+-[0-9a-f]{32}$')));
    expect(replayedKeys[0], isNot(replayedKeys[1]));
    expect(store.pendingMutations, isEmpty);
    expect(store.failedMutations, isEmpty);
    expect(store.groupById('group-shared-1').expenses.single.id,
        'expense-server-1');
    expect(store.groupById('group-shared-1').settlements.single.id,
        'settlement-server-1');
    expect(
      store.balanceWith(
        store.groupById('group-shared-1'),
        store.groupById('group-shared-1').members[1],
      ),
      2000,
    );

    store.dispose();
    await db.close();
    await directory.delete(recursive: true);
  });

  test(
      'reuses the exact same Idempotency-Key across transient timeout and reconnect retry',
      () async {
    final directory = await Directory.systemTemp.createTemp('vaquita-idem-');
    final db = await OfflineDatabase.open(
      databasePath: p.join(directory.path, 'app.db'),
    );
    final seenKeys = <String>[];
    var attempts = 0;
    final client = ApiClient(
      baseUrl: 'http://example.test',
      storage: _MemorySessionStorage(),
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/auth/login') {
          return _loginOk('user-1', 'Ana', 'ana@example.test');
        }
        if (request.method == 'GET' && request.url.path == '/api/v1/groups') {
          return http.Response(
            jsonEncode({
              'groups': [
                {
                  'id': 'group-personal-1',
                  'name': 'Home',
                  'emoji': '🏠',
                  'visibility': 'personal',
                  'members': [
                    {'id': 'user-1', 'user_id': 'user-1', 'name': 'Ana'},
                    {'id': 'member-2', 'name': 'Beto'},
                  ],
                  'expenses': [
                    {
                      'id': 'expense-1',
                      'description': 'Rent',
                      'amount_cents': 10000,
                      'payer_id': 'member-2',
                      'participant_ids': ['user-1', 'member-2'],
                      'created_at': DateTime.utc(2026, 11, 19).toIso8601String(),
                    }
                  ],
                  'settlements': attempts >= 3
                      ? [
                          {
                            'id': 'settlement-1',
                            'from_member_id': 'user-1',
                            'to_member_id': 'member-2',
                            'amount_cents': 2500,
                            'created_at':
                                DateTime.utc(2026, 11, 20).toIso8601String(),
                          }
                        ]
                      : <Object>[],
                }
              ],
            }),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (request.method == 'POST' &&
            request.url.path == '/api/v1/groups/group-personal-1/settlements') {
          attempts++;
          seenKeys.add(request.headers['idempotency-key'] ?? '');
          if (attempts == 1) {
            throw TimeoutException('timed out after send');
          }
          if (attempts == 2) {
            return http.Response(
              jsonEncode({'code': 'service_unavailable', 'message': 'busy'}),
              503,
            );
          }
          return http.Response(jsonEncode({'id': 'settlement-1'}), 201);
        }
        if (request.method == 'GET' && request.url.path == '/api/v1/status') {
          return http.Response(jsonEncode({'contacts': <Object>[]}), 200);
        }
        throw StateError('Unexpected request: ${request.method} ${request.url}');
      }),
    );

    final store = DemoStore.offline(client, db);
    await store.initialize();
    await client.login(email: 'ana@example.test', password: 'password');
    await store.refreshAuthentication();
    await store.load();

    // First attempt times out -> queued with the exact same key.
    expect(
      await store.settleBalance(
        groupId: 'group-personal-1',
        memberId: 'member-2',
        amountCents: 2500,
      ),
      isTrue,
    );
    expect(store.lastMutationQueuedOffline, isTrue);
    expect(store.pendingMutations, hasLength(1));

    // Second attempt hits 503 -> remains pending with the same key.
    expect(await store.syncPendingMutations(), isFalse);
    expect(store.pendingMutations, hasLength(1));

    // Third attempt succeeds -> replays the exact same key.
    expect(await store.syncPendingMutations(), isTrue);
    expect(store.pendingMutations, isEmpty);
    expect(seenKeys, hasLength(3));
    expect(seenKeys.toSet(), hasLength(1));
    expect(seenKeys.first, matches(RegExp(r'^mobile-\d+-[0-9a-f]{32}$')));

    store.dispose();
    await db.close();
    await directory.delete(recursive: true);
  });

  test(
      'load preserves groups with pending mutations while refreshing unrelated groups',
      () async {
    final directory = await Directory.systemTemp.createTemp('vaquita-merge2-');
    final db = await OfflineDatabase.open(
      databasePath: p.join(directory.path, 'app.db'),
    );
    var group2Name = 'Group 2 Initial';
    final client = ApiClient(
      baseUrl: 'http://example.test',
      storage: _MemorySessionStorage(),
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/auth/login') {
          return _loginOk('user-1', 'Ana', 'ana@example.test');
        }
        if (request.method == 'GET' && request.url.path == '/api/v1/groups') {
          return http.Response(
            jsonEncode({
              'groups': [
                {
                  'id': 'group-1',
                  'name': 'Group 1 Server',
                  'emoji': '1️⃣',
                  'visibility': 'shared',
                  'members': [
                    {'id': 'user-1', 'user_id': 'user-1', 'name': 'Ana'},
                    {'id': 'member-2', 'name': 'Beto'},
                  ],
                  'expenses': <Object>[],
                  'settlements': <Object>[],
                },
                {
                  'id': 'group-2',
                  'name': group2Name,
                  'emoji': '2️⃣',
                  'visibility': 'shared',
                  'members': [
                    {'id': 'user-1', 'user_id': 'user-1', 'name': 'Ana'},
                    {'id': 'member-2', 'name': 'Beto'},
                  ],
                  'expenses': <Object>[],
                  'settlements': <Object>[],
                },
              ],
            }),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }
        throw StateError('Unexpected request: ${request.method} ${request.url}');
      }),
    );

    final store = DemoStore.offline(client, db);
    await store.initialize();
    await client.login(email: 'ana@example.test', password: 'password');
    await store.refreshAuthentication();
    await store.load();

    store.setConnectivityOnline(false);
    await store.addExpense(
      groupId: 'group-1',
      description: 'Offline coffee',
      amountCents: 1200,
      payerId: 'user-1',
      payers: const [ExpensePayer(memberId: 'user-1', amountCents: 1200)],
      participantIds: const ['user-1', 'member-2'],
    );

    // Server updates group-2 while group-1 still has a queued offline expense.
    group2Name = 'Group 2 Updated';
    store.setConnectivityOnline(true);
    await store.load();

    expect(store.groupById('group-1').expenses, hasLength(1));
    expect(store.groupById('group-1').expenses.single.description,
        'Offline coffee');
    expect(store.groupById('group-2').name, 'Group 2 Updated');

    store.dispose();
    await db.close();
    await directory.delete(recursive: true);
  });

  test(
      'marks permanent 4xx rejection as failed without blocking other mutations and supports discard',
      () async {
    final directory = await Directory.systemTemp.createTemp('vaquita-fail-');
    final db = await OfflineDatabase.open(
      databasePath: p.join(directory.path, 'app.db'),
    );
    var group2Synced = false;
    final client = ApiClient(
      baseUrl: 'http://example.test',
      storage: _MemorySessionStorage(),
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/auth/login') {
          return _loginOk('user-1', 'Ana', 'ana@example.test');
        }
        if (request.method == 'GET' && request.url.path == '/api/v1/groups') {
          return http.Response(
            jsonEncode({
              'groups': [
                {
                  'id': 'group-1',
                  'name': 'Group 1',
                  'emoji': '1️⃣',
                  'visibility': 'shared',
                  'members': [
                    {'id': 'user-1', 'user_id': 'user-1', 'name': 'Ana'},
                    {'id': 'member-2', 'name': 'Beto'},
                  ],
                  'expenses': [
                    {
                      'id': 'expense-1',
                      'description': 'Dinner',
                      'amount_cents': 10000,
                      'payer_id': 'user-1',
                      'participant_ids': ['user-1', 'member-2'],
                      'created_at': DateTime.utc(2026, 11, 19).toIso8601String(),
                    }
                  ],
                  'settlements': <Object>[],
                },
                {
                  'id': 'group-2',
                  'name': 'Group 2',
                  'emoji': '2️⃣',
                  'visibility': 'shared',
                  'members': [
                    {'id': 'user-1', 'user_id': 'user-1', 'name': 'Ana'},
                    {'id': 'member-2', 'name': 'Beto'},
                  ],
                  'expenses': group2Synced
                      ? [
                          {
                            'id': 'expense-server-2',
                            'description': 'Snacks',
                            'amount_cents': 800,
                            'payer_id': 'user-1',
                            'participant_ids': ['user-1', 'member-2'],
                            'created_at':
                                DateTime.utc(2026, 11, 20).toIso8601String(),
                          }
                        ]
                      : <Object>[],
                  'settlements': <Object>[],
                },
              ],
            }),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (request.method == 'POST' &&
            request.url.path ==
                '/api/v1/groups/group-1/settlements/received') {
          return http.Response(
            jsonEncode({
              'code': 'validation_failed',
              'message': 'amount exceeds outstanding balance',
            }),
            422,
          );
        }
        if (request.method == 'POST' &&
            request.url.path == '/api/v1/groups/group-2/expenses') {
          group2Synced = true;
          return http.Response(jsonEncode({'id': 'expense-server-2'}), 201);
        }
        throw StateError('Unexpected request: ${request.method} ${request.url}');
      }),
    );

    final store = DemoStore.offline(client, db);
    await store.initialize();
    await client.login(email: 'ana@example.test', password: 'password');
    await store.refreshAuthentication();
    await store.load();

    store.setConnectivityOnline(false);
    await store.confirmReceivedPayment(
      groupId: 'group-1',
      debtorId: 'member-2',
      amountCents: 5000,
    );
    await store.addExpense(
      groupId: 'group-2',
      description: 'Snacks',
      amountCents: 800,
      payerId: 'user-1',
      payers: const [ExpensePayer(memberId: 'user-1', amountCents: 800)],
      participantIds: const ['user-1', 'member-2'],
    );

    store.setConnectivityOnline(true);
    expect(await store.syncPendingMutations(), isFalse);

    // Group 2 succeeded while Group 1's rejected settlement is surfaced as failed.
    expect(group2Synced, isTrue);
    expect(store.pendingMutations, isEmpty);
    expect(store.failedMutations, hasLength(1));
    expect(store.failedMutations.single.lastError, 'validation_failed');
    expect(store.groupById('group-2').expenses.single.id, 'expense-server-2');
    expect(store.groupById('group-1').settlements, hasLength(1));

    // Discarding the failed mutation removes the optimistic local settlement.
    await store.discardFailedMutation(store.failedMutations.single.id);
    expect(store.failedMutations, isEmpty);
    expect(store.groupById('group-1').settlements, isEmpty);

    store.dispose();
    await db.close();
    await directory.delete(recursive: true);
  });

  test('upgrades a version 1 SQLite database to version 2 without losing data',
      () async {
    final directory = await Directory.systemTemp.createTemp('vaquita-v1-');
    final dbPath = p.join(directory.path, 'legacy.db');

    // Create a genuine version 1 database.
    final v1 = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE groups (
            id TEXT PRIMARY KEY,
            remote_id TEXT,
            payload TEXT NOT NULL,
            revision INTEGER NOT NULL DEFAULT 1,
            synced_revision INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
      },
    );
    final legacyGroup = ExpenseGroup(
      id: 'local_group_legacy',
      name: 'Legacy group',
      emoji: '📦',
      members: const [
        Member(id: 'me', name: 'Ana'),
        Member(id: 'local_member_1', name: 'Beto'),
      ],
    );
    await v1.insert('groups', {
      'id': legacyGroup.id,
      'remote_id': null,
      'payload': jsonEncode(legacyGroup.toJson()),
      'revision': 1,
      'synced_revision': 0,
    });
    await v1.insert('settings', {
      'key': 'sync_enabled:user-1',
      'value': 'true',
    });
    await v1.close();

    // Open through OfflineDatabase (version 2) and confirm migration preserved data.
    final upgraded = await OfflineDatabase.open(databasePath: dbPath);
    final groups = await upgraded.loadGroups();
    expect(groups, hasLength(1));
    expect(groups.single.id, 'local_group_legacy');
    expect(await upgraded.syncEnabled('user-1'), isTrue);

    final mutation = PendingMutation(
      id: 'mut-1',
      accountId: 'user-1',
      groupId: 'group-1',
      operation: PendingMutation.opAddExpense,
      idempotencyKey: 'mobile-1-abc',
      payload: const {'amount_cents': 500},
      localEntityId: 'local_expense_1',
      createdAt: DateTime.utc(2026, 11, 20),
    );
    await upgraded.enqueueMutation(mutation);
    final stored = await upgraded.mutationsForAccount('user-1');
    expect(stored, hasLength(1));
    expect(stored.single.idempotencyKey, 'mobile-1-abc');

    await upgraded.close();
    await directory.delete(recursive: true);
  });

  test('isolates queued server mutations per signed-in account', () async {
    final directory = await Directory.systemTemp.createTemp('vaquita-acct-');
    final db = await OfflineDatabase.open(
      databasePath: p.join(directory.path, 'app.db'),
    );
    final syncedForAccount = <String>[];
    final client = ApiClient(
      baseUrl: 'http://example.test',
      storage: _MemorySessionStorage(),
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/auth/login') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (body['email'] == 'a@example.test') {
            return _loginOk('account-a', 'Alice', 'a@example.test');
          }
          return _loginOk('account-b', 'Bob', 'b@example.test');
        }
        if (request.url.path == '/api/v1/auth/sign-out') {
          return http.Response('', 204);
        }
        if (request.method == 'GET' && request.url.path == '/api/v1/groups') {
          return http.Response(
            jsonEncode({
              'groups': [
                {
                  'id': 'group-a',
                  'name': 'Group A',
                  'emoji': 'A',
                  'visibility': 'shared',
                  'members': [
                    {'id': 'account-a', 'user_id': 'account-a', 'name': 'Alice'},
                    {'id': 'member-2', 'name': 'Carlos'},
                  ],
                  'expenses': <Object>[],
                  'settlements': <Object>[],
                }
              ],
            }),
            200,
          );
        }
        if (request.method == 'POST' &&
            request.url.path == '/api/v1/groups/group-a/expenses') {
          syncedForAccount.add(request.headers['authorization'] ?? '');
          return http.Response(jsonEncode({'id': 'expense-a'}), 201);
        }
        throw StateError('Unexpected request: ${request.method} ${request.url}');
      }),
    );

    final store = DemoStore.offline(client, db);
    await store.initialize();
    await client.login(email: 'a@example.test', password: 'password');
    await store.refreshAuthentication();
    await store.load();

    store.setConnectivityOnline(false);
    await store.addExpense(
      groupId: 'group-a',
      description: 'Alice offline meal',
      amountCents: 2000,
      payerId: 'account-a',
      payers: const [ExpensePayer(memberId: 'account-a', amountCents: 2000)],
      participantIds: const ['account-a', 'member-2'],
    );
    expect(store.pendingMutations, hasLength(1));

    // Sign out and sign in as Account B: Account A's queue must not sync under B.
    await client.signOut();
    await store.refreshAuthentication();
    expect(store.pendingMutations, isEmpty);

    await client.login(email: 'b@example.test', password: 'password');
    await store.refreshAuthentication();
    store.setConnectivityOnline(true);
    expect(store.pendingMutations, isEmpty);
    await store.syncPendingMutations();
    expect(syncedForAccount, isEmpty);

    // Sign back in as Account A: Account A's queued mutation resumes and syncs.
    await client.signOut();
    await store.refreshAuthentication();
    await client.login(email: 'a@example.test', password: 'password');
    await store.refreshAuthentication();
    expect(store.pendingMutations, hasLength(1));
    expect(await store.syncPendingMutations(), isTrue);
    expect(syncedForAccount, ['Bearer token-account-a']);
    expect(store.pendingMutations, isEmpty);

    store.dispose();
    await db.close();
    await directory.delete(recursive: true);
  });

  testWidgets(
      'disables payment requests offline while allowing queued receipt confirmation and showing dashboard banner',
      (tester) async {
    var paymentRequestsPosted = 0;
    final client = ApiClient(
      baseUrl: 'http://example.test',
      storage: _MemorySessionStorage(),
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/auth/login') {
          return _loginOk('user-1', 'Ana', 'ana@example.test');
        }
        if (request.url.path == '/api/v1/payment-requests') {
          paymentRequestsPosted++;
          return http.Response('{}', 201);
        }
        if (request.method == 'GET' && request.url.path == '/api/v1/groups') {
          return http.Response(
            jsonEncode({
              'groups': [
                {
                  'id': 'group-1',
                  'name': 'Shared Dinner',
                  'emoji': '🍽️',
                  'visibility': 'shared',
                  'members': [
                    {'id': 'user-1', 'user_id': 'user-1', 'name': 'Ana'},
                    {'id': 'debtor-1', 'name': 'Beto'},
                  ],
                  'expenses': [
                    {
                      'id': 'expense-1',
                      'description': 'Dinner',
                      'amount_cents': 10000,
                      'payer_id': 'user-1',
                      'participant_ids': ['user-1', 'debtor-1'],
                      'created_at': DateTime.utc(2026, 11, 20).toIso8601String(),
                    }
                  ],
                  'settlements': <Object>[],
                }
              ],
            }),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }
        throw StateError('Unexpected request: ${request.method} ${request.url}');
      }),
    );

    final store = DemoStore.offline(client, null);
    addTearDown(store.dispose);
    await client.login(email: 'ana@example.test', password: 'password');
    await store.refreshAuthentication();
    await store.load();
    store.setConnectivityOnline(false);

    // Offline requestPayment is explicitly rejected and never queued.
    expect(
      await store.requestPayment(
        groupId: 'group-1',
        debtorId: 'debtor-1',
        amountCents: 5000,
      ),
      isFalse,
    );
    expect(paymentRequestsPosted, 0);
    expect(store.pendingMutations, isEmpty);

    // Open settlement sheet in group detail while offline.
    final cubit = AppCubit(store);
    addTearDown(cubit.close);
    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GroupDetailScreen(store: store, groupId: 'group-1'),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-settlement-debtor-1')));
    await tester.pumpAndSettle();

    final requestButton = tester.widget<OutlinedButton>(
      find.byKey(const Key('request-debtor-1')),
    );
    expect(requestButton.onPressed, isNull);
    expect(
      find.text('Las solicitudes de pago requieren conexión a internet.'),
      findsOneWidget,
    );

    // Confirming payment received works offline and shows the offline-queued snackbar.
    await tester.ensureVisible(find.byKey(const Key('settle-debtor-1')));
    await tester.tap(find.byKey(const Key('settle-debtor-1')));
    await tester.pumpAndSettle();

    expect(
      find.text('Guardado sin conexión. Se sincronizará al volver internet.'),
      findsOneWidget,
    );
    expect(store.pendingMutations, hasLength(1));

    // Dashboard displays the pending sync banner and per-group pending count.
    await tester.pumpWidget(VaquitaApp(store: store));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pending-sync-banner')), findsOneWidget);
    expect(find.text('1 pendiente(s)'), findsOneWidget);
  });
}
