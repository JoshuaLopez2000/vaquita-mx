import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:vaquita_mx/src/models.dart';

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({required String baseUrl, http.Client? client})
      : _baseUrl = baseUrl.replaceAll(RegExp(r'/$'), ''),
        _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;
  static const _storage = FlutterSecureStorage();
  static const _sessionTokenKey = 'session_token';
  static const _sessionUserKey = 'session_user';
  String? _token;
  String? _userId;
  AppUser? _user;
  String? get userId => _userId;
  AppUser? get user => _user;

  Future<bool> restoreSession() async {
    final token = await _storage.read(key: _sessionTokenKey);
    final encodedUser = await _storage.read(key: _sessionUserKey);
    if (token == null || encodedUser == null) return false;
    try {
      final user = AppUser.fromJson(
          jsonDecode(encodedUser) as Map<String, dynamic>);
      _token = token;
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
    await _storage.write(key: _sessionTokenKey, value: _token);
    await _storage.write(
      key: _sessionUserKey,
      value: jsonEncode({
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
    _user = null;
    _userId = null;
    await _storage.delete(key: _sessionTokenKey);
    await _storage.delete(key: _sessionUserKey);
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

  Future<List<ExpenseGroup>> listGroups() async {
    final response = await _client
        .get(Uri.parse('$_baseUrl/api/v1/groups'), headers: _headers())
        .timeout(const Duration(seconds: 8));
    final body = _decode(response);
    return ((body['groups'] as List<dynamic>?) ?? const [])
        .map((value) => ExpenseGroup.fromJson(value as Map<String, dynamic>))
        .toList();
  }

  Future<void> createGroup({
    required String name,
    required List<String> memberNames,
    String emoji = '',
    String visibility = 'personal',
    bool salarySplitEnabled = false,
    List<Map<String, String>>? members,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$_baseUrl/api/v1/groups'),
          headers: _headers(),
          body: jsonEncode({
            'name': name,
            if (members == null)
              'member_names': memberNames
            else
              'members': members,
            'emoji': emoji,
            'visibility': visibility,
            'salary_split_enabled': salarySplitEnabled
          }),
        )
        .timeout(const Duration(seconds: 8));
    _decode(response);
  }

  Future<void> updateGroup(String groupId, Map<String, dynamic> input) async {
    final response = await _client
        .patch(Uri.parse('$_baseUrl/api/v1/groups/$groupId'),
            headers: _headers(), body: jsonEncode(input))
        .timeout(const Duration(seconds: 8));
    _decode(response);
  }

  Future<void> addMember(String groupId,
      {required String name, required String phone}) async {
    final response = await _client
        .post(Uri.parse('$_baseUrl/api/v1/groups/$groupId/members'),
            headers: _headers(),
            body: jsonEncode({'name': name, 'phone': phone}))
        .timeout(const Duration(seconds: 8));
    _decode(response);
  }

  Future<void> updateMember(
      String groupId, String memberId, Map<String, dynamic> input) async {
    final response = await _client
        .patch(Uri.parse('$_baseUrl/api/v1/groups/$groupId/members/$memberId'),
            headers: _headers(), body: jsonEncode(input))
        .timeout(const Duration(seconds: 8));
    _decode(response);
  }

  Future<List<Map<String, dynamic>>> status() async {
    final response = await _client
        .get(Uri.parse('$_baseUrl/api/v1/status'), headers: _headers())
        .timeout(const Duration(seconds: 8));
    return (_decode(response)['contacts'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
  }

  Future<List<GroupInvitation>> invitations() async {
    final response = await _client
        .get(Uri.parse('$_baseUrl/api/v1/group-invitations'),
            headers: _headers())
        .timeout(const Duration(seconds: 8));
    return ((_decode(response)['invitations'] as List<dynamic>?) ?? const [])
        .map((value) => GroupInvitation.fromJson(value as Map<String, dynamic>))
        .toList();
  }

  Future<void> respondInvitation(String groupId, bool accept) async {
    final response = await _client
        .post(Uri.parse('$_baseUrl/api/v1/group-invitations/$groupId/response'),
            headers: _headers(), body: jsonEncode({'accept': accept}))
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 204) _decode(response);
  }

  Future<List<AppContact>> matchContacts(List<String> phones) async {
    final response = await _client
        .post(Uri.parse('$_baseUrl/api/v1/contacts/matches'),
            headers: _headers(), body: jsonEncode({'phones': phones}))
        .timeout(const Duration(seconds: 8));
    return (_decode(response)['contacts'] as List<dynamic>)
        .map((value) => AppContact.fromJson(value as Map<String, dynamic>))
        .toList();
  }

  Future<List<AppContact>> listContacts() async {
    final response = await _client
        .get(Uri.parse('$_baseUrl/api/v1/contacts'), headers: _headers())
        .timeout(const Duration(seconds: 8));
    return ((_decode(response)['contacts'] as List<dynamic>?) ?? const [])
        .map((value) => AppContact.fromJson(value as Map<String, dynamic>))
        .toList();
  }

  Future<List<AppContact>> saveContact(String name, String phone) async {
    return saveContacts([AppContact(id: '', name: name, phone: phone)]);
  }

  Future<List<AppContact>> saveContacts(List<AppContact> contacts) async {
    final response = await _client
        .post(Uri.parse('$_baseUrl/api/v1/contacts'),
            headers: _headers(),
            body: jsonEncode({
              'contacts': [
                for (final contact in contacts)
                  {'name': contact.name, 'phone': contact.phone}
              ]
            }))
        .timeout(const Duration(seconds: 8));
    return ((_decode(response)['contacts'] as List<dynamic>?) ?? const [])
        .map((value) => AppContact.fromJson(value as Map<String, dynamic>))
        .toList();
  }

  Future<void> removeContact(String contactId) async {
    final response = await _client
        .delete(Uri.parse('$_baseUrl/api/v1/contacts/$contactId'),
            headers: _headers())
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 204) _decode(response);
  }

  Future<void> addExpense({
    required String groupId,
    required String description,
    required int amountCents,
    required String payerId,
    required List<String> participantIds,
    String splitMode = 'equal',
  }) async {
    final response = await _client
        .post(
          Uri.parse('$_baseUrl/api/v1/groups/$groupId/expenses'),
          headers: _headers(),
          body: jsonEncode({
            'description': description,
            'amount_cents': amountCents,
            'payer_id': payerId,
            'participant_ids': participantIds,
            'split_mode': splitMode,
          }),
        )
        .timeout(const Duration(seconds: 8));
    _decode(response);
  }

  Future<void> settleBalance({
    required String groupId,
    required String memberId,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$_baseUrl/api/v1/groups/$groupId/settlements'),
          headers: _headers(),
          body: jsonEncode({'member_id': memberId}),
        )
        .timeout(const Duration(seconds: 8));
    _decode(response);
  }

  Future<void> removeMember(String groupId, String memberId) async {
    final response = await _client
        .delete(Uri.parse('$_baseUrl/api/v1/groups/$groupId/members/$memberId'),
            headers: _headers())
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 204) _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(decoded['error'] as String? ?? 'Request failed');
    }
    return decoded;
  }

  Future<void> _authenticate(String path, Map<String, dynamic> input) async {
    final response = await _client
        .post(
          Uri.parse('$_baseUrl$path'),
          headers: _headers(),
          body: jsonEncode(input),
        )
        .timeout(const Duration(seconds: 8));
    final result = _decode(response);
    _token = result['token'] as String;
    final user = result['user'] as Map<String, dynamic>?;
    _userId = user?['id'] as String?;
    if (user != null && user['id'] != null) _user = AppUser.fromJson(user);
  }

  Map<String, String> _headers() => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  void close() => _client.close();
}
