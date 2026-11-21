import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vaquita_mx/src/api_client.dart';
import 'package:vaquita_mx/src/store.dart';

void main() {
  test(
      'concurrent loadInvitations and loadContacts do not duplicate items and keep cached data on failure',
      () async {
    final inviteGate = Completer<void>();
    final contactGate = Completer<void>();
    var inviteCalls = 0;
    var contactCalls = 0;
    var failNetwork = false;

    final client = ApiClient(
      baseUrl: 'http://example.test',
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/auth/login') {
          return http.Response(
            jsonEncode({
              'access_token': 'token',
              'refresh_token': 'refresh',
              'user': {
                'id': 'user-1',
                'name': 'Joshua',
                'email': 'joshua@vaquita.mx',
                'phone': '+525510000002',
                'salary_cents': 0,
              },
            }),
            200,
          );
        }
        if (failNetwork) {
          throw const SocketException('offline');
        }
        if (request.url.path == '/api/v1/group-invitations') {
          inviteCalls++;
          if (inviteCalls == 2 && !inviteGate.isCompleted) {
            inviteGate.complete();
          }
          await inviteGate.future;
          return http.Response(
            jsonEncode({
              'invitations': [
                {
                  'group': {
                    'id': 'group-1',
                    'name': 'Concierto CDMX',
                    'emoji': 'M',
                    'visibility': 'shared',
                  },
                  'member': {
                    'id': 'member-1',
                    'user_id': 'user-1',
                    'name': 'Joshua',
                    'accepted': false,
                  },
                },
              ],
            }),
            200,
          );
        }
        if (request.url.path == '/api/v1/contacts') {
          contactCalls++;
          if (contactCalls == 2 && !contactGate.isCompleted) {
            contactGate.complete();
          }
          await contactGate.future;
          return http.Response(
            jsonEncode({
              'contacts': [
                {'id': 'c1', 'name': 'Ana', 'phone': '+525510000001'},
              ],
            }),
            200,
          );
        }
        throw StateError('Unexpected: ${request.method} ${request.url}');
      }),
    );
    final store = DemoStore.offline(client, null);
    addTearDown(() {
      store.dispose();
      client.close();
    });
    await client.login(email: 'joshua@vaquita.mx', password: 'TestPass123!');

    await Future.wait([store.loadInvitations(), store.loadInvitations()]);
    expect(inviteCalls, 2);
    expect(store.invitations, hasLength(1));
    expect(store.invitations.single.group.id, 'group-1');

    await Future.wait([store.loadContacts(), store.loadContacts()]);
    expect(contactCalls, 2);
    expect(store.contacts, hasLength(1));
    expect(store.contacts.single.id, 'c1');

    // A transient network failure must keep previously loaded items intact.
    failNetwork = true;
    await store.loadInvitations();
    await store.loadContacts();
    expect(store.invitations, hasLength(1));
    expect(store.contacts, hasLength(1));
  });
}
