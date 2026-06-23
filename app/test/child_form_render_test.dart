// Render + basic interaction test for the create/edit child form. Uses a
// MockClient-backed service so it never hits a real backend.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:monami_app/child_form_screen.dart';
import 'package:monami_app/child_model.dart';
import 'package:monami_app/child_service.dart';

ChildService _captureService(void Function(http.Request) onPost) {
  final client = MockClient((req) async {
    if (req.method == 'POST') onPost(req);
    return http.Response.bytes(
      utf8.encode(jsonEncode({
        'id': 'new',
        'name': 'Vy',
        'gender': 'girl',
        'age': 5,
        'interests': const <String>[],
        'created_at': null,
        'memory': {'summary': '', 'updated_at': null},
      })),
      201,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
  return ChildService(restBase: 'http://x', deviceId: 'd', client: client);
}

void main() {
  testWidgets('create form renders its fields', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ChildFormScreen(service: _captureService((_) {})),
    ));
    await tester.pump();
    expect(find.text('Thêm bé'), findsWidgets);
    expect(find.text('Tên bé'), findsOneWidget);
    expect(find.text('Bạn gái'), findsOneWidget);
    expect(find.text('Bạn trai'), findsOneWidget);
  });

  testWidgets('blocks save with no name (validation)', (tester) async {
    var posted = false;
    await tester.pumpWidget(MaterialApp(
      home: ChildFormScreen(service: _captureService((_) => posted = true)),
    ));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Thêm bé'));
    await tester.pump();
    expect(find.text('Hãy nhập tên bé'), findsOneWidget);
    expect(posted, isFalse); // never hit the network without a name
  });

  testWidgets('edit mode prefills the existing child', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ChildFormScreen(
        service: _captureService((_) {}),
        existing: const Child(
            id: 'c1', name: 'Phong', gender: ChildGender.boy, age: 6),
      ),
    ));
    await tester.pump();
    expect(find.text('Sửa thông tin bé'), findsOneWidget);
    expect(find.text('Phong'), findsOneWidget); // name prefilled
  });
}
