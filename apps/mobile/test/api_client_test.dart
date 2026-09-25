import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vaquita_mx/src/api_client.dart';

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

  test('sends login credentials and keeps the session token', () async {
    final client = ApiClient(
      baseUrl: 'http://example.test',
      client: MockClient((request) async {
        expect(request.url.path, '/api/v1/auth/login');
        expect(jsonDecode(request.body), {'email': 'ana@example.com', 'password': 'password1'});
        return http.Response(jsonEncode({'token': 'session-token', 'user': {}}), 200);
      }),
    );

    await client.login(email: 'ana@example.com', password: 'password1');
  });
}
