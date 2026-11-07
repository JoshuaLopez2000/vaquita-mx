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
  Future<http.Response> Function(http.Request) handler,
) async {
  final client = ApiClient(
    baseUrl: 'http://example.test',
    client: MockClient(handler),
  );
  await client.login(email: 'you@example.test', password: 'password');
  final store = DemoStore.remote(client);
  store.groups.add(
    ExpenseGroup(
      id: 'group-1',
      name: 'Group',
      emoji: 'G',
      members: const [
        Member(id: 'user-1', userId: 'user-1', name: 'You'),
        Member(id: 'debtor-1', name: 'Ana'),
      ],
      balances: const {'user-1': -12500, 'debtor-1': 12500},
      paymentRelations: const [
        PaymentRelation(
          fromMemberId: 'debtor-1',
          toMemberId: 'user-1',
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
    await tester.tap(find.byKey(const Key('settle-debtor-1')));
    await tester.pumpAndSettle();

    expect(find.text('Solicitud de pago creada.'), findsOneWidget);
    expect(requestCount, 3);
  });
}
