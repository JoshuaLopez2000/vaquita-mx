import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vaquita_mx/l10n/app_localizations.dart';
import 'package:vaquita_mx/src/api_client.dart';
import 'package:vaquita_mx/src/app.dart';
import 'package:vaquita_mx/src/deep_links.dart';
import 'package:vaquita_mx/src/features/app/application/app_cubit.dart';
import 'package:vaquita_mx/src/group_detail_screen.dart';
import 'package:vaquita_mx/src/models.dart';
import 'package:vaquita_mx/src/screens/payment_request_detail_screen.dart';
import 'package:vaquita_mx/src/store.dart';

http.Response _jsonResponse(Object body, int statusCode) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      statusCode,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

http.Response _loginOk({String userId = 'user-1', String name = 'Ana'}) =>
    _jsonResponse({
      'access_token': 'access-token',
      'refresh_token': 'refresh-token',
      'user': {
        'id': userId,
        'name': name,
        'email': '$userId@example.test',
        'phone': '+525511112222',
        'salary_cents': 0,
      },
    }, 200);

Map<String, dynamic> _sampleRequestJson({
  required String id,
  required String role,
  String status = 'PENDING',
  int amountCents = 25000,
  String groupId = 'group-1',
  String groupName = 'Depa',
  String groupEmoji = '🏠',
  String creditorId = 'member-creditor',
  String creditorName = 'Ana',
  String debtorId = 'member-debtor',
  String debtorName = 'Beto',
  String description = 'Liquidación de saldo del grupo',
  DateTime? expiresAt,
  DateTime? paidAt,
}) =>
    {
      'id': id,
      'group_id': groupId,
      'group_name': groupName,
      'group_emoji': groupEmoji,
      'creditor_id': creditorId,
      'creditor_name': creditorName,
      'debtor_id': debtorId,
      'debtor_name': debtorName,
      'amount_cents': amountCents,
      'currency': 'MXN',
      'provider': 'simulated',
      'status': status,
      'payment_url': 'vaquitamx://payment-requests/$id',
      'expires_at':
          (expiresAt ?? DateTime.now().toUtc().add(const Duration(hours: 24)))
              .toIso8601String(),
      'created_at': DateTime.now().toUtc().toIso8601String(),
      if (paidAt != null) 'paid_at': paidAt.toUtc().toIso8601String(),
      'description': description,
      'role': role,
    };

class _FakeDeepLinkSource implements DeepLinkSource {
  _FakeDeepLinkSource({this.initialLink});

  final String? initialLink;
  final StreamController<String> _controller =
      StreamController<String>.broadcast();

  void emit(String link) => _controller.add(link);

  @override
  Future<String?> getInitialLink() async => initialLink;

  @override
  Stream<String> get links => _controller.stream;

  @override
  void dispose() {
    unawaited(_controller.close());
  }
}

