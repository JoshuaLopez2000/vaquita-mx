import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vaquita_mx/src/api_client.dart';
import 'package:vaquita_mx/src/models.dart';

void main() {
  test('loads groups from the API', () async {
    final client = ApiClient(
      baseUrl: 'http://example.test/',
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/groups');
        return http.Response(
          jsonEncode({
            'groups': [
              {
                'id': 'group-1',
                'name': 'Trip',
                'balances': {'me': 400, 'ana': -400},
                'emoji': '🏖️',
                'members': [
                  {'id': 'me', 'name': 'You'},
                ],
                'expenses': <Object>[],
                'settlements': <Object>[],
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final groups = await client.listGroups();

    expect(groups, hasLength(1));
    expect(groups.single.name, 'Trip');
    expect(groups.single.balances['ana'], -400);
    expect(groups.single.members.single.id, 'me');
  });

  test('sends a group mutation as JSON', () async {
    final client = ApiClient(
      baseUrl: 'http://example.test',
      client: MockClient((request) async {
        expect(request.method, 'POST');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['name'], 'Roommates');
        expect(body['member_names'], ['Ana']);
        return http.Response('{}', 201);
      }),
    );

    await client.createGroup(name: 'Roommates', memberNames: ['Ana']);
  });

  test('sends a received-payment confirmation with an idempotency key',
      () async {
    final client = ApiClient(
      baseUrl: 'http://example.test',
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(
          request.url.path,
          '/api/v1/groups/group-1/settlements/received',
        );
        expect(request.headers['idempotency-key'], isNotEmpty);
        expect(jsonDecode(request.body), {
          'debtor_member_id': 'member-2',
          'amount_cents': 1250,
        });
        return http.Response('{}', 201);
      }),
    );

    await client.confirmReceivedPayment(
      groupId: 'group-1',
      debtorId: 'member-2',
      amountCents: 1250,
    );
  });

  test('forwards caller-supplied idempotency keys on expense and settlements',
      () async {
    final received = <String, String?>{};
    final client = ApiClient(
      baseUrl: 'http://example.test',
      client: MockClient((request) async {
        received[request.url.path] = request.headers['idempotency-key'];
        return http.Response('{}', 201);
      }),
    );

    await client.addExpense(
      groupId: 'group-1',
      description: 'Coffee',
      amountCents: 900,
      payerId: 'user-1',
      payers: const [ExpensePayer(memberId: 'user-1', amountCents: 900)],
      participantIds: const ['user-1', 'member-2'],
      idempotencyKey: 'stable-expense-key',
    );
    await client.settleBalance(
      groupId: 'group-1',
      memberId: 'member-2',
      amountCents: 450,
      idempotencyKey: 'stable-settlement-key',
    );
    await client.confirmReceivedPayment(
      groupId: 'group-1',
      debtorId: 'member-2',
      amountCents: 450,
      idempotencyKey: 'stable-received-key',
    );

    expect(received, {
      '/api/v1/groups/group-1/expenses': 'stable-expense-key',
      '/api/v1/groups/group-1/settlements': 'stable-settlement-key',
      '/api/v1/groups/group-1/settlements/received': 'stable-received-key',
    });
  });

  test('syncs only supported local group fields and returns ID mappings',
      () async {
    final client = ApiClient(
      baseUrl: 'http://example.test',
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/offline-sync/groups');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final group =
            (body['groups'] as List<dynamic>).single as Map<String, dynamic>;
        expect(group.keys.toSet(), {
          'id',
          'name',
          'emoji',
          'visibility',
          'salary_split_enabled',
          'members',
          'expenses',
          'settlements',
        });
        expect((group['expenses'] as List<dynamic>).single,
            containsPair('amount_cents', 101));
        return http.Response(
          jsonEncode({
            'groups': [
              {
                'local_group_id': 'local_group_1',
                'remote_group_id': 'local_group_1',
              }
            ],
          }),
          200,
        );
      }),
    );

    final ids = await client.syncLocalGroups([
      ExpenseGroup(
        id: 'local_group_1',
        name: 'Offline group',
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
            createdAt: DateTime.utc(2026, 11, 7),
          ),
        ],
      ),
    ]);

    expect(ids, {'local_group_1': 'local_group_1'});
  });

  test('sends exact participant shares separately from payer contributions',
      () async {
    final client = ApiClient(
      baseUrl: 'http://example.test',
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(request.url.path, '/api/v1/groups/group-1/expenses');
        expect(body['payers'], [
          {'member_id': 'ana', 'amount_cents': 7000},
          {'member_id': 'diego', 'amount_cents': 3000},
        ]);
        expect(body['shares'], [
          {'member_id': 'ana', 'amount_cents': 1000},
          {'member_id': 'diego', 'amount_cents': 9000},
        ]);
        expect(body['split_mode'], 'exact');
        expect(body['split_overpayment'], isFalse);
        return http.Response('{}', 201);
      }),
    );

    await client.addExpense(
      groupId: 'group-1',
      description: 'Dinner',
      amountCents: 10000,
      payerId: 'ana',
      payers: const [
        ExpensePayer(memberId: 'ana', amountCents: 7000),
        ExpensePayer(memberId: 'diego', amountCents: 3000),
      ],
      participantIds: const ['ana', 'diego'],
      splitMode: 'exact',
      shares: const [
        ExpenseShare(memberId: 'ana', amountCents: 1000),
        ExpenseShare(memberId: 'diego', amountCents: 9000),
      ],
      splitOverpayment: false,
    );
  });

  test('parses stable API error codes, fields, and correlation IDs', () async {
    final client = ApiClient(
      baseUrl: 'http://example.test',
      client: MockClient((request) async => http.Response(
            jsonEncode({
              'version': '1',
              'code': 'validation_failed',
              'message': 'The wording may change.',
              'fields': {'name': 'required'},
              'error': 'The wording may change.',
            }),
            422,
            headers: const {'x-correlation-id': 'mobile-test-123'},
          )),
    );

    try {
      await client.createGroup(name: '', memberNames: const []);
      fail('expected ApiException');
    } on ApiException catch (error) {
      expect(error.code, 'validation_failed');
      expect(error.message, 'The wording may change.');
      expect(error.fields, {'name': 'required'});
      expect(error.correlationId, 'mobile-test-123');
    }
  });

  test('sends login credentials and keeps the rotating session', () async {
    final client = ApiClient(
      baseUrl: 'http://example.test',
      client: MockClient((request) async {
        expect(request.url.path, '/api/v1/auth/login');
        expect(jsonDecode(request.body),
            {'email': 'ana@example.com', 'password': 'password1'});
        return http.Response(
            jsonEncode({
              'access_token': 'access-token',
              'refresh_token': 'refresh-token',
              'user': {
                'id': 'user-1',
                'name': 'Ana',
                'email': 'ana@example.com',
                'phone': '+525511112222',
              }
            }),
            200);
      }),
    );

    await client.login(email: 'ana@example.com', password: 'password1');
    expect(client.userId, 'user-1');
  });

  test('shares one transparent refresh across concurrent requests', () async {
    var refreshCalls = 0;
    final storage = MemorySessionStorage();
    final client = ApiClient(
      baseUrl: 'http://example.test',
      storage: storage,
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/auth/login') {
          return sessionResponse('access-old', 'refresh-old');
        }
        if (request.url.path == '/api/v1/auth/refresh') {
          refreshCalls++;
          expect(jsonDecode(request.body), {'refresh_token': 'refresh-old'});
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return sessionResponse('access-new', 'refresh-new');
        }
        if (request.url.path == '/api/v1/groups') {
          if (request.headers['authorization'] == 'Bearer access-old') {
            return http.Response(
                jsonEncode({
                  'version': '1',
                  'code': 'authentication_required',
                  'message': 'Changed wording',
                  'error': 'Changed wording',
                }),
                401);
          }
          expect(request.headers['authorization'], 'Bearer access-new');
          return http.Response(jsonEncode({'groups': <Object>[]}), 200);
        }
        return http.Response(jsonEncode({'error': 'unexpected'}), 500);
      }),
    );

    await client.login(email: 'ana@example.com', password: 'password1');
    await client.persistSession();
    await Future.wait([client.listGroups(), client.listGroups()]);

    expect(refreshCalls, 1);
    expect(storage.values['session_token'], 'access-new');
    expect(storage.values['refresh_token'], 'refresh-new');
  });

  test('restores a secure session and clears it after refresh rejection',
      () async {
    final storage = MemorySessionStorage({
      'session_token': 'expired-access',
      'refresh_token': 'invalid-refresh',
      'session_user': jsonEncode({
        'id': 'user-1',
        'name': 'Ana',
        'email': 'ana@example.com',
        'phone': '+525511112222',
      }),
    });
    var invalidated = false;
    final client = ApiClient(
      baseUrl: 'http://example.test',
      storage: storage,
      onSessionInvalidated: () => invalidated = true,
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/groups') {
          expect(request.headers['authorization'], 'Bearer expired-access');
          return http.Response(
              jsonEncode({
                'version': '1',
                'code': 'authentication_required',
                'message': 'Changed wording',
                'error': 'Changed wording',
              }),
              401);
        }
        expect(request.url.path, '/api/v1/auth/refresh');
        return http.Response(
            jsonEncode({
              'version': '1',
              'code': 'invalid_refresh_token',
              'message': 'Changed refresh wording',
              'error': 'Changed refresh wording',
            }),
            401);
      }),
    );

    expect(await client.restoreSession(), isTrue);
    await expectLater(client.listGroups(), throwsA(isA<ApiException>()));

    expect(invalidated, isTrue);
    expect(storage.values, isEmpty);
    expect(client.userId, isNull);
  });

  test('signs out through the server and clears secure storage', () async {
    final storage = MemorySessionStorage();
    final paths = <String>[];
    final client = ApiClient(
      baseUrl: 'http://example.test',
      storage: storage,
      client: MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.path == '/api/v1/auth/login') {
          return sessionResponse('access-token', 'refresh-token');
        }
        expect(request.headers['authorization'], 'Bearer access-token');
        return http.Response('', 204);
      }),
    );

    await client.login(email: 'ana@example.com', password: 'password1');
    await client.persistSession();
    await client.signOut(allDevices: true);

    expect(paths, contains('/api/v1/auth/sign-out-all'));
    expect(storage.values, isEmpty);
    expect(client.userId, isNull);
  });

  test('loads invitations with compact group payloads', () async {
    final client = ApiClient(
      baseUrl: 'http://example.test',
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/group-invitations');
        return http.Response(
          jsonEncode({
            'invitations': [
              {
                'group': {
                  'id': 'group-1',
                  'name': 'Beach trip',
                  'emoji': '🏖️',
                  'visibility': 'shared',
                  'salary_split_enabled': false,
                },
                'member': {'id': 'member-1', 'name': 'Diego'},
              }
            ]
          }),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final invitations = await client.invitations();

    expect(invitations, hasLength(1));
    expect(invitations.single.group.members, isEmpty);
    expect(invitations.single.group.name, 'Beach trip');
  });
}

http.Response sessionResponse(String accessToken, String refreshToken) =>
    http.Response(
      jsonEncode({
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'access_expires_at': '2026-09-30T20:00:00Z',
        'refresh_expires_at': '2026-10-30T20:00:00Z',
        'user': {
          'id': 'user-1',
          'name': 'Ana',
          'email': 'ana@example.com',
          'phone': '+525511112222',
        }
      }),
      200,
      headers: const {'content-type': 'application/json'},
    );

class MemorySessionStorage implements SessionStorage {
  MemorySessionStorage([Map<String, String>? initial]) : values = {...?initial};

  final Map<String, String> values;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
