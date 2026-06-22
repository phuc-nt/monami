// Renders each RobotExpression headlessly and asserts it produces a valid PNG —
// this both catches paint/layout exceptions and gives a visual artifact for dev
// review. PNGs are written to build/robot_face_<expr>.png ONLY when the env var
// DUMP_ROBOT_FACE is set, so a normal `flutter test` stays side-effect-free:
//
//   DUMP_ROBOT_FACE=1 flutter test test/robot_face_render_test.dart   # write PNGs
//   flutter test                                                       # assert only

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monami_app/robot_face.dart';

Future<void> _renderExpression(WidgetTester tester, RobotExpression e) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF0B1016),
        body: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: 480,
              height: 300,
              child: RobotFace(expression: e),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));

  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  // toImage() + toByteData() are real async work; run them outside the fake-async
  // test zone so they complete despite the face's repeating animation ticker.
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    // Assert the painter produced a real (non-empty) image — catches paint or
    // layout exceptions for this expression.
    expect(bytes, isNotNull, reason: 'no image for ${e.name}');
    expect(bytes!.lengthInBytes, greaterThan(0), reason: 'empty image for ${e.name}');
    if (Platform.environment.containsKey('DUMP_ROBOT_FACE')) {
      final dir = Directory('build')..createSync(recursive: true);
      File('${dir.path}/robot_face_${e.name}.png')
          .writeAsBytesSync(bytes.buffer.asUint8List());
    }
    image.dispose();
  });
}

void main() {
  testWidgets('render every robot expression to PNG', (tester) async {
    for (final e in RobotExpression.values) {
      await _renderExpression(tester, e);
    }
    // Replace the animated widget with an empty frame so the repeating ticker is
    // disposed before the test ends (avoids a pending-timer hang).
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
