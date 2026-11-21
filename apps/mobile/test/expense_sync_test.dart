import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vaquita_mx/src/api_client.dart';
import 'package:vaquita_mx/src/models.dart';
import 'package:vaquita_mx/src/store.dart';

void main() {
  test('keeps an expense in the API after refreshing a synced group', () async {
    final serverExpenses = <Map<String, dynamic>>[];
    var expensePosts = 0;
    final client = ApiClient(
      baseUrl: 'http://example.test',
      client: MockClient((request) async {
        if (request.method == 'POST' &&
            request.url.path == '/api/v1/auth/login') {
          return http.Response(
            jsonEncode({
              'access_token': 'access-token',
              'refresh_token': 'refresh-token',
              'user': {
                'id': 'user-1',
                'name': 'You',
                'email': 'you@example.test',
                'phone': '',
                'salary_cents': 0,
              },
            }),
            200,
          );
        }
        if (request.method == 'GET' && request.url.path == '/api/v1/groups') {
          return http.Response(
            jsonEncode({
              'groups': [
                {
                  'id': 'group-1',
                  'name': 'Group',
                  'emoji': 'G',
                  'visibility': 'shared',
                  'members': [
                    {'id': 'user-1', 'user_id': 'user-1', 'name': 'You'},
                    {'id': 'member-1', 'name': 'Ana'},
                  ],
                  'expenses': serverExpenses,
                  'settlements': <Object>[],
                  'balances': <String, int>{},
                  'payment_relations': <Object>[],
                }
              ],
            }),
            200,
          );
        }
        if (request.method == 'POST' &&
            request.url.path == '/api/v1/groups/group-1/expenses') {
          expensePosts++;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          serverExpenses.add({
            'id': 'expense-1',
            'description': body['description'],
            'amount_cents': body['amount_cents'],
            'payer_id': body['payer_id'],
            'payers': body['payers'],
            'participant_ids': body['participant_ids'],
            'split_mode': body['split_mode'],
            'shares': {'user-1': 5000, 'member-1': 5000},
            'created_at': DateTime.utc(2026, 11, 8).toIso8601String(),
          });
          return http.Response(jsonEncode({'id': 'expense-1'}), 201);
        }
        throw StateError(
            'Unexpected request: ${request.method} ${request.url}');
      }),
    );
    final store = DemoStore.offline(client, null);
    addTearDown(store.dispose);
    await client.login(email: 'you@example.test', password: 'password');
    await store.load();

    expect(
      await store.addExpense(
        groupId: 'group-1',
        description: 'Dinner',
        amountCents: 10000,
        payerId: 'user-1',
        payers: const [ExpensePayer(memberId: 'user-1', amountCents: 10000)],
        participantIds: const ['user-1', 'member-1'],
      ),
      isTrue,
    );
    await store.load();

    expect(expensePosts, 1);
    expect(store.groupById('group-1').expenses, hasLength(1));
    expect(store.groupById('group-1').expenses.single.description, 'Dinner');
  });
}
