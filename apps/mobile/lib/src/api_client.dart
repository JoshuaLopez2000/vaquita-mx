import 'dart:convert';

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
  String? _token;

  Future<void> login({required String email, required String password}) =>
      _authenticate('/api/v1/auth/login', {'email': email, 'password': password});

  Future<void> register({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) => _authenticate('/api/v1/auth/register', {
        'name': name,
        'email': email,
        'phone': phone,
        'password': password,
      });

  Future<List<ExpenseGroup>> listGroups() async {
    final response = await _client
        .get(Uri.parse('$_baseUrl/api/v1/groups'), headers: _headers())
        .timeout(const Duration(seconds: 8));
    final body = _decode(response);
    return (body['groups'] as List<dynamic>)
        .map((value) => ExpenseGroup.fromJson(value as Map<String, dynamic>))
        .toList();
  }

  Future<void> createGroup({
    required String name,
    required List<String> memberNames,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$_baseUrl/api/v1/groups'),
          headers: _headers(),
          body: jsonEncode({'name': name, 'member_names': memberNames}),
        )
        .timeout(const Duration(seconds: 8));
    _decode(response);
  }

  Future<List<AppContact>> matchContacts(List<String> phones) async {
    final response = await _client.post(Uri.parse('$_baseUrl/api/v1/contacts/matches'), headers: _headers(), body: jsonEncode({'phones': phones})).timeout(const Duration(seconds: 8));
    return (_decode(response)['contacts'] as List<dynamic>).map((value) => AppContact.fromJson(value as Map<String, dynamic>)).toList();
  }

  Future<void> addExpense({
    required String groupId,
    required String description,
    required int amountCents,
    required String payerId,
    required List<String> participantIds,
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

  Map<String, dynamic> _decode(http.Response response) {
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(decoded['error'] as String? ?? 'Request failed');
    }
    return decoded;
  }

  Future<void> _authenticate(String path, Map<String, String> input) async {
    final response = await _client
        .post(
          Uri.parse('$_baseUrl$path'),
          headers: _headers(),
          body: jsonEncode(input),
        )
        .timeout(const Duration(seconds: 8));
    _token = _decode(response)['token'] as String;
  }

  Map<String, String> _headers() => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  void close() => _client.close();
}
