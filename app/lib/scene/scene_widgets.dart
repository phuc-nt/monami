// Shared, data-agnostic Sticker-Scene widgets used by the picker / voice / form
// screens: an animated world backdrop, a comic speech bubble, and the standing
// robot character. Extracted from the approved UI preview (scene_flow.dart) and
// parameterized on a SceneSpec + plain values — no app data types here, so the
// real screens own the data/state wiring.

import 'package:flutter/material.dart';

import '../robot_face.dart';
import 'flat_art_kit.dart';
import 'scene_spec.dart';

// ── Animated backdrop: gradient sky/water + the world's painted props ─────────

/// The world background: a gradient sky + the spec's prop painter, animated by a
/// single shared 20s controller. Wrap content as [child]. RepaintBoundary keeps
/// the (constantly repainting) backdrop from invalidating the content above it.
class SceneBackdrop extends StatefulWidget {
  const SceneBackdrop({super.key, required this.spec, required this.child});
  final SceneSpec spec;
  final Widget child;
  @override
  State<SceneBackdrop> createState() => _SceneBackdropState();
}

class _SceneBackdropState extends State<SceneBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 20))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.spec;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: s.skyColors,
          stops: s.skyStops,
        ),
      ),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) => CustomPaint(
          painter: _BackdropPainter(spec: s, t: _c.value),
          child: child,
        ),
        child: RepaintBoundary(child: widget.child),
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter({required this.spec, required this.t});
  final SceneSpec spec;
  final double t;
  @override
  void paint(Canvas canvas, Size size) => spec.paint(canvas, size, t);
  @override
  bool shouldRepaint(_BackdropPainter old) => old.t != t || old.spec != spec;
}

// ── Comic speech bubble (shared) ──────────────────────────────────────────────

class SpeechBubble extends StatelessWidget {
  const SpeechBubble(
      {super.key, required this.text, required this.color, required this.ink});
  final String text;
  final Color color;
  final Color ink;
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FaBlock(
          color: color,
          radius: 18,
          shadowOffset: const Offset(0, 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Text(text, style: faFont(15, w: FontWeight.w800, c: ink)),
        ),
        Transform.translate(
          offset: const Offset(0, -2),
          child: CustomPaint(
              size: const Size(18, 10), painter: _TailPainter(color)),
        ),
      ],
    );
  }
}

class _TailPainter extends CustomPainter {
  _TailPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width * 0.35, size.height)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
    canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = FlatArt.ink);
  }

  @override
  bool shouldRepaint(_TailPainter old) => old.color != color;
}

// ── Standing robot character (shared) ─────────────────────────────────────────

/// The robot as a character: a colored body block housing the dark LED screen +
/// face, on two little legs. [bodyColor] is the per-child tint; [variant] +
/// [expression] drive the face.
class StandingRobot extends StatelessWidget {
  const StandingRobot({
    super.key,
    required this.expression,
    required this.variant,
    required this.bodyColor,
    this.width = 290,
    this.bloom = 1.8,
    this.legGap = 40,
  });
  final RobotExpression expression;
  final FaceVariant variant;
  final Color bodyColor;
  final double width;
  final double bloom;
  final double legGap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FaBlock(
          color: bodyColor,
          radius: 30,
          borderWidth: 3.5,
          shadowOffset: const Offset(0, 7),
          padding: const EdgeInsets.all(16),
          width: width,
          child: FaBlock(
            color: FlatArt.screen,
            radius: 20,
            borderWidth: 2.5,
            shadow: false,
            padding: const EdgeInsets.all(14),
            child: RobotFace(
              expression: expression,
              variant: variant,
              litColor: Colors.white,
              screenColor: FlatArt.screen,
              bloom: bloom,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _leg(),
          SizedBox(width: legGap),
          _leg(),
        ]),
      ],
    );
  }

  Widget _leg() => Container(
        width: 14,
        height: 22,
        decoration: const BoxDecoration(
          color: FlatArt.ink,
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(6)),
        ),
      );
}
