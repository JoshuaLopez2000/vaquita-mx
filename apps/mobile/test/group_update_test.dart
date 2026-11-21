import 'dart:convert';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vaquita_mx/l10n/app_localizations.dart';
import 'package:vaquita_mx/src/api_client.dart';
import 'package:vaquita_mx/src/features/app/application/app_cubit.dart';
import 'package:vaquita_mx/src/group_detail_screen.dart';
import 'package:vaquita_mx/src/store.dart';

Future<DemoStore> _pumpEditor(
  WidgetTester tester, {
  required bool rejectUpdate,
}) async {
  var emoji = 'G';
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
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'groups': [
              {
                'id': 'group-1',
                'name': 'Group',
                'emoji': emoji,
                'visibility': 'personal',
                'members': [
                  {'id': 'user-1', 'user_id': 'user-1', 'name': 'You'},
                ],
                'expenses': <Object>[],
                'settlements': <Object>[],
                'balances': <String, int>{},
                'payment_relations': <Object>[],
              }
            ],
          })),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (request.method == 'PATCH' &&
          request.url.path == '/api/v1/groups/group-1') {
        if (rejectUpdate) {
          return http.Response(
            jsonEncode({
              'error': {
                'code': 'resource_not_found',
                'message': 'group not found',
              }
            }),
            404,
          );
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        emoji = body['emoji'] as String;
        return http.Response('{}', 200);
      }
      throw StateError('Unexpected request: ${request.method} ${request.url}');
    }),
  );
  final store = DemoStore.offline(client, null);
  await client.login(email: 'you@example.test', password: 'password');
  await store.load();
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
  return store;
}

Future<void> _selectSoupEmoji(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.more_horiz_rounded));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Editar grupo y agregar contactos'));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(TextField).at(1));
  await tester.pumpAndSettle();
  final picker = tester.widget<EmojiPicker>(find.byType(EmojiPicker));
  picker.onEmojiSelected!(
    Category.SMILEYS,
    const Emoji('🍲', 'Pot of food'),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Guardar grupo'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('saves edited emoji from the group screen', (tester) async {
    final store = await _pumpEditor(tester, rejectUpdate: false);
    addTearDown(store.dispose);

    await _selectSoupEmoji(tester);

    expect(store.groupById('group-1').emoji, '🍲');
    expect(find.text('🍲'), findsOneWidget);
  });

  testWidgets('keeps the editor open when the server rejects an update',
      (tester) async {
    final store = await _pumpEditor(tester, rejectUpdate: true);
    addTearDown(store.dispose);

    await _selectSoupEmoji(tester);

    expect(find.text('Guardar grupo'), findsOneWidget);
    expect(
      find.text(
          'No se pudo guardar el grupo. Comprueba tu conexión y que tengas permiso para editarlo.'),
      findsOneWidget,
    );
    expect(store.groupById('group-1').emoji, 'G');
  });

  test('saves a server-backed group emoji through the API', () async {
    var emoji = 'G';
    var updateRequests = 0;
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
          return http.Response.bytes(
            utf8.encode(jsonEncode({
              'groups': [
                {
                  'id': 'group-1',
                  'name': 'Group',
                  'emoji': emoji,
                  'visibility': 'shared',
                  'members': [
                    {'id': 'user-1', 'user_id': 'user-1', 'name': 'You'},
                    {'id': 'member-1', 'name': 'Ana'},
                  ],
                  'expenses': <Object>[],
                  'settlements': <Object>[],
                  'balances': <String, int>{},
                  'payment_relations': <Object>[],
                }
              ],
            })),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (request.method == 'PATCH' &&
            request.url.path == '/api/v1/groups/group-1') {
          updateRequests++;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['emoji'], '🍲');
          emoji = body['emoji'] as String;
          return http.Response('{}', 200);
        }
        throw StateError(
            'Unexpected request: ${request.method} ${request.url}');
      }),
    );
    final store = DemoStore.offline(client, null);
    addTearDown(store.dispose);
    await client.login(email: 'you@example.test', password: 'password');
    await store.load();

    expect(await store.updateGroup('group-1', {'emoji': '🍲'}), isTrue);
    expect(emoji, '🍲');
    expect(store.errorMessage, isNull);
    expect(store.groupById('group-1').emoji, '🍲');
    await store.load();

    expect(updateRequests, 1);
    expect(store.groupById('group-1').emoji, '🍲');
  });
}
