import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:monami_app/child_model.dart';
import 'package:monami_app/child_service.dart';

const _base = 'http://127.0.0.1:8000';
const _dev = 'devA';

ChildService _service(MockClient client, {String token = ''}) => ChildService(
      restBase: _base,
      deviceId: _dev,
      token: token,
      client: client,
    );

Map<String, dynamic> _childJson({String id = 'c1', String summary = ''}) => {
      'id': id,
      'name': 'Vy',
      'gender': 'girl',
      'age': 5,
      'interests': ['Elsa'],
      'created_at': null,
      'memory': {'summary': summary, 'updated_at': null},
    };

/// A JSON response encoded as UTF-8 bytes (like a real server) so the client's
/// `utf8.decode(bodyBytes)` round-trips VN diacritics. (A plain
/// `http.Response(string, ...)` defaults bodyBytes to latin1 and breaks on 'ớ'.)
http.Response _json(Object body, int status) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  test('listChildren parses a 200 array', () async {
    http.BaseRequest? seen;
    final svc = _service(MockClient((req) async {
      seen = req;
      return _json([_childJson()], 200);
    }));
    final list = await svc.listChildren();
    expect(list.single.id, 'c1');
    expect(seen!.method, 'GET');
    expect(seen!.url.path, '/devices/$_dev/children');
  });

  test('listChildren on empty array is an empty list (not an error)', () async {
    final svc = _service(MockClient((_) async => _json(<dynamic>[], 200)));
    expect(await svc.listChildren(), isEmpty);
  });

  test('listChildren throws typed error on non-2xx (distinct from empty)', () async {
    final svc = _service(MockClient((_) async => _json({'detail': 'boom'}, 500)));
    expect(svc.listChildren(), throwsA(isA<ChildServiceException>()));
  });

  test('network failure surfaces a typed, token-safe error', () async {
    final svc = _service(MockClient((_) async => throw Exception('socket down')));
    try {
      await svc.listChildren();
      fail('expected throw');
    } on ChildServiceException catch (e) {
      expect(e.toString(), isNot(contains('socket'))); // raw error masked
    }
  });

  test('createChild posts the profile body and returns 201 child', () async {
    http.Request? seen;
    final svc = _service(MockClient((req) async {
      seen = req;
      return _json(_childJson(id: 'new'), 201);
    }));
    final c = await svc.createChild(
      const Child(id: '', name: 'Vy', gender: ChildGender.girl, age: 5, interests: ['Elsa']),
    );
    expect(c.id, 'new');
    expect(seen!.method, 'POST');
    expect(jsonDecode(seen!.body),
        {'name': 'Vy', 'gender': 'girl', 'age': 5, 'interests': ['Elsa']});
  });

  test('updateChild PATCHes and returns 200 child', () async {
    http.BaseRequest? seen;
    final svc = _service(MockClient((req) async {
      seen = req;
      return _json(_childJson(id: 'c1'), 200);
    }));
    expect((await svc.updateChild('c1', {'age': 6})).id, 'c1');
    expect(seen!.method, 'PATCH');
    expect(seen!.url.path, '/devices/$_dev/children/c1');
  });

  test('deleteChild expects 204', () async {
    http.BaseRequest? seen;
    final svc = _service(MockClient((req) async {
      seen = req;
      return http.Response('', 204);
    }));
    await svc.deleteChild('c1'); // no throw
    expect(seen!.method, 'DELETE');
  });

  test('setMemory PATCHes memory + returns updated child', () async {
    // Capture the request OUTSIDE the handler — an `expect` failure inside the
    // MockClient callback would be swallowed by ChildService._guard.
    http.Request? seen;
    final svc = _service(MockClient((req) async {
      seen = req;
      return _json(_childJson(id: 'c1', summary: 'mới'), 200);
    }));
    final updated = await svc.setMemory('c1', 'mới');
    expect(updated.memorySummary, 'mới');
    expect(seen!.url.path, '/devices/$_dev/children/c1/memory');
    expect(jsonDecode(seen!.body), {'summary': 'mới'});
  });

  test('clearMemory DELETEs memory + returns child with empty summary', () async {
    http.BaseRequest? seen;
    final svc = _service(MockClient((req) async {
      seen = req;
      return _json(_childJson(id: 'c1', summary: ''), 200);
    }));
    expect((await svc.clearMemory('c1')).memorySummary, '');
    expect(seen!.method, 'DELETE');
    expect(seen!.url.path, '/devices/$_dev/children/c1/memory');
  });

  test('token is sent as a query param when set', () async {
    http.BaseRequest? seen;
    final svc = _service(
      MockClient((req) async {
        seen = req;
        return _json(<dynamic>[], 200);
      }),
      token: 'secret',
    );
    await svc.listChildren();
    expect(seen!.url.queryParameters['token'], 'secret');
  });
}
