// Generates the app icon: just the robot's smiling eyes (no mouth) as an LED
// dot-matrix, mint on a soft light gradient, square + filling the frame. Run:
//
//   DUMP_ICON=1 flutter test test/app_icon_render_test.dart
//
// then it writes app/assets/icon/app_icon.png (1024×1024, square, no alpha need
// — opaque background) which `dart run flutter_launcher_icons` turns into the
// platform icon sets.

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

// A square LED grid so the eyes sit centered with even margins (the app's face
// is 32×20; here we use a square grid because there's no mouth to place).
const int _cols = 22;
const int _rows = 22;

/// Paints two happy upward-curved "◠ ◠" eyes (no mouth), centered + filling the
/// square. Each eye is a downward-opening arc (a smiling-eye), drawn ~3 cells
/// thick so it reads boldly at icon sizes; the two eyes are clearly separated.
class _IconPainter extends CustomPainter {
  const _IconPainter();

  // Eye centers (col) + a shared baseline row; half-width controls the span.
  static const int _baseRow = 14; // arc corners sit here (vertically centered)
  static const int _halfW = 4; // eye spans cx-4 .. cx+4 (9 cells wide)
  static const int _leftCx = 6;
  static const int _rightCx = 16; // wider gap so the two eyes read distinctly
  static const int _thick = 3; // bolder arc line (3 cells thick)

  bool _eye(int cx, int c, int r) {
    final dx = c - cx;
    // Trim the very inner/outer corners so the arc tapers (no stray baseline
    // dots colliding between the two eyes).
    if (dx.abs() > _halfW) return false;
    final t = dx.abs() / _halfW; // 0 at center, 1 at corners
    if (t > 0.85) return false; // drop the extreme corner cell → clean taper
    // Smiling eye ◠: rises toward the center top. Bigger lift = rounder.
    final lift = ((1 - t * t) * 5).round(); // up to 5 rows higher at center
    final top = _baseRow - lift;
    return r >= top && r < top + _thick;
  }

  bool _lit(int c, int r) => _eye(_leftCx, c, r) || _eye(_rightCx, c, r);

  @override
  void paint(Canvas canvas, Size size) {
    // Soft light gradient (mint-tinted top → white) so the deeper-mint eyes read
    // on a bright App Store tile.
    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFD7F5EC), Color(0xFFFFFFFF)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);

    final cellW = size.width / _cols;
    final cellH = size.height / _rows;
    final dotR = math.min(cellW, cellH) * 0.42;

    const lit = Color(0xFF14B88A); // deeper mint to pop on light
    final litPaint = Paint()..color = lit;
    final glowPaint = Paint()
      ..color = lit.withValues(alpha: 0.28)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    final dimPaint = Paint()..color = lit.withValues(alpha: 0.07);

    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        final center = Offset(cellW * (c + 0.5), cellH * (r + 0.5));
        if (_lit(c, r)) {
          canvas.drawCircle(center, dotR * 1.7, glowPaint);
          canvas.drawCircle(center, dotR, litPaint);
        } else {
          canvas.drawCircle(center, dotR * 0.55, dimPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void main() {
  testWidgets('render app icon (smiling eyes, light gradient) to PNG',
      (tester) async {
    // Size the test surface so a 1024-logical-px box isn't constrained to the
    // default 800×600 window.
    tester.view.physicalSize = const Size(1024, 1024);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final key = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: key,
          child: const SizedBox(
            width: 1024,
            height: 1024,
            child: CustomPaint(painter: _IconPainter()),
          ),
        ),
      ),
    );
    await tester.pump();

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.0); // 1024×1024
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(bytes, isNotNull);
      expect(image.width, 1024);
      expect(image.height, 1024); // square — the whole point of the redesign
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
