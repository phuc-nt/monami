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
  // A tall surface so the form's ListView lays out the bottom CTA (find.text /
  // tap can't reach a lazily-unbuilt off-screen ListView child).
  Future<void> pumpForm(WidgetTester tester, ChildFormScreen form) async {
    tester.view.physicalSize = const Size(440 * 3, 1200 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: form));
    await tester.pump();
  }

  testWidgets('create form renders its fields', (tester) async {
    await pumpForm(tester, ChildFormScreen(service: _captureService((_) {})));
    expect(find.text('Bé mới'), findsOneWidget); // create-mode heading
    expect(find.text('Thêm bé'), findsWidgets); // the CTA
    expect(find.text('Tên bé'), findsOneWidget);
    expect(find.text('Bạn gái'), findsOneWidget);
    expect(find.text('Bạn trai'), findsOneWidget);
  });

  testWidgets('blocks save with no name (validation)', (tester) async {
    var posted = false;
    await pumpForm(
        tester, ChildFormScreen(service: _captureService((_) => posted = true)));
    // Tap the CTA (a flat-art FaPressable, not a Material button) by its text.
    await tester.tap(find.text('Thêm bé'));
    await tester.pump();
    expect(find.text('Hãy nhập tên bé'), findsOneWidget);
    expect(posted, isFalse); // never hit the network without a name
  });

  testWidgets('blocks save with no gender, never posts', (tester) async {
    var posted = false;
    await pumpForm(
        tester, ChildFormScreen(service: _captureService((_) => posted = true)));
    // Enter a valid name but pick NO gender → save must surface the gender error.
    await tester.enterText(find.byType(TextFormField), 'Su');
    await tester.tap(find.text('Thêm bé'));
    await tester.pump();
    expect(find.text('Hãy chọn bạn trai hoặc bạn gái'), findsOneWidget);
    expect(posted, isFalse);
  });

  testWidgets('409 from the backend shows the soft-cap message', (tester) async {
    final client = MockClient((req) async => http.Response('cap', 409));
    final service =
        ChildService(restBase: 'http://x', deviceId: 'd', client: client);
    await pumpForm(tester, ChildFormScreen(service: service));
    await tester.enterText(find.byType(TextFormField), 'Su');
    await tester.tap(find.text('Bạn gái')); // pick a gender so it reaches the POST
    await tester.pump();
    await tester.tap(find.text('Thêm bé'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Đã đủ 5 bé'), findsOneWidget);
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
