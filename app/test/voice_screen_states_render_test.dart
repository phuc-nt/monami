// Dev-only: render the Sticker-Scene voice layout in each voice state to PNGs so
// the UI can be reviewed without a backend/mic. Reproduces the screen's structure
// (scene backdrop + standing robot + speech bubble + talk pill) with a fixed
// expression/label per state — it does NOT use the real controller (which needs
// native plugins). Also asserts the per-state talk-lock + label mapping.
//
//   DUMP_STATES=1 flutter test test/voice_screen_states_render_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monami_app/robot_face.dart';
import 'package:monami_app/scene/flat_art_kit.dart';
import 'package:monami_app/scene/scene_widgets.dart';
import 'package:monami_app/scene/scene_worlds.dart';

class _Spec {
  const _Spec(this.name, this.expr, this.bubble, this.button, this.ready);
  final String name;
  final RobotExpression expr;
  final String bubble;
  final String button;
  final bool ready; // talk button enabled?
}

// Mirrors the real VoiceHome mapping: locked on connecting+disconnected.
const _specs = [
  _Spec('connecting', RobotExpression.sleepy, 'Mình đang thức dậy…',
      'Đợi một chút…', false),
  _Spec('idle', RobotExpression.calm, 'Chạm để nói với mình nhé!',
      'Chạm để nói', true),
  _Spec('listening', RobotExpression.attentive, 'Mình đang nghe nè…',
      'Chạm để dừng', true),
  _Spec('speaking', RobotExpression.talking, 'Để mình kể cho nghe…',
      'Chạm để dừng', true),
  _Spec('disconnected', RobotExpression.sleepy, 'Ơ, mất kết nối rồi',
      'Chưa sẵn sàng', false),
];

Widget _screen(_Spec s) {
  final spec = specForId('night');
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: SceneBackdrop(
        spec: spec,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Spacer(),
                SpeechBubble(
                    text: s.bubble, color: spec.bubbleColor, ink: spec.bubbleInk),
                const SizedBox(height: 8),
                StandingRobot(
                  expression: s.expr,
                  variant: FaceVariant.girl,
                  bodyColor: FlatArt.magenta,
                ),
                const Spacer(),
                // Talk pill: grey + disabled label when not ready (lock).
                Container(
                  height: 76,
                  decoration: BoxDecoration(
                    color: s.ready ? spec.talkColor : const Color(0xFFC9CFD8),
                    borderRadius: BorderRadius.circular(38),
                    border: inkBorder(3.5),
                    boxShadow: hardShadow(offset: const Offset(0, 6)),
                  ),
                  child: Center(
                      child:
                          Text(s.button, style: faFont(20, w: FontWeight.w800))),
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
  // NOTE: the talk-button LOCK (disabled during connecting/disconnected) is
  // enforced AND tested at the controller boundary — VoiceController.toggleMic()
  // returns early on those states (see voice_controller.dart + echo_gate_test).
  // This file is a dev-only PNG render smoke check; it does not re-assert the lock
  // (a same-file literal would be a phantom test).

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
            child: SizedBox(width: 393, height: 852, child: _screen(s)),
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
