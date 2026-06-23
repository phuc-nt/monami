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

Future<void> _renderExpression(
    WidgetTester tester, RobotExpression e, FaceVariant v) async {
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
              child: RobotFace(expression: e, variant: v),
            ),
          ),
        ),
      ),
    ),
  );

  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;

  // Capture a few animation frames so movement (blink, mouth, hop, dart) is
  // visible and the painter is exercised across phases.
  for (var frame = 0; frame < 3; frame++) {
    await tester.pump(const Duration(milliseconds: 700));
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(bytes, isNotNull, reason: 'no image for ${v.name}/${e.name}');
      expect(bytes!.lengthInBytes, greaterThan(0),
          reason: 'empty image for ${v.name}/${e.name}');
      if (Platform.environment.containsKey('DUMP_ROBOT_FACE')) {
        final dir = Directory('build')..createSync(recursive: true);
        File('${dir.path}/robot_face_${v.name}_${e.name}_$frame.png')
            .writeAsBytesSync(bytes.buffer.asUint8List());
      }
      image.dispose();
    });
  }
}

/// Dump one side-by-side PNG per expression: girl | boy | neutral, so the
/// variants can be compared at a glance. Only writes when DUMP_ROBOT_FACE is set.
Future<void> _renderVariantRow(
    WidgetTester tester, RobotExpression e) async {
  final key = GlobalKey();
  Color tint(FaceVariant v) => switch (v) {
        FaceVariant.girl => const Color(0xFFE8A0D8),
        FaceVariant.boy => const Color(0xFF7CC4F6),
        FaceVariant.neutral => const Color(0xFF9FA8B2),
      };
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF0B1016),
        body: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: 960,
              height: 220,
              child: Row(
                children: [
                  for (final v in FaceVariant.values)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: RobotFace(
                            expression: e, variant: v, litColor: tint(v)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.pump(const Duration(milliseconds: 300));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    expect(bytes, isNotNull);
    if (Platform.environment.containsKey('DUMP_ROBOT_FACE')) {
      final dir = Directory('build')..createSync(recursive: true);
      File('${dir.path}/robot_face_compare_${e.name}.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    }
    image.dispose();
  });
}

void main() {
  testWidgets('render every expression × variant to PNG', (tester) async {
    for (final v in FaceVariant.values) {
      for (final e in RobotExpression.values) {
        await _renderExpression(tester, e, v);
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('dump girl|boy|neutral comparison rows', (tester) async {
    for (final e in RobotExpression.values) {
      await _renderVariantRow(tester, e);
    }
    // Dispose the repeating ticker before the test ends.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // Lock in that the three variants actually render DIFFERENTLY at the painter
  // level (not just map to different enums) — guards against a refactor silently
  // disabling square/lash/antenna. All three are pumped to the SAME animation
  // phase so only the variant differs.
  testWidgets('girl / boy / neutral render to distinct pixels', (tester) async {
    Future<List<int>> shot(FaceVariant v) async {
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF0B1016),
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 320,
                height: 200,
                child: RobotFace(expression: RobotExpression.calm, variant: v),
              ),
            ),
          ),
        ),
      ));
      // Pin to the same phase for every variant so only the shape differs.
      await tester.pump(const Duration(milliseconds: 100));
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      late List<int> bytes;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2.0);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        bytes = data!.buffer.asUint8List();
        image.dispose();
      });
      return bytes;
    }

    final girl = await shot(FaceVariant.girl);
    final boy = await shot(FaceVariant.boy);
    final neutral = await shot(FaceVariant.neutral);
    bool same(List<int> a, List<int> b) =>
        a.length == b.length &&
        List.generate(a.length, (i) => a[i] == b[i]).every((x) => x);
    expect(same(girl, boy), isFalse, reason: 'girl and boy must differ');
    expect(same(girl, neutral), isFalse, reason: 'girl and neutral must differ');
    expect(same(boy, neutral), isFalse, reason: 'boy and neutral must differ');

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
