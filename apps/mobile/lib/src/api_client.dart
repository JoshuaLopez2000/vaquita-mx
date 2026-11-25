import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:vaquita_mx/src/models.dart';

class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.correlationId,
    this.fields = const <String, String>{},
  });

  final String code;
  final String message;
  final int? statusCode;
  final String? correlationId;
  final Map<String, String> fields;

  @override
  String toString() => message;
}

abstract class SessionStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureSessionStorage implements SessionStorage {
  const SecureSessionStorage();

  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class ApiClient {
  ApiClient({
    required String baseUrl,
    http.Client? client,
    SessionStorage? storage,
    this.onSessionInvalidated,
  })  : _baseUrl = baseUrl.replaceAll(RegExp(r'/$'), ''),
        _client = client ?? http.Client(),
        _storage = storage ?? const SecureSessionStorage();

  final String _baseUrl;
  final http.Client _client;
  final SessionStorage _storage;
  void Function()? onSessionInvalidated;
  static const _sessionTokenKey = 'session_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _sessionUserKey = 'session_user';
  String? _token;
  String? _refreshToken;
  String? _userId;
  AppUser? _user;
  Future<bool>? _refreshInProgress;
  String? get userId => _userId;
  AppUser? get user => _user;

  Future<bool> restoreSession() async {
    final token = await _storage.read(_sessionTokenKey);
    final refreshToken = await _storage.read(_refreshTokenKey);
    final encodedUser = await _storage.read(_sessionUserKey);
    if (token == null || encodedUser == null) return false;
    try {
      final user =
          AppUser.fromJson(jsonDecode(encodedUser) as Map<String, dynamic>);
      _token = token;
      _refreshToken = refreshToken;
      _user = user;
      _userId = user.id;
      return true;
    } catch (_) {
      await clearSession();
      return false;
    }
  }

  Future<void> persistSession() async {
    if (_token == null || _user == null) return;
    await _storage.write(_sessionTokenKey, _token!);
    if (_refreshToken != null) {
      await _storage.write(_refreshTokenKey, _refreshToken!);
    } else {
      await _storage.delete(_refreshTokenKey);
    }
    await _storage.write(
      _sessionUserKey,
      jsonEncode({
        'id': _user!.id,
        'name': _user!.name,
        'email': _user!.email,
        'phone': _user!.phone,
        'salary_cents': _user!.salaryCents,
      }),
    );
  }

  Future<void> clearSession() async {
    _token = null;
    _refreshToken = null;
    _user = null;
    _userId = null;
    await _storage.delete(_sessionTokenKey);
    await _storage.delete(_refreshTokenKey);
    await _storage.delete(_sessionUserKey);
  }

  Future<void> login({required String email, required String password}) =>
      _authenticate(
          '/api/v1/auth/login', {'email': email, 'password': password});

  Future<void> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    int salaryCents = 0,
  }) =>
      _authenticate('/api/v1/auth/register', <String, dynamic>{
        'name': name,
        'email': email,
        'phone': phone,
        'password': password,
        'salary_cents': salaryCents,
      });

  Future<void> signOut({bool allDevices = false}) async {
    try {
      if (_token != null) {
        final response = await _request(
          'POST',
          allDevices ? '/api/v1/auth/sign-out-all' : '/api/v1/auth/sign-out',
        );
        if (response.statusCode != 204) _decode(response);
      }
    } finally {
      await clearSession();
    }
  }

  Future<List<ExpenseGroup>> listGroups() async {
    final response = await _request('GET', '/api/v1/groups');
    final body = _decode(response);
    return ((body['groups'] as List<dynamic>?) ?? const [])
        .map((value) => ExpenseGroup.fromJson(value as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, String>> syncLocalGroups(List<ExpenseGroup> groups) async {
    final response = await _request(
      'POST',
      '/api/v1/offline-sync/groups',
      body: {
        'groups': [for (final group in groups) _offlineGroupPayload(group)],
      },
    );
    final rows = (_decode(response)['groups'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    return {
      for (final row in rows)
        row['local_group_id'] as String: row['remote_group_id'] as String,
    };
  }

  Map<String, dynamic> _offlineGroupPayload(ExpenseGroup group) => {
        'id': group.id,
        'name': group.name,
        'emoji': group.emoji,
        'visibility': group.visibility,
        'salary_split_enabled': group.salarySplitEnabled,
        'members': [
          for (final member in group.members)
            {
              'id': member.id,
              'name': member.name,
              'phone': member.phone,
              'salary_sharing': member.salarySharing,
              'active': member.active,
            },
        ],
        'expenses': [
          for (final expense in group.expenses)
            {
              'id': expense.id,
              'description': expense.description,
              'amount_cents': expense.amountCents,
              'payer_id': expense.payerId,
              'payers': [
                for (final payer in expense.payers)
                  {
                    'member_id': payer.memberId,
                    'amount_cents': payer.amountCents,
                  },
              ],
              'participant_ids': expense.participantIds,
              'split_mode': expense.splitMode,
              'shares': expense.splitMode == 'exact' &&
                      expense.consumptionShares.isNotEmpty
                  ? expense.consumptionShares
                  : expense.shares,
              if (expense.percentages.isNotEmpty)
                'percentages': expense.percentages,
              'split_overpayment': expense.splitOverpayment,
              if (expense.replacesExpenseId != null &&
                  expense.replacesExpenseId!.isNotEmpty)
                'replaces_expense_id': expense.replacesExpenseId,
              'created_at': expense.createdAt.toUtc().toIso8601String(),
            },
        ],
        if (group.expenseReversals.isNotEmpty)
          'expense_reversals': [
            for (final reversal in group.expenseReversals)
              {
                'id': reversal.id,
                'original_expense_id': reversal.originalExpenseId,
                'actor_member_id': reversal.actorMemberId,
                'reason': reversal.reason,
                'created_at': reversal.createdAt.toUtc().toIso8601String(),
              },
          ],
        'settlements': [
          for (final settlement in group.settlements)
            {
              'id': settlement.id,
              'from_member_id': settlement.fromMemberId,
              'to_member_id': settlement.toMemberId,
              'amount_cents': settlement.amountCents,
              if (settlement.replacesSettlementId != null &&
                  settlement.replacesSettlementId!.isNotEmpty)
                'replaces_settlement_id': settlement.replacesSettlementId,
              'created_at': settlement.createdAt.toUtc().toIso8601String(),
            },
        ],
        if (group.settlementReversals.isNotEmpty)
          'settlement_reversals': [
            for (final reversal in group.settlementReversals)
              {
                'id': reversal.id,
                'original_settlement_id': reversal.originalSettlementId,
                'actor_member_id': reversal.actorMemberId,
                'reason': reversal.reason,
                'created_at': reversal.createdAt.toUtc().toIso8601String(),
              },
          ],
      };

  Future<void> createGroup({
    required String name,
    required List<String> memberNames,
    String emoji = '',
    String visibility = 'personal',
    bool salarySplitEnabled = false,
    List<Map<String, String>>? members,
  }) async {
    final response = await _request('POST', '/api/v1/groups', body: {
      'name': name,
      if (members == null) 'member_names': memberNames else 'members': members,
      'emoji': emoji,
      'visibility': visibility,
      'salary_split_enabled': salarySplitEnabled
    });
    _decode(response);
  }

  Future<void> updateGroup(String groupId, Map<String, dynamic> input) async {
    final response =
        await _request('PATCH', '/api/v1/groups/$groupId', body: input);
    _decode(response);
  }

  Future<void> addMember(String groupId,
      {required String name, required String phone}) async {
    final response = await _request(
      'POST',
      '/api/v1/groups/$groupId/members',
      body: {'name': name, 'phone': phone},
    );
    _decode(response);
  }

  Future<void> updateMember(
      String groupId, String memberId, Map<String, dynamic> input) async {
    final response = await _request(
      'PATCH',
      '/api/v1/groups/$groupId/members/$memberId',
      body: input,
    );
    _decode(response);
  }

  Future<List<Map<String, dynamic>>> status() async {
    final response = await _request('GET', '/api/v1/status');
    return (_decode(response)['contacts'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
  }

  Future<List<GroupInvitation>> invitations() async {
    final response = await _request('GET', '/api/v1/group-invitations');
    return ((_decode(response)['invitations'] as List<dynamic>?) ?? const [])
        .map((value) => GroupInvitation.fromJson(value as Map<String, dynamic>))
        .toList();
  }

  Future<void> respondInvitation(String groupId, bool accept) async {
    final response = await _request(
      'POST',
      '/api/v1/group-invitations/$groupId/response',
      body: {'accept': accept},
    );
    if (response.statusCode != 204) _decode(response);
  }

  Future<List<AppContact>> matchContacts(List<String> phones) async {
    final response = await _request(
      'POST',
      '/api/v1/contacts/matches',
      body: {'phones': phones},
    );
    return (_decode(response)['contacts'] as List<dynamic>)
        .map((value) => AppContact.fromJson(value as Map<String, dynamic>))
        .toList();
  }

  Future<List<AppContact>> listContacts() async {
    final response = await _request('GET', '/api/v1/contacts');
    return ((_decode(response)['contacts'] as List<dynamic>?) ?? const [])
        .map((value) => AppContact.fromJson(value as Map<String, dynamic>))
        .toList();
  }

  Future<List<AppContact>> saveContact(String name, String phone) async {
    return saveContacts([AppContact(id: '', name: name, phone: phone)]);
  }

  Future<List<AppContact>> saveContacts(List<AppContact> contacts) async {
    final response = await _request('POST', '/api/v1/contacts', body: {
      'contacts': [
        for (final contact in contacts)
          {'name': contact.name, 'phone': contact.phone}
      ]
    });
    return ((_decode(response)['contacts'] as List<dynamic>?) ?? const [])
        .map((value) => AppContact.fromJson(value as Map<String, dynamic>))
        .toList();
  }

  Future<void> removeContact(String contactId) async {
    final response = await _request('DELETE', '/api/v1/contacts/$contactId');
    if (response.statusCode != 204) _decode(response);
  }

  Future<void> addExpense({
    required String groupId,
    required String description,
    required int amountCents,
    required String payerId,
    required List<ExpensePayer> payers,
    required List<String> participantIds,
    String splitMode = 'equal',
    List<ExpenseShare> shares = const [],
    List<ExpensePercentage> percentages = const [],
    bool splitOverpayment = true,
    String? replacesExpenseId,
    String? idempotencyKey,
  }) async {
    final response = await _request(
      'POST',
      '/api/v1/groups/$groupId/expenses',
      headers: {'Idempotency-Key': idempotencyKey ?? _idempotencyKey()},
      body: {
        'description': description,
        'amount_cents': amountCents,
        'payer_id': payerId,
        'payers': [
          for (final payer in payers)
            {'member_id': payer.memberId, 'amount_cents': payer.amountCents},
        ],
        'participant_ids': participantIds,
        'split_mode': splitMode,
        'split_overpayment': splitOverpayment,
        'shares': [
          for (final share in shares)
            {'member_id': share.memberId, 'amount_cents': share.amountCents},
        ],
        if (percentages.isNotEmpty)
          'percentages': [
            for (final entry in percentages) entry.toJson(),
          ],
        if (replacesExpenseId != null && replacesExpenseId.isNotEmpty)
          'replaces_expense_id': replacesExpenseId,
      },
    );
    _decode(response);
  }

  Future<void> reverseExpense({
    required String groupId,
    required String expenseId,
    required String reason,
    String? idempotencyKey,
  }) async {
    final response = await _request(
      'POST',
      '/api/v1/groups/$groupId/expenses/$expenseId/reversals',
      headers: {'Idempotency-Key': idempotencyKey ?? _idempotencyKey()},
      body: {'reason': reason},
    );
    _decode(response);
  }

  Future<void> settleBalance({
    required String groupId,
    required String memberId,
    int? amountCents,
    String? replacesSettlementId,
    String? idempotencyKey,
  }) async {
    final response = await _request(
      'POST',
      '/api/v1/groups/$groupId/settlements',
      headers: {'Idempotency-Key': idempotencyKey ?? _idempotencyKey()},
      body: {
        'member_id': memberId,
        if (amountCents != null) 'amount_cents': amountCents,
        if (replacesSettlementId != null && replacesSettlementId.isNotEmpty)
          'replaces_settlement_id': replacesSettlementId,
      },
    );
    _decode(response);
  }

  Future<void> confirmReceivedPayment({
    required String groupId,
    required String debtorId,
    int? amountCents,
    String? replacesSettlementId,
    String? idempotencyKey,
  }) async {
    final response = await _request(
      'POST',
      '/api/v1/groups/$groupId/settlements/received',
      headers: {'Idempotency-Key': idempotencyKey ?? _idempotencyKey()},
      body: {
        'debtor_member_id': debtorId,
        if (amountCents != null) 'amount_cents': amountCents,
        if (replacesSettlementId != null && replacesSettlementId.isNotEmpty)
          'replaces_settlement_id': replacesSettlementId,
      },
    );
    _decode(response);
  }

  Future<void> reverseSettlement({
    required String groupId,
    required String settlementId,
    required String reason,
    String? idempotencyKey,
  }) async {
    final response = await _request(
      'POST',
      '/api/v1/groups/$groupId/settlements/$settlementId/reversals',
      headers: {'Idempotency-Key': idempotencyKey ?? _idempotencyKey()},
      body: {'reason': reason},
    );
    _decode(response);
  }

  Future<PaymentRequestPage> listPaymentRequests({
    String? status,
    String? orientation,
    String? groupId,
    int? limit,
    String? cursor,
  }) async {
    final query = <String, String>{};
    if (status != null && status.trim().isNotEmpty) {
      query['status'] = status.trim();
    }
    if (orientation != null && orientation.trim().isNotEmpty) {
      query['orientation'] = orientation.trim();
    }
    if (groupId != null && groupId.trim().isNotEmpty) {
      query['group_id'] = groupId.trim();
    }
    if (limit != null) {
      query['limit'] = '$limit';
    }
    if (cursor != null && cursor.trim().isNotEmpty) {
      query['cursor'] = cursor.trim();
    }
    final path = Uri(
      path: '/api/v1/payment-requests',
      queryParameters: query.isEmpty ? null : query,
    ).toString();
    final response = await _request('GET', path);
    final decoded = _decode(response);
    final items = ((decoded['payment_requests'] as List<dynamic>?) ?? const [])
        .map((value) =>
            PaymentRequestItem.fromJson(value as Map<String, dynamic>))
        .toList();
    final nextCursor = decoded['next_cursor'] as String?;
    return PaymentRequestPage(
      items: items,
      nextCursor:
          (nextCursor == null || nextCursor.trim().isEmpty) ? null : nextCursor,
    );
  }

  Future<PaymentRequestItem> getPaymentRequest(String requestId) async {
    final encodedId = Uri.encodeComponent(requestId.trim());
    final response =
        await _request('GET', '/api/v1/payment-requests/$encodedId');
    return PaymentRequestItem.fromJson(_decode(response));
  }

  Future<PaymentRequestItem?> requestPayment({
    required String groupId,
    required String debtorId,
    required int amountCents,
    required String description,
    String? idempotencyKey,
  }) async {
    final response =
        await _request('POST', '/api/v1/payment-requests', headers: {
      'Idempotency-Key': idempotencyKey ?? _idempotencyKey(),
    }, body: {
      'group_id': groupId,
      'debtor_id': debtorId,
      'amount_cents': amountCents,
      'currency': 'MXN',
      'description': description,
    });
    final decoded = _decode(response);
    if (decoded['id'] is String) {
      return PaymentRequestItem.fromJson(decoded);
    }
    return null;
  }

  Future<PaymentRequestItem> completeSimulatedPayment({
    required String requestId,
    required String providerEventId,
  }) async {
    final encodedId = Uri.encodeComponent(requestId.trim());
    final response = await _request(
      'POST',
      '/api/v1/payment-requests/$encodedId/simulate',
      body: {'provider_event_id': providerEventId},
    );
    return PaymentRequestItem.fromJson(_decode(response));
  }

  Future<void> removeMember(String groupId, String memberId) async {
    final response = await _request(
      'DELETE',
      '/api/v1/groups/$groupId/members/$memberId',
    );
    if (response.statusCode != 204) _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    late final Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _apiException(response);
      }
      rethrow;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _apiException(response, decoded);
    }
    return decoded;
  }

  Future<void> _authenticate(String path, Map<String, dynamic> input) async {
    final response =
        await _request('POST', path, body: input, authenticated: false);
    final result = _decode(response);
    _applySession(result);
  }

  Future<http.Response> _request(
    String method,
    String path, {
    Object? body,
    Map<String, String>? headers,
    bool authenticated = true,
    bool retryAfterRefresh = true,
  }) async {
    final response = await _send(method, path, body: body, headers: headers);
    if (response.statusCode != 401 ||
        !authenticated ||
        _token == null ||
        !_isAuthenticationFailure(response)) {
      return response;
    }
    if (retryAfterRefresh && _refreshToken != null) {
      final refreshed = await _refreshAccessToken();
      if (refreshed) {
        return _request(
          method,
          path,
          body: body,
          headers: headers,
          authenticated: authenticated,
          retryAfterRefresh: false,
        );
      }
    } else {
      await _invalidateSession();
    }
    return response;
  }

  Future<http.Response> _send(String method, String path,
      {Object? body, Map<String, String>? headers}) async {
    final request = http.Request(method, Uri.parse('$_baseUrl$path'));
    request.headers.addAll({
      'Content-Type': 'application/json',
      if (_token != null) 'Authorization': 'Bearer $_token',
      ...?headers,
    });
    if (body != null) request.body = jsonEncode(body);
    final streamed =
        await _client.send(request).timeout(const Duration(seconds: 8));
    return http.Response.fromStream(streamed);
  }

  String newIdempotencyKey() => _idempotencyKey();

  String _idempotencyKey() {
    final random = Random.secure();
    final suffix = List<int>.generate(16, (_) => random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return 'mobile-${DateTime.now().microsecondsSinceEpoch}-$suffix';
  }

  Future<bool> _refreshAccessToken() {
    final active = _refreshInProgress;
    if (active != null) return active;
    late final Future<bool> operation;
    operation = _performRefresh().whenComplete(() {
      if (identical(_refreshInProgress, operation)) _refreshInProgress = null;
    });
    _refreshInProgress = operation;
    return operation;
  }

  Future<bool> _performRefresh() async {
    final refreshToken = _refreshToken;
    if (refreshToken == null) return false;
    try {
      final response = await _send(
        'POST',
        '/api/v1/auth/refresh',
        body: {'refresh_token': refreshToken},
      );
      if (response.statusCode != 200) {
        final error = _apiException(response);
        if (error.code == 'invalid_refresh_token' ||
            error.code == 'authentication_required' ||
            (error.code == 'request_failed' && response.statusCode == 401)) {
          await _invalidateSession();
        }
        return false;
      }
      _applySession(_decode(response));
      await persistSession();
      return true;
    } catch (_) {
      // A transport failure leaves the existing session intact so a later
      // request can retry. Only an authoritative server rejection signs out.
      return false;
    }
  }

  void _applySession(Map<String, dynamic> result) {
    _token = result['access_token'] as String;
    _refreshToken = result['refresh_token'] as String;
    final user = result['user'] as Map<String, dynamic>?;
    _userId = user?['id'] as String?;
    if (user != null && user['id'] != null) _user = AppUser.fromJson(user);
  }

  bool _isAuthenticationFailure(http.Response response) {
    final code = _apiException(response).code;
    return code == 'authentication_required' || code == 'request_failed';
  }

  ApiException _apiException(
    http.Response response, [
    Map<String, dynamic>? decoded,
  ]) {
    Map<String, dynamic> body = decoded ?? const <String, dynamic>{};
    if (decoded == null) {
      try {
        body = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        // Non-JSON gateway responses still become a stable client error.
      }
    }
    final rawFields = body['fields'];
    final fields = rawFields is Map
        ? rawFields.map((key, value) => MapEntry('$key', '$value'))
        : const <String, String>{};
    final legacyMessage = body['error'] as String?;
    final code = body['code'] as String? ?? 'request_failed';
    return ApiException(
      code: code,
      message: body['message'] as String? ?? legacyMessage ?? 'request failed',
      statusCode: response.statusCode,
      correlationId: response.headers['x-correlation-id'],
      fields: fields,
    );
  }

  Future<void> _invalidateSession() async {
    await clearSession();
    onSessionInvalidated?.call();
  }

  void close() => _client.close();
}
