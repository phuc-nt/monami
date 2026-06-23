// Dev-only: render a 1024x1024 app-icon source PNG (the happy robot face on a
// rounded dark screen, mint LEDs) to assets/icon/app_icon.png.
//
//   DUMP_ICON=1 flutter test test/app_icon_render_test.dart
//
// Then flutter_launcher_icons generates the iOS/macOS icon sets from it.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monami_app/robot_face.dart';

void main() {
  testWidgets('render app icon source', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: key,
          child: Container(
            // Solid background fills the square (icons can't be transparent on iOS).
            color: const Color(0xFF0B1016),
            width: 512,
            height: 512,
            child: const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: RobotFace(expression: RobotExpression.happy),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      // pixelRatio 2 → 1024x1024 output.
      final image = await boundary.toImage(pixelRatio: 2.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(bytes, isNotNull);
      if (Platform.environment.containsKey('DUMP_ICON')) {
        final dir = Directory('assets/icon')..createSync(recursive: true);
        File('${dir.path}/app_icon.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
      }
      image.dispose();
    });

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
