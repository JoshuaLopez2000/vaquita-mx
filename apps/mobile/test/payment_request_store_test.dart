import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vaquita_mx/l10n/app_localizations.dart';
import 'package:vaquita_mx/src/api_client.dart';
import 'package:vaquita_mx/src/features/app/application/app_cubit.dart';
import 'package:vaquita_mx/src/group_detail_screen.dart';
import 'package:vaquita_mx/src/models.dart';
import 'package:vaquita_mx/src/store.dart';

Future<DemoStore> _remoteStore(
  Future<http.Response> Function(http.Request) handler, {
  bool offlineFirst = false,
  String visibility = 'shared',
  bool currentUserOwes = false,
}) async {
  final client = ApiClient(
    baseUrl: 'http://example.test',
    client: MockClient(handler),
  );
  await client.login(email: 'you@example.test', password: 'password');
  final store =
      offlineFirst ? DemoStore.offline(client, null) : DemoStore.remote(client);
  store.groups.add(
    ExpenseGroup(
      id: 'group-1',
      name: 'Group',
      emoji: 'G',
      visibility: visibility,
      members: const [
        Member(id: 'user-1', userId: 'user-1', name: 'You'),
        Member(id: 'debtor-1', name: 'Ana'),
      ],
      balances: currentUserOwes
          ? const {'user-1': 12500, 'debtor-1': -12500}
          : const {'user-1': -12500, 'debtor-1': 12500},
      paymentRelations: [
        PaymentRelation(
          fromMemberId: currentUserOwes ? 'user-1' : 'debtor-1',
          toMemberId: currentUserOwes ? 'debtor-1' : 'user-1',
          amountCents: 12500,
        ),
      ],
    ),
  );
  return store;
}

