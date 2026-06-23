// REST client for per-device child profiles + memory.
//
// Wraps the backend's 6 endpoints (see backend/child_rest_api.py), all scoped
// under this install's deviceId and gated by the same shared token as the WS.
// Base URL = AppConfig.restBase (the origin of the WS URL).
//
// Errors are TYPED so the UI can tell a real "no children yet" (a successful
// empty list) apart from a network/timeout/backend failure — the picker must
// NOT show an empty state on a failed fetch (a parent would re-create a child).
//
// The deviceId + token are bearer secrets: they go in the URL/query only at
// request time and are NEVER logged. `ChildServiceException.toString` omits them.

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'child_model.dart';

/// A REST call failed (network, timeout, or non-2xx). Distinct from an empty
/// list. The message is safe to surface; it never includes the token/deviceId.
class ChildServiceException implements Exception {
  ChildServiceException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => 'ChildServiceException($message)';
}

class ChildService {
  ChildService({
    required this.restBase,
    required this.deviceId,
    this.token = '',
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client();

  final String restBase;
  final String deviceId;
  final String token;
  final Duration timeout;
  final http.Client _client;

  Uri _uri(String path) {
    final query = token.isEmpty ? <String, String>{} : {'token': token};
    return Uri.parse('$restBase$path').replace(queryParameters: query.isEmpty ? null : query);
  }

  String get _base => '/devices/$deviceId/children';

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on ChildServiceException {
      rethrow;
    } catch (_) {
      // Swallow the raw error (it can carry the URL incl. token); surface a
      // generic, safe message.
      throw ChildServiceException('không kết nối được máy chủ');
    }
  }

  Never _httpError(http.Response r) {
    // Body may echo back input but never the token; still keep the message terse.
    throw ChildServiceException('máy chủ trả lỗi (${r.statusCode})', statusCode: r.statusCode);
  }

  /// GET the children for this device. A 2xx empty array is a real empty list;
  /// any failure throws [ChildServiceException] (so callers don't confuse the two).
  Future<List<Child>> listChildren() => _guard(() async {
        final r = await _client.get(_uri(_base)).timeout(timeout);
        if (r.statusCode != 200) _httpError(r);
        final data = jsonDecode(utf8.decode(r.bodyBytes)) as List<dynamic>;
        return data.map((e) => Child.fromJson(e as Map<String, dynamic>)).toList();
      });

  Future<Child> createChild(Child child) => _guard(() async {
        final r = await _client
            .post(_uri(_base),
                headers: _jsonHeaders, body: jsonEncode(child.toProfileJson()))
            .timeout(timeout);
        if (r.statusCode != 201) _httpError(r);
        return Child.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
      });

  Future<Child> updateChild(String childId, Map<String, dynamic> fields) =>
      _guard(() async {
        final r = await _client
            .patch(_uri('$_base/$childId'),
                headers: _jsonHeaders, body: jsonEncode(fields))
            .timeout(timeout);
        if (r.statusCode != 200) _httpError(r);
        return Child.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
      });

  Future<void> deleteChild(String childId) => _guard(() async {
        final r = await _client.delete(_uri('$_base/$childId')).timeout(timeout);
        if (r.statusCode != 204) _httpError(r);
      });

  Future<Child> setMemory(String childId, String summary) => _guard(() async {
        final r = await _client
            .patch(_uri('$_base/$childId/memory'),
                headers: _jsonHeaders, body: jsonEncode({'summary': summary}))
            .timeout(timeout);
        if (r.statusCode != 200) _httpError(r);
        return Child.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
      });

  Future<Child> clearMemory(String childId) => _guard(() async {
        final r = await _client.delete(_uri('$_base/$childId/memory')).timeout(timeout);
        if (r.statusCode != 200) _httpError(r);
        return Child.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
      });

  static const _jsonHeaders = {'content-type': 'application/json'};

  void dispose() => _client.close();
}
