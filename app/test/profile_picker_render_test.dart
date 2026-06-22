// Dev-only: render the ProfilePicker screen to a PNG to eyeball the layout
// without a GUI. Asserts a valid image (catches build/layout exceptions).
//
//   DUMP_PICKER=1 flutter test test/profile_picker_render_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monami_app/profile_picker.dart';

void main() {
  testWidgets('ProfilePicker renders both children', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: key,
          child: SizedBox(
            width: 760,
            height: 560,
            child: ProfilePicker(onPick: (_) {}),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Vy'), findsOneWidget);
    expect(find.text('Phong'), findsOneWidget);

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
}
