import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vaquita_mx/src/api_client.dart';
import 'package:vaquita_mx/src/models.dart';
import 'package:vaquita_mx/src/offline_database.dart';
import 'package:vaquita_mx/src/store.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('persists group history and keeps per-account sync consent', () async {
    final directory = await Directory.systemTemp.createTemp('vaquita-offline-');
    final path = p.join(directory.path, 'test.db');
    var database = await OfflineDatabase.open(databasePath: path);
    final group = ExpenseGroup(
      id: 'local_group_1',
      name: 'Dinner',
      emoji: '🍲',
      members: const [
        Member(id: 'me', name: 'Ana'),
        Member(id: 'local_member_1', name: 'Beto'),
      ],
      expenses: [
        Expense(
          id: 'local_expense_1',
          description: 'Soup',
          amountCents: 101,
          payerId: 'me',
          payers: const [ExpensePayer(memberId: 'me', amountCents: 101)],
          participantIds: const ['me', 'local_member_1'],
          splitMode: 'exact',
          shares: const {'me': 50, 'local_member_1': 51},
          splitOverpayment: false,
          createdAt: DateTime.utc(2026, 11, 7),
        ),
      ],
      settlements: [
        Settlement(
          id: 'local_settlement_1',
          fromMemberId: 'local_member_1',
          toMemberId: 'me',
          amountCents: 20,
          createdAt: DateTime.utc(2026, 11, 8),
        ),
      ],
    );

    await database.saveGroup(group);
    expect(await database.isPending(group.id), isTrue);
    expect(await database.revision(group.id), 1);
    expect(await database.syncEnabled('account-1'), isFalse);
    await database.setSyncEnabled('account-1', true);
    expect(await database.syncEnabled('account-1'), isTrue);
    await database.close();

    database = await OfflineDatabase.open(databasePath: path);
    final restored = (await database.loadGroups()).single;
    expect(restored.id, group.id);
    expect(restored.expenses.single.amountCents, 101);
    expect(restored.expenses.single.shares, {'me': 50, 'local_member_1': 51});
    expect(restored.settlements.single.amountCents, 20);
    expect(await database.syncEnabled('account-1'), isTrue);
    expect(await database.syncEnabled('account-2'), isFalse);

    await database.markSynced(group.id, 'remote-group-1', 1);
    await database.close();
    database = await OfflineDatabase.open(databasePath: path);
    expect(await database.syncedGroupIds(), {group.id});
    expect(await database.isPending(group.id), isFalse);
    await database.saveGroup(
      ExpenseGroup(
        id: group.id,
        name: 'Dinner edited offline',
        emoji: group.emoji,
        members: group.members,
        expenses: group.expenses,
        settlements: group.settlements,
      ),
    );
    expect(await database.isPending(group.id), isTrue);
    expect(await database.revision(group.id), 2);
    expect(await database.syncedGroupIds(), isEmpty);

    await database.close();
    await directory.delete(recursive: true);
  });

  test('creates and allocates an expense locally without an account', () async {
    final store = DemoStore.offline(
      ApiClient(baseUrl: 'http://example.test'),
      null,
    );
    await store.createGroup(
      name: 'Dinner',
      emoji: '🍲',
      memberNames: const ['Beto'],
    );
    final group = store.groups.single;
    final guest = group.members[1];

    await store.addExpense(
      groupId: group.id,
      description: 'Soup',
      amountCents: 101,
      payerId: 'me',
      payers: const [ExpensePayer(memberId: 'me', amountCents: 101)],
      participantIds: ['me', guest.id],
      splitMode: 'exact',
      shares: [
        const ExpenseShare(memberId: 'me', amountCents: 50),
        ExpenseShare(memberId: guest.id, amountCents: 51),
      ],
      splitOverpayment: false,
    );

    expect(store.currentUserBalance(group), 51);
    expect(store.balanceWith(group, guest), 51);
    store.dispose();
  });

  test('confirms and persists a received payment in a local group', () async {
    final directory = await Directory.systemTemp.createTemp('vaquita-payment-');
    final path = p.join(directory.path, 'test.db');
    final database = await OfflineDatabase.open(databasePath: path);
    final store = DemoStore.offline(
      ApiClient(baseUrl: 'http://example.test'),
      database,
    );
    await store.createGroup(
      name: 'Dinner',
      emoji: '🍲',
      memberNames: const ['Beto'],
      visibility: 'shared',
      salarySplitEnabled: true,
    );
    final group = store.groups.single;
    final debtor = group.members[1];

    expect(group.visibility, 'personal');
    expect(group.salarySplitEnabled, isFalse);
    expect(store.canRequestPayment(group), isFalse);

    await store.addExpense(
      groupId: group.id,
      description: 'Soup',
      amountCents: 1000,
      payerId: 'me',
      payers: const [ExpensePayer(memberId: 'me', amountCents: 1000)],
      participantIds: ['me', debtor.id],
    );
    expect(store.balanceWith(group, debtor), 500);

    expect(
      await store.confirmReceivedPayment(
        groupId: group.id,
        debtorId: debtor.id,
        amountCents: 250,
      ),
      isTrue,
    );
    expect(group.settlements.single.fromMemberId, debtor.id);
    expect(group.settlements.single.toMemberId, 'me');
    expect(group.settlements.single.amountCents, 250);
    expect(store.balanceWith(group, debtor), 250);
    await database.close();
    store.dispose();

    final reopened = await OfflineDatabase.open(databasePath: path);
    final restored = (await reopened.loadGroups()).single;
    expect(restored.settlements.single.amountCents, 250);
    expect(restored.settlements.single.fromMemberId, debtor.id);
    await reopened.close();
    await directory.delete(recursive: true);
  });

  test('sync retries a received local settlement after signing in again',
      () async {
    final directory = await Directory.systemTemp.createTemp('vaquita-sync-');
    final path = p.join(directory.path, 'test.db');
    final database = await OfflineDatabase.open(databasePath: path);
    final syncBodies = <String>[];
    var syncAttempts = 0;
    final client = ApiClient(
      baseUrl: 'http://example.test',
      storage: _TestSessionStorage(),
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/auth/login') {
          return http.Response(
            jsonEncode({
              'access_token': 'access-token',
              'refresh_token': 'refresh-token',
              'user': {
                'id': 'account-1',
                'name': 'Ana',
                'email': 'ana@example.test',
                'phone': '',
                'salary_cents': 0,
              },
            }),
            200,
          );
        }
        if (request.url.path == '/api/v1/auth/sign-out') {
          return http.Response('', 204);
        }
        if (request.url.path == '/api/v1/offline-sync/groups') {
          syncAttempts++;
          syncBodies.add(request.body);
          if (syncAttempts == 1) {
            return http.Response(
              jsonEncode({
                'error': {'code': 'server_unavailable', 'message': 'retry'}
              }),
              503,
            );
          }
          final input = jsonDecode(request.body) as Map<String, dynamic>;
          final syncedGroup =
              (input['groups'] as List<dynamic>).single as Map<String, dynamic>;
          final settlements = syncedGroup['settlements'] as List<dynamic>;
          expect(settlements, hasLength(1));
          expect(settlements.single, containsPair('amount_cents', 250));
          return http.Response(
            jsonEncode({
              'groups': [
                {
                  'local_group_id': syncedGroup['id'],
                  'remote_group_id': syncedGroup['id'],
                }
              ],
            }),
            200,
          );
        }
        if (request.url.path == '/api/v1/groups') {
          return http.Response(jsonEncode({'groups': <Object>[]}), 200);
        }
        throw StateError(
            'Unexpected request: ${request.method} ${request.url}');
      }),
    );
    final store = DemoStore.offline(client, database);
    await store.createGroup(name: 'Dinner', memberNames: const ['Beto']);
    final group = store.groups.single;
    final debtor = group.members[1];
    await store.addExpense(
      groupId: group.id,
      description: 'Soup',
      amountCents: 1000,
      payerId: 'me',
      payers: const [ExpensePayer(memberId: 'me', amountCents: 1000)],
      participantIds: ['me', debtor.id],
    );
    await store.confirmReceivedPayment(
      groupId: group.id,
      debtorId: debtor.id,
      amountCents: 250,
    );

    await client.login(email: 'ana@example.test', password: 'password');
    expect(await store.syncLocalGroups(enable: true), isFalse);
    await client.signOut();
    expect(store.isAuthenticated, isFalse);
    await client.login(email: 'ana@example.test', password: 'password');
    expect(await store.syncLocalGroups(), isTrue);

    expect(syncAttempts, 2);
    expect(syncBodies[1], syncBodies[0]);
    expect(await database.isPending(group.id), isFalse);

    store.dispose();
    await database.close();
    await directory.delete(recursive: true);
  });

  test('keeps pending local group data authoritative until sync completes',
      () async {
    final directory = await Directory.systemTemp.createTemp('vaquita-merge-');
    final database = await OfflineDatabase.open(
      databasePath: p.join(directory.path, 'test.db'),
    );
    late String groupId;
    late List<Member> members;
    final client = ApiClient(
      baseUrl: 'http://example.test',
      storage: _TestSessionStorage(),
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/auth/login') {
          return http.Response(
            jsonEncode({
              'access_token': 'access-token',
              'refresh_token': 'refresh-token',
              'user': {
                'id': 'account-1',
                'name': 'Ana',
                'email': 'ana@example.test',
                'phone': '',
                'salary_cents': 0,
              },
            }),
            200,
          );
        }
        if (request.url.path == '/api/v1/groups') {
          return http.Response(
            jsonEncode({
              'groups': [
                {
                  'id': groupId,
                  'name': 'Server copy',
                  'emoji': 'S',
                  'members': members.map((member) => member.toJson()).toList(),
                  'expenses': <Object>[],
                  'settlements': <Object>[],
                }
              ],
            }),
            200,
          );
        }
        throw StateError(
            'Unexpected request: ${request.method} ${request.url}');
      }),
    );
    final store = DemoStore.offline(client, database);
    await store.createGroup(
      name: 'Local copy',
      emoji: 'L',
      memberNames: const ['Beto'],
    );
    final group = store.groups.single;
    groupId = group.id;
    members = group.members;
    await database.markSynced(group.id, group.id, 1);
    await database.saveGroup(
      ExpenseGroup(
        id: group.id,
        name: group.name,
        emoji: group.emoji,
        members: group.members,
      ),
    );
    await client.login(email: 'ana@example.test', password: 'password');

    await store.load();
    expect(store.groups.single.name, 'Local copy');
    expect(await database.isPending(group.id), isTrue);

    await database.markSynced(
        group.id, group.id, await database.revision(group.id));
    await store.load();
    expect(store.groups.single.name, 'Server copy');
    expect(await database.isPending(group.id), isFalse);

    store.dispose();
    await database.close();
    await directory.delete(recursive: true);
  });
}

class _TestSessionStorage implements SessionStorage {
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
