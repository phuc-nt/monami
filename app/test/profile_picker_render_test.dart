// Dev-only: render the service-backed ProfilePicker to a PNG to eyeball layout
// without a GUI. Uses a MockClient so it never hits a real backend. Asserts the
// children load + render (catches build/layout exceptions).
//
//   DUMP_PICKER=1 flutter test test/profile_picker_render_test.dart

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:monami_app/child_service.dart';
import 'package:monami_app/profile_picker.dart';

ChildService _serviceReturning(List<Map<String, dynamic>> children) {
  final client = MockClient((req) async => http.Response.bytes(
        utf8.encode(jsonEncode(children)),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ));
  return ChildService(restBase: 'http://x', deviceId: 'd', client: client);
}

Map<String, dynamic> _child(String id, String name, String gender) => {
      'id': id,
      'name': name,
      'gender': gender,
      'age': 5,
      'interests': const <String>[],
      'created_at': null,
      'memory': {'summary': '', 'updated_at': null},
    };

void main() {
  testWidgets('ProfilePicker renders children from the service', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: key,
          child: SizedBox(
            width: 760,
            height: 560,
            child: ProfilePicker(
              service: _serviceReturning([
                _child('c1', 'Vy', 'girl'),
                _child('c2', 'Phong', 'boy'),
              ]),
              onPick: (_) {},
              onGuest: () {},
            ),
          ),
        ),
      ),
    );
    // Let the async list load resolve.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Vy'), findsOneWidget);
    expect(find.text('Phong'), findsOneWidget);
    expect(find.text('Thêm bé'), findsOneWidget); // add card (under cap)

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(bytes, isNotNull);
      if (Platform.environment.containsKey('DUMP_PICKER')) {
        final dir = Directory('build')..createSync(recursive: true);
        File('${dir.path}/profile_picker.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
      }
      image.dispose();
    });

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('empty result shows the add-first empty state, not an error',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ProfilePicker(
        service: _serviceReturning([]),
        onPick: (_) {},
        onGuest: () {},
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Thêm bé để bắt đầu'), findsOneWidget);
    expect(find.text('Thêm bé'), findsOneWidget);
  });
}