Future<http.Response> _loginResponse(http.Request request) async {
  if (request.method == 'POST' && request.url.path == '/api/v1/auth/login') {
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
  throw StateError('Unexpected request: ${request.method} ${request.url.path}');
}

Future<void> _pumpGroupDetail(WidgetTester tester, DemoStore store) async {
  await tester.pumpWidget(
    BlocProvider(
      create: (_) => AppCubit(store),
      child: MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: GroupDetailScreen(store: store, groupId: 'group-1'),
      ),
    ),
  );
  await tester.tap(find.text('Solicitar'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('creates a payment request with a valid idempotency key',
      (tester) async {
    var requestCount = 0;
    final store = await _remoteStore((request) async {
      requestCount++;
      if (request.url.path == '/api/v1/auth/login') {
        return _loginResponse(request);
      }
      if (request.method == 'POST' &&
          request.url.path == '/api/v1/payment-requests') {
        expect(
          request.headers['idempotency-key'],
          matches(RegExp(r'^mobile-\d+-[0-9a-f]{32}$')),
        );
        expect(
          jsonDecode(request.body),
          {
            'group_id': 'group-1',
            'debtor_id': 'debtor-1',
            'amount_cents': 12500,
            'currency': 'MXN',
            'description': 'Group balance settlement',
          },
        );
        return http.Response(jsonEncode({'id': 'request-1'}), 201);
      }
      if (request.method == 'GET' && request.url.path == '/api/v1/groups') {
        return http.Response(
          jsonEncode({
            'groups': [
              {
                'id': 'group-1',
                'name': 'Group',
                'emoji': 'G',
                'members': [
                  {'id': 'user-1', 'user_id': 'user-1', 'name': 'You'},
                  {'id': 'debtor-1', 'name': 'Ana'},
                ],
                'balances': {'user-1': -12500, 'debtor-1': 12500},
                'payment_relations': [
                  {
                    'from_member_id': 'debtor-1',
                    'to_member_id': 'user-1',
                    'amount_cents': 12500,
                  },
                ],
                'expenses': <Object>[],
                'settlements': <Object>[],
              },
            ],
          }),
          200,
        );
      }
      return http.Response('{}', 404);
    });
    addTearDown(store.dispose);

    await _pumpGroupDetail(tester, store);
    await tester.ensureVisible(find.byKey(const Key('request-debtor-1')));
    await tester.tap(find.byKey(const Key('request-debtor-1')));
    await tester.pumpAndSettle();

    expect(find.text('Solicitud de pago creada.'), findsOneWidget);
    expect(requestCount, 3);
  });

  testWidgets('refreshes shared-group balance after confirming receipt',
      (tester) async {
    var receiptConfirmed = false;
    final store = await _remoteStore((request) async {
      if (request.url.path == '/api/v1/auth/login') {
        return _loginResponse(request);
      }
      if (request.method == 'POST' &&
          request.url.path == '/api/v1/groups/group-1/settlements/received') {
        receiptConfirmed = true;
        return http.Response('{}', 201);
      }
      if (request.method == 'GET' && request.url.path == '/api/v1/groups') {
        final group = {
          'id': 'group-1',
          'name': 'Group',
          'emoji': 'G',
          'visibility': 'shared',
          'members': [
            {'id': 'user-1', 'user_id': 'user-1', 'name': 'You'},
            {'id': 'debtor-1', 'name': 'Ana'},
          ],
          'balances': receiptConfirmed
              ? {'user-1': 0, 'debtor-1': 0}
              : {'user-1': -12500, 'debtor-1': 12500},
          'payment_relations': receiptConfirmed
              ? <Object>[]
              : [
                  {
                    'from_member_id': 'debtor-1',
                    'to_member_id': 'user-1',
                    'amount_cents': 12500,
                  }
                ],
          'expenses': <Object>[],
          'settlements': receiptConfirmed
              ? [
                  {
                    'id': 'settlement-1',
                    'from_member_id': 'debtor-1',
                    'to_member_id': 'user-1',
                    'amount_cents': 12500,
                    'created_at': DateTime.utc(2026, 11, 8).toIso8601String(),
                  }
                ]
              : <Object>[],
        };
        return http.Response(
            jsonEncode({
              'groups': [group]
            }),
            200);
      }
      if (request.method == 'GET' && request.url.path == '/api/v1/status') {
        return http.Response(jsonEncode({'contacts': <Object>[]}), 200);
      }
      throw StateError('Unexpected request: ${request.method} ${request.url}');
    });
    addTearDown(store.dispose);
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
    await tester.ensureVisible(find.byKey(const Key('settle-debtor-1')));
    await tester.tap(find.byKey(const Key('settle-debtor-1')));
    await tester.pumpAndSettle();

    expect(receiptConfirmed, isTrue);
    expect(
        store.balanceWith(
            store.groupById('group-1'), store.groupById('group-1').members[1]),
        0);
    expect(find.byKey(const Key('open-settlement-debtor-1')), findsNothing);
  });

  test('posts shared-group confirmation from a web-style offline store',
      () async {
    var confirmed = false;
    final store = await _remoteStore((request) async {
      if (request.url.path == '/api/v1/auth/login') {
        return _loginResponse(request);
      }
      if (request.method == 'POST' &&
          request.url.path == '/api/v1/groups/group-1/settlements/received') {
        confirmed = true;
        return http.Response('{}', 201);
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
                  {'id': 'debtor-1', 'name': 'Ana'},
                ],
                'balances': confirmed
                    ? {'user-1': 0, 'debtor-1': 0}
                    : {'user-1': -12500, 'debtor-1': 12500},
                'payment_relations': confirmed
                    ? <Object>[]
                    : [
                        {
                          'from_member_id': 'debtor-1',
                          'to_member_id': 'user-1',
                          'amount_cents': 12500,
                        }
                      ],
                'expenses': [
                  {
                    'id': 'expense-1',
                    'description': 'Dinner',
                    'amount_cents': 25000,
                    'payer_id': 'user-1',
                    'participant_ids': ['user-1', 'debtor-1'],
                    'created_at': DateTime.utc(2026, 11, 7).toIso8601String(),
                  }
                ],
                'settlements': confirmed
                    ? [
                        {
                          'id': 'settlement-1',
                          'from_member_id': 'debtor-1',
                          'to_member_id': 'user-1',
                          'amount_cents': 12500,
                          'created_at':
                              DateTime.utc(2026, 11, 8).toIso8601String(),
                        }
                      ]
                    : <Object>[],
              }
            ],
          }),
          200,
        );
      }
      if (request.method == 'GET' && request.url.path == '/api/v1/status') {
        return http.Response(jsonEncode({'contacts': <Object>[]}), 200);
      }
      throw StateError('Unexpected request: ${request.method} ${request.url}');
    }, offlineFirst: true);
    addTearDown(store.dispose);
    final debtor = store.groupById('group-1').members[1];

    expect(
      await store.confirmReceivedPayment(
        groupId: 'group-1',
        debtorId: debtor.id,
        amountCents: 12500,
      ),
      isTrue,
    );

    expect(confirmed, isTrue);
    expect(store.balanceWith(store.groupById('group-1'), debtor), 0);
    expect(store.groupById('group-1').settlements, hasLength(1));
  });

  test('posts personal-group settlement from a web-style offline store',
      () async {
    var settled = false;
    final store = await _remoteStore((request) async {
      if (request.url.path == '/api/v1/auth/login') {
        return _loginResponse(request);
      }
      if (request.method == 'POST' &&
          request.url.path == '/api/v1/groups/group-1/settlements') {
        settled = true;
        return http.Response('{}', 201);
      }
      if (request.method == 'GET' && request.url.path == '/api/v1/groups') {
        return http.Response(
          jsonEncode({
            'groups': [
              {
                'id': 'group-1',
                'name': 'Group',
                'emoji': 'G',
                'visibility': 'personal',
                'members': [
                  {'id': 'user-1', 'user_id': 'user-1', 'name': 'You'},
                  {'id': 'debtor-1', 'name': 'Ana'},
                ],
                'balances': settled
                    ? {'user-1': 0, 'debtor-1': 0}
                    : {'user-1': 12500, 'debtor-1': -12500},
                'payment_relations': settled
                    ? <Object>[]
                    : [
                        {
                          'from_member_id': 'user-1',
                          'to_member_id': 'debtor-1',
                          'amount_cents': 12500,
                        }
                      ],
                'expenses': [
                  {
                    'id': 'expense-1',
                    'description': 'Dinner',
                    'amount_cents': 25000,
                    'payer_id': 'debtor-1',
                    'participant_ids': ['user-1', 'debtor-1'],
                    'created_at': DateTime.utc(2026, 11, 7).toIso8601String(),
                  }
                ],
                'settlements': settled
                    ? [
                        {
                          'id': 'settlement-1',
                          'from_member_id': 'user-1',
                          'to_member_id': 'debtor-1',
                          'amount_cents': 12500,
                          'created_at':
                              DateTime.utc(2026, 11, 8).toIso8601String(),
                        }
                      ]
                    : <Object>[],
              }
            ],
          }),
          200,
        );
      }
      if (request.method == 'GET' && request.url.path == '/api/v1/status') {
        return http.Response(jsonEncode({'contacts': <Object>[]}), 200);
      }
      throw StateError('Unexpected request: ${request.method} ${request.url}');
    }, offlineFirst: true, visibility: 'personal', currentUserOwes: true);
    addTearDown(store.dispose);
    final member = store.groupById('group-1').members[1];

    expect(
      await store.settleBalance(
        groupId: 'group-1',
        memberId: member.id,
        amountCents: 12500,
      ),
      isTrue,
    );

    expect(settled, isTrue);
    expect(store.balanceWith(store.groupById('group-1'), member), 0);
    expect(store.groupById('group-1').settlements, hasLength(1));
  });

  test('uses server for receipt in an offline-created group after sync',
      () async {
    var synced = false;
    var receiptConfirmed = false;
    String? groupId;
    String? ownerId;
    String? debtorId;
    final client = ApiClient(
      baseUrl: 'http://example.test',
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/auth/login') {
          return _loginResponse(request);
        }
        if (request.method == 'POST' &&
            request.url.path == '/api/v1/offline-sync/groups') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final syncedGroup =
              (body['groups'] as List<dynamic>).single as Map<String, dynamic>;
          expect(syncedGroup['visibility'], 'personal');
          groupId = syncedGroup['id'] as String;
          final members = syncedGroup['members'] as List<dynamic>;
          ownerId = (members.first as Map<String, dynamic>)['id'] as String;
          debtorId = (members.last as Map<String, dynamic>)['id'] as String;
          synced = true;
          return http.Response(
            jsonEncode({
              'groups': [
                {
                  'local_group_id': groupId,
                  'remote_group_id': groupId,
                }
              ],
            }),
            200,
          );
        }
        if (request.method == 'POST' &&
            request.url.path.endsWith('/settlements/received')) {
          expect(synced, isTrue);
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['debtor_member_id'], debtorId);
          receiptConfirmed = true;
          return http.Response('{}', 201);
        }
        if (request.method == 'GET' && request.url.path == '/api/v1/groups') {
          return http.Response(
            jsonEncode({
              'groups': [
                {
                  'id': groupId,
                  'name': 'Offline dinner',
                  'emoji': 'D',
                  'visibility': 'personal',
                  'members': [
                    {'id': ownerId, 'user_id': 'user-1', 'name': 'You'},
                    {'id': debtorId, 'name': 'Ana'},
                  ],
                  'balances': receiptConfirmed
                      ? {ownerId!: 0, debtorId!: 0}
                      : {ownerId!: -5000, debtorId!: 5000},
                  'payment_relations': receiptConfirmed
                      ? <Object>[]
                      : [
                          {
                            'from_member_id': debtorId,
                            'to_member_id': ownerId,
                            'amount_cents': 5000,
                          }
                        ],
                  'expenses': [
                    {
                      'id': 'local_expense_103',
                      'description': 'Dinner',
                      'amount_cents': 10000,
                      'payer_id': ownerId,
                      'participant_ids': [ownerId, debtorId],
                      'created_at': DateTime.utc(2026, 11, 8).toIso8601String(),
                    }
                  ],
                  'settlements': receiptConfirmed
                      ? [
                          {
                            'id': 'settlement-1',
                            'from_member_id': debtorId,
                            'to_member_id': ownerId,
                            'amount_cents': 5000,
                            'created_at':
                                DateTime.utc(2026, 11, 8).toIso8601String(),
                          }
                        ]
                      : <Object>[],
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
    final store = DemoStore.offline(client, null);
    addTearDown(store.dispose);
    await store.createGroup(
      name: 'Offline dinner',
      emoji: 'D',
      memberNames: const ['Ana'],
      visibility: 'shared',
    );
    final group = store.groups.single;
    expect(group.id, startsWith('local_group_'));
    expect(group.visibility, 'personal');
    final debtor = group.members[1];
    final owner = group.members.first;
    await store.addExpense(
      groupId: group.id,
      description: 'Dinner',
      amountCents: 10000,
      payerId: owner.id,
      payers: [
        ExpensePayer(memberId: owner.id, amountCents: 10000),
      ],
      participantIds: group.members.map((member) => member.id).toList(),
    );

    await client.login(email: 'you@example.test', password: 'password');
    await store.refreshAuthentication();
    expect(await store.syncLocalGroups(enable: true), isTrue);
    expect(
      await store.confirmReceivedPayment(
        groupId: group.id,
        debtorId: debtor.id,
      ),
      isTrue,
    );

    expect(receiptConfirmed, isTrue);
    expect(store.balanceWith(store.groupById(group.id), debtor), 0);
    expect(store.groupById(group.id).settlements, hasLength(1));
  });
}
