// Dev-only: render the VoiceHome visual layout in each voice state to PNGs so the
// UI can be reviewed without a backend/mic. Reproduces the screen's structure
// (robot face + status line + talk button) with a fixed expression/label per
// state — it does NOT use the real controller (which needs native plugins).
//
//   DUMP_STATES=1 flutter test test/voice_screen_states_render_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monami_app/app_theme.dart';
import 'package:monami_app/robot_face.dart';

class _Spec {
  const _Spec(this.name, this.expr, this.label, this.color, this.button, this.btnColor);
  final String name;
  final RobotExpression expr;
  final String label;
  final Color color;
  final String button;
  final Color btnColor;
}

const _specs = [
  _Spec('connecting', RobotExpression.sleepy, 'Đang đánh thức bạn nhỏ…',
      Colors.amberAccent, 'Đợi một chút…', Colors.grey),
  _Spec('idle', RobotExpression.calm, 'Sẵn sàng — chạm để nói',
      Colors.greenAccent, 'Chạm để nói', Colors.indigo),
  _Spec('listening', RobotExpression.attentive, 'Đang nghe bé…',
      Colors.redAccent, 'Đang nghe… (chạm để dừng)', Colors.red),
  _Spec('speaking', RobotExpression.talking, 'Đang trả lời…',
      Colors.lightBlueAccent, 'Đang nghe… (chạm để dừng)', Colors.red),
];

Widget _screen(_Spec s, Color tint) {
  final showStatus = s.name == 'connecting'; // kid screen hides status otherwise
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const Icon(Icons.arrow_back, color: Colors.white),
        title: const Text('Bạn của Vy', style: TextStyle(color: Colors.white)),
        centerTitle: true,
      ),
      body: Container(
        decoration: childBackground(tint),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            colors: [tint.withValues(alpha: 0.22), Colors.transparent],
                            radius: 0.7,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: RobotFace(expression: s.expr, litColor: tint),
                        ),
                      ),
                    ),
                  ),
                ),
                if (showStatus) ...[
                  const SizedBox(height: 12),
                  Text(s.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: s.color, fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 20),
                Container(
                  height: 96,
                  decoration: BoxDecoration(
                    color: s.btnColor,
                    borderRadius: BorderRadius.circular(48),
                    boxShadow: [
                      BoxShadow(color: s.btnColor.withValues(alpha: 0.5), blurRadius: 20),
                    ],
                  ),
                  child: Center(
                    child: Text(s.button,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('render voice screen states', (tester) async {
    tester.view.physicalSize = const Size(393 * 3, 852 * 3); // iPhone-ish
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    for (final s in _specs) {
      final key = GlobalKey();
      await tester.pumpWidget(
        Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(width: 393, height: 852, child: _screen(s, const Color(0xFFE8A0D8))),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2.0);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        expect(bytes, isNotNull);
        if (Platform.environment.containsKey('DUMP_STATES')) {
          final dir = Directory('build')..createSync(recursive: true);
          File('${dir.path}/voice_${s.name}.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
        }
        image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