void main() {
  group('parsePaymentRequestDeepLink', () {
    test('parses valid vaquitamx payment request links', () {
      expect(
        parsePaymentRequestDeepLink('vaquitamx://payment-requests/pr_abc123'),
        'pr_abc123',
      );
      expect(
        parsePaymentRequestDeepLink(
          '  VAQUITAMX://PAYMENT-REQUESTS/pr_xyz_789  ',
        ),
        'pr_xyz_789',
      );
    });

    test('rejects invalid schemes, hosts, empty ids, or extra segments', () {
      expect(parsePaymentRequestDeepLink(null), isNull);
      expect(parsePaymentRequestDeepLink(''), isNull);
      expect(
        parsePaymentRequestDeepLink('https://vaquita.mx/payment-requests/pr_1'),
        isNull,
      );
      expect(
        parsePaymentRequestDeepLink('vaquitamx://groups/group-1'),
        isNull,
      );
      expect(
        parsePaymentRequestDeepLink('vaquitamx://payment-requests/'),
        isNull,
      );
      expect(
        parsePaymentRequestDeepLink('vaquitamx://payment-requests/pr_1/extra'),
        isNull,
      );
    });
  });

  group('payment request retry idempotency and offline safety', () {
    test(
        'reuses one Idempotency-Key across transient retry and clears on success',
        () async {
      final seenKeys = <String>[];
      var postAttempt = 0;
      final client = ApiClient(
        baseUrl: 'http://example.test',
        client: MockClient((request) async {
          if (request.url.path == '/api/v1/auth/login') return _loginOk();
          if (request.method == 'POST' &&
              request.url.path == '/api/v1/payment-requests') {
            postAttempt++;
            seenKeys.add(request.headers['idempotency-key']!);
            if (postAttempt == 1) {
              return _jsonResponse(
                {'code': 'service_unavailable', 'message': 'try again'},
                503,
              );
            }
            return _jsonResponse(
              _sampleRequestJson(id: 'pr_$postAttempt', role: 'creditor'),
              201,
            );
          }
          if (request.method == 'GET' && request.url.path == '/api/v1/groups') {
            return _jsonResponse({'groups': <Object>[]}, 200);
          }
          throw StateError('Unexpected: ${request.method} ${request.url}');
        }),
      );
      await client.login(email: 'user-1@example.test', password: 'password');
      final store = DemoStore.offline(client, null);
      addTearDown(store.dispose);
      store.groups.add(
        ExpenseGroup(
          id: 'group-1',
          name: 'Depa',
          emoji: '🏠',
          visibility: 'shared',
          members: const [
            Member(id: 'member-creditor', userId: 'user-1', name: 'Ana'),
            Member(id: 'member-debtor', userId: 'user-2', name: 'Beto'),
          ],
        ),
      );

      final first = await store.requestPayment(
        groupId: 'group-1',
        debtorId: 'member-debtor',
        amountCents: 25000,
        description: 'Liquidación de saldo del grupo',
      );
      expect(first, isFalse);

      final retry = await store.requestPayment(
        groupId: 'group-1',
        debtorId: 'member-debtor',
        amountCents: 25000,
        description: 'Liquidación de saldo del grupo',
      );
      expect(retry, isTrue);

      final nextIntent = await store.requestPayment(
        groupId: 'group-1',
        debtorId: 'member-debtor',
        amountCents: 25000,
        description: 'Liquidación de saldo del grupo',
      );
      expect(nextIntent, isTrue);

      expect(seenKeys, hasLength(3));
      expect(seenKeys[0], seenKeys[1]);
      expect(seenKeys[2], isNot(seenKeys[1]));
    });

    test(
        'reuses stable provider_event_id across transient simulate retry and disables offline',
        () async {
      final seenEventIds = <String>[];
      var simulateAttempt = 0;
      final client = ApiClient(
        baseUrl: 'http://example.test',
        client: MockClient((request) async {
          if (request.url.path == '/api/v1/auth/login') return _loginOk();
          if (request.method == 'POST' &&
              request.url.path == '/api/v1/payment-requests/pr_1/simulate') {
            simulateAttempt++;
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            seenEventIds.add(body['provider_event_id'] as String);
            if (simulateAttempt == 1) {
              return _jsonResponse(
                {'code': 'service_unavailable', 'message': 'retry'},
                503,
              );
            }
            return _jsonResponse(
              _sampleRequestJson(
                id: 'pr_1',
                role: 'debtor',
                status: 'PAID',
                paidAt: DateTime.now().toUtc(),
              ),
              201,
            );
          }
          if (request.method == 'GET' && request.url.path == '/api/v1/groups') {
            return _jsonResponse({'groups': <Object>[]}, 200);
          }
          if (request.method == 'GET' && request.url.path == '/api/v1/status') {
            return _jsonResponse({'contacts': <Object>[]}, 200);
          }
          throw StateError('Unexpected: ${request.method} ${request.url}');
        }),
      );
      await client.login(email: 'user-1@example.test', password: 'password');
      final store = DemoStore.offline(client, null);
      addTearDown(store.dispose);

      // Offline completion is disabled and never queued.
      store.setConnectivityOnline(false);
      expect(await store.completeSimulatedPayment('pr_1'), isFalse);
      expect(store.errorMessage, 'server_unavailable');
      expect(store.pendingMutations, isEmpty);
      expect(seenEventIds, isEmpty);

      // Online transient retry reuses the same provider_event_id.
      store.setConnectivityOnline(true);
      expect(await store.completeSimulatedPayment('pr_1'), isFalse);
      expect(await store.completeSimulatedPayment('pr_1'), isTrue);
      expect(seenEventIds, hasLength(2));
      expect(seenEventIds[0], seenEventIds[1]);
      expect(store.paymentRequestById('pr_1')?.isPaid, isTrue);
    });
  });

  group('Bandeja, Group Detail, and Deep Links UI', () {
    testWidgets(
        'lists and filters payment requests in Bandeja and completes debtor simulated payment with disclaimer',
        (tester) async {
      final queriedOrientations = <String?>[];
      var isPaid = false;

      final client = ApiClient(
        baseUrl: 'http://example.test',
        client: MockClient((request) async {
          if (request.url.path == '/api/v1/auth/login') {
            return _loginOk(userId: 'user-2', name: 'Beto');
          }
          if (request.method == 'GET' && request.url.path == '/api/v1/status') {
            return _jsonResponse({'contacts': <Object>[]}, 200);
          }
          if (request.method == 'GET' &&
              request.url.path == '/api/v1/group-invitations') {
            return _jsonResponse({'invitations': <Object>[]}, 200);
          }
          if (request.method == 'GET' &&
              request.url.path == '/api/v1/payment-requests') {
            final orientation = request.url.queryParameters['orientation'];
            queriedOrientations.add(orientation);
            final debtorReq = _sampleRequestJson(
              id: 'pr_debtor',
              role: 'debtor',
              status: isPaid ? 'PAID' : 'PENDING',
              paidAt: isPaid ? DateTime.now().toUtc() : null,
            );
            final creditorReq = _sampleRequestJson(
              id: 'pr_creditor',
              role: 'creditor',
              creditorName: 'Beto',
              debtorName: 'Carla',
              amountCents: 18000,
              description: 'Cena de tacos',
            );
            final items = switch (orientation) {
              'debtor' => [debtorReq],
              'creditor' => [creditorReq],
              _ => [debtorReq, creditorReq],
            };
            return _jsonResponse({'payment_requests': items}, 200);
          }
          if (request.method == 'GET' &&
              request.url.path == '/api/v1/payment-requests/pr_debtor') {
            return _jsonResponse(
              _sampleRequestJson(
                id: 'pr_debtor',
                role: 'debtor',
                status: isPaid ? 'PAID' : 'PENDING',
                paidAt: isPaid ? DateTime.now().toUtc() : null,
              ),
              200,
            );
          }
          if (request.method == 'POST' &&
              request.url.path ==
                  '/api/v1/payment-requests/pr_debtor/simulate') {
            isPaid = true;
            return _jsonResponse(
              _sampleRequestJson(
                id: 'pr_debtor',
                role: 'debtor',
                status: 'PAID',
                paidAt: DateTime.now().toUtc(),
              ),
              201,
            );
          }
          if (request.method == 'GET' && request.url.path == '/api/v1/groups') {
            return _jsonResponse({'groups': <Object>[]}, 200);
          }
          return _jsonResponse({}, 404);
        }),
      );
      await client.login(email: 'beto@example.test', password: 'password');
      final store = DemoStore.remote(client);
      addTearDown(store.dispose);

      await tester.pumpWidget(
        BlocProvider(
          create: (_) => AppCubit(store),
          child: MaterialApp(
            locale: const Locale('es'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: StatusScreen(store: store)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Solicitudes de pago'), findsOneWidget);
      expect(
        find.byKey(const Key('payment-request-card-pr_debtor')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('payment-request-card-pr_creditor')),
        findsOneWidget,
      );

      // Filter by debtor ("Por pagar").
      await tester.tap(find.byKey(const Key('payment-requests-filter-debtor')));
      await tester.pumpAndSettle();
      expect(queriedOrientations, contains('debtor'));
      expect(
        find.byKey(const Key('payment-request-card-pr_debtor')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('payment-request-card-pr_creditor')),
        findsNothing,
      );

      // Filter by creditor ("Enviadas").
      await tester
          .tap(find.byKey(const Key('payment-requests-filter-creditor')));
      await tester.pumpAndSettle();
      expect(queriedOrientations, contains('creditor'));
      expect(
        find.byKey(const Key('payment-request-card-pr_creditor')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('payment-request-card-pr_debtor')),
        findsNothing,
      );

      // Switch back to debtor and complete simulated payment.
      await tester.tap(find.byKey(const Key('payment-requests-filter-debtor')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('payment-request-card-pr_debtor')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('payment-request-demo-disclaimer')),
        findsOneWidget,
      );
      expect(find.text('Pago simulado (demo)'), findsOneWidget);
      expect(
        find.byKey(const Key('complete-simulated-payment-button')),
        findsOneWidget,
      );

      await tester
          .tap(find.byKey(const Key('complete-simulated-payment-button')));
      await tester.pumpAndSettle();

      expect(isPaid, isTrue);
      expect(
        find.text('Pago simulado completado. Saldos actualizados.'),
        findsOneWidget,
      );
      expect(find.text('Pagada'), findsOneWidget);
      expect(
        find.byKey(const Key('complete-simulated-payment-button')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('payment-request-state-explanation')),
        findsOneWidget,
      );
    });

    testWidgets(
        'surfaces payment requests in Group Detail, shares creditor link, and explains expired/failed states',
        (tester) async {
      String? copiedText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText =
              (call.arguments as Map<dynamic, dynamic>)['text'] as String?;
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      final pendingReq = _sampleRequestJson(
        id: 'pr_cred_pending',
        role: 'creditor',
        status: 'PENDING',
      );
      final expiredReq = _sampleRequestJson(
        id: 'pr_expired',
        role: 'debtor',
        status: 'EXPIRED',
        expiresAt: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
      );
      final failedReq = _sampleRequestJson(
        id: 'pr_failed',
        role: 'debtor',
        status: 'FAILED',
      );

      final client = ApiClient(
        baseUrl: 'http://example.test',
        client: MockClient((request) async {
          if (request.url.path == '/api/v1/auth/login') return _loginOk();
          if (request.method == 'GET' &&
              request.url.path == '/api/v1/payment-requests') {
            expect(request.url.queryParameters['group_id'], 'group-1');
            return _jsonResponse(
              {
                'payment_requests': [pendingReq, expiredReq, failedReq]
              },
              200,
            );
          }
          if (request.method == 'GET' &&
              request.url.path == '/api/v1/payment-requests/pr_cred_pending') {
            return _jsonResponse(pendingReq, 200);
          }
          if (request.method == 'GET' &&
              request.url.path == '/api/v1/payment-requests/pr_expired') {
            return _jsonResponse(expiredReq, 200);
          }
          if (request.method == 'GET' &&
              request.url.path == '/api/v1/payment-requests/pr_failed') {
            return _jsonResponse(failedReq, 200);
          }
          return _jsonResponse({}, 404);
        }),
      );
      await client.login(email: 'ana@example.test', password: 'password');
      final store = DemoStore.remote(client);
      addTearDown(store.dispose);
      store.groups.add(
        ExpenseGroup(
          id: 'group-1',
          name: 'Depa',
          emoji: '🏠',
          visibility: 'shared',
          members: const [
            Member(id: 'member-creditor', userId: 'user-1', name: 'Ana'),
            Member(id: 'member-debtor', userId: 'user-2', name: 'Beto'),
          ],
        ),
      );

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
      await tester.pumpAndSettle();

      // Creditor pending request appears inside Group Detail and shares deep link.
      final pendingCard =
          find.byKey(const Key('payment-request-card-pr_cred_pending'));
      await tester.scrollUntilVisible(pendingCard, 200);
      await tester.ensureVisible(pendingCard);
      await tester.pumpAndSettle();
      await tester.tap(pendingCard);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('payment-request-waiting-debtor')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('complete-simulated-payment-button')),
        findsNothing,
      );
      final shareButton =
          find.byKey(const Key('share-payment-request-link-button'));
      await tester.scrollUntilVisible(
        shareButton,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(shareButton);
      await tester.pumpAndSettle();
      await tester.tap(shareButton);
      await tester.pumpAndSettle();
      expect(copiedText, 'vaquitamx://payment-requests/pr_cred_pending');
      expect(find.text('Enlace de pago copiado'), findsOneWidget);

      // Pop back and inspect EXPIRED request.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      final expiredCard =
          find.byKey(const Key('payment-request-card-pr_expired'));
      await tester.scrollUntilVisible(expiredCard, 200);
      await tester.ensureVisible(expiredCard);
      await tester.pumpAndSettle();
      await tester.tap(expiredCard);
      await tester.pumpAndSettle();

      expect(find.text('Expirada'), findsOneWidget);
      expect(
        find.text(
          'Esta solicitud expiró y ya no puede completarse. Pide una nueva solicitud si aún existe saldo pendiente.',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('complete-simulated-payment-button')),
        findsNothing,
      );

      // Pop back and inspect FAILED request.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      final failedCard =
          find.byKey(const Key('payment-request-card-pr_failed'));
      await tester.scrollUntilVisible(failedCard, 200);
      await tester.ensureVisible(failedCard);
      await tester.pumpAndSettle();
      await tester.tap(failedCard);
      await tester.pumpAndSettle();

      expect(find.text('Fallida'), findsOneWidget);
      expect(
        find.byKey(const Key('complete-simulated-payment-button')),
        findsNothing,
      );
    });

    testWidgets(
        'opens PaymentRequestDetailScreen from vaquitamx://payment-requests/{id} deep links including 404 handling',
        (tester) async {
      final deepLinks = _FakeDeepLinkSource(
        initialLink: 'vaquitamx://payment-requests/pr_deep_1',
      );
      addTearDown(deepLinks.dispose);

      final client = ApiClient(
        baseUrl: 'http://example.test',
        client: MockClient((request) async {
          if (request.url.path == '/api/v1/auth/login') {
            return _loginOk(userId: 'user-2', name: 'Beto');
          }
          if (request.method == 'GET' &&
              request.url.path == '/api/v1/contacts') {
            return _jsonResponse({'contacts': <Object>[]}, 200);
          }
          if (request.method == 'GET' &&
              request.url.path == '/api/v1/payment-requests/pr_deep_1') {
            return _jsonResponse(
              _sampleRequestJson(
                id: 'pr_deep_1',
                role: 'debtor',
                amountCents: 45000,
                description: 'Renta de octubre',
              ),
              200,
            );
          }
          if (request.method == 'GET' &&
              request.url.path == '/api/v1/payment-requests/pr_missing') {
            return _jsonResponse(
              {'code': 'resource_not_found', 'message': 'not found'},
              404,
            );
          }
          return _jsonResponse({}, 404);
        }),
      );
      await client.login(email: 'beto@example.test', password: 'password');
      final store = DemoStore.remote(client);
      addTearDown(store.dispose);

      await tester.pumpWidget(
        VaquitaApp(store: store, deepLinkSource: deepLinks),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PaymentRequestDetailScreen), findsOneWidget);
      expect(find.text('\$450.00 MXN'), findsOneWidget);
      expect(find.text('Renta de octubre'), findsOneWidget);
      expect(
        find.byKey(const Key('payment-request-demo-disclaimer')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('complete-simulated-payment-button')),
        findsOneWidget,
      );

      // Incoming deep link to a hidden/missing request shows unavailable state.
      deepLinks.emit('vaquitamx://payment-requests/pr_missing');
      await tester.pumpAndSettle();

      expect(find.text('Solicitud no disponible'), findsOneWidget);
    });

    testWidgets(
        'exits startup loading indicator after async initialization and opens queued deep link',
        (tester) async {
      final storeCompleter = Completer<DemoStore>();
      final deepLinks = _FakeDeepLinkSource(
        initialLink: 'vaquitamx://payment-requests/pr_boot_1',
      );
      addTearDown(deepLinks.dispose);

      await tester.pumpWidget(
        VaquitaApp(
          initializeStore: () => storeCompleter.future,
          deepLinkSource: deepLinks,
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(AppShell), findsNothing);

      final client = ApiClient(
        baseUrl: 'http://example.test',
        client: MockClient((request) async {
          if (request.url.path == '/api/v1/auth/login') {
            return _loginOk(userId: 'user-2', name: 'Beto');
          }
          if (request.method == 'GET' &&
              request.url.path == '/api/v1/contacts') {
            return _jsonResponse({'contacts': <Object>[]}, 200);
          }
          if (request.method == 'GET' &&
              request.url.path == '/api/v1/payment-requests/pr_boot_1') {
            return _jsonResponse(
              _sampleRequestJson(
                id: 'pr_boot_1',
                role: 'debtor',
                amountCents: 30000,
                description: 'Internet de noviembre',
              ),
              200,
            );
          }
          return _jsonResponse({}, 404);
        }),
      );
      await client.login(email: 'beto@example.test', password: 'password');
      final store = DemoStore.remote(client);
      storeCompleter.complete(store);

      await tester.pumpAndSettle();

      expect(find.byType(PaymentRequestDetailScreen), findsOneWidget);
      expect(find.text('Internet de noviembre'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.byType(AppShell), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
