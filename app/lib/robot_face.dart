// Cute pixel-art LED robot face. Pure Flutter CustomPainter — no Rive, no
// assets, no audio lip-sync. The face is a 32x20 LED dot-matrix "screen": every
// cell is a dim dot, lit cells (eyes + mouth) form an expression.
//
// Shapes are computed procedurally in grid space (eye = rounded block or arc,
// mouth = arc/line) so they stay smooth at this resolution and are easy to
// animate. Animations (all derived from one controller):
//   - blink: eyes briefly squash to a line — every expression, on its own rhythm
//   - eye darting: eyes glance left/right slightly when idle/attentive
//   - idle breathing: overall LED brightness gently pulses so it's never dead
//   - happy bounce + sparkle: the whole face hops and eyes twinkle when happy
//
// Phase 1 is visual only; Phase 2 maps the live VoiceState to these expressions.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'child_model.dart';

/// The robot's expressions. Mapped from the voice state in Phase 2.
enum RobotExpression { calm, attentive, talking, sleepy, happy }

/// Visual variant of the face, chosen from the child's gender. The animation +
/// expressions are identical across variants; only the static shape decoration
/// differs (eye style + brow/lash + antenna), so boys and girls read as clearly
/// distinct characters without forking the animation logic.
///   - girl   : softer, rounded eyes with a little lash accent; a small "bow".
///   - boy    : squarer, stronger eyes with a flat brow; a single antenna stalk.
///   - neutral: the original gender-agnostic face (guest / unspecified).
enum FaceVariant { girl, boy, neutral }

/// Map a child's gender to a face variant (unspecified → neutral).
FaceVariant faceVariantFor(ChildGender g) => switch (g) {
      ChildGender.girl => FaceVariant.girl,
      ChildGender.boy => FaceVariant.boy,
      ChildGender.neutral => FaceVariant.neutral,
    };

/// LED grid size. Fine enough for smooth curves, still clearly "pixels".
const int _cols = 32;
const int _rows = 20;

/// A cute pixel-art LED robot face. Drives its own animation.
class RobotFace extends StatefulWidget {
  const RobotFace({
    super.key,
    required this.expression,
    this.variant = FaceVariant.neutral,
    this.litColor = const Color(0xFF7CF6C8), // friendly mint-green LEDs
    this.screenColor = const Color(0xFF15202B),
    this.bloom = 1.0,
  });

  final RobotExpression expression;
  final FaceVariant variant;
  final Color litColor;
  final Color screenColor;

  /// Bloom multiplier — how much the LEDs glow. 1.0 = the original baseline; the
  /// flat-art scenes push this higher (e.g. 1.4–1.8) for a richer, dimensional
  /// look on the dark screen. Default keeps existing callers unchanged.
  final double bloom;

  @override
  State<RobotFace> createState() => _RobotFaceState();
}

class _RobotFaceState extends State<RobotFace>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    // One long-running clock; the painter derives every sub-animation from it.
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AspectRatio(
        aspectRatio: _cols / _rows,
        child: AnimatedBuilder(
          animation: _anim,
          builder: (context, _) {
            return CustomPaint(
              painter: _RobotFacePainter(
                expression: widget.expression,
                variant: widget.variant,
                t: _anim.value, // 0..1 over 6s
                litColor: widget.litColor,
                screenColor: widget.screenColor,
                bloom: widget.bloom,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RobotFacePainter extends CustomPainter {
  _RobotFacePainter({
    required this.expression,
    required this.variant,
    required this.t,
    required this.litColor,
    required this.screenColor,
    required this.bloom,
  });

  final RobotExpression expression;
  final FaceVariant variant;
  final double t; // 0..1 animation clock
  final Color litColor;
  final Color screenColor;
  final double bloom;

  @override
  void paint(Canvas canvas, Size size) {
    // Dark rounded "screen" with a subtle top-down sheen so it reads as glass.
    final screenRect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.shortestSide * 0.1),
    );
    canvas.drawRRect(screenRect, Paint()..color = screenColor);
    // Glass sheen: a faint lighter wash at the top fading to nothing.
    final sheen = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.center,
        colors: [Colors.white.withValues(alpha: 0.06), Colors.transparent],
      ).createShader(Offset.zero & size);
    canvas.drawRRect(screenRect, sheen);

    final f = _faceFor(expression, variant, t);

    // Cell geometry.
    final margin = size.width * 0.035;
    final gridW = size.width - margin * 2;
    final gridH = size.height - margin * 2;
    final cellW = gridW / _cols;
    final cellH = gridH / _rows;
    final dotR = math.min(cellW, cellH) * 0.4;

    // Idle "breathing": gently pulse lit brightness so the panel feels alive.
    final breath = 0.85 + 0.15 * math.sin(t * 2 * math.pi); // 0.7..1.0
    final litBright = (expression == RobotExpression.sleepy) ? 0.6 : breath;

    final dimPaint = Paint()..color = litColor.withValues(alpha: 0.05);
    final litPaint = Paint()..color = litColor.withValues(alpha: litBright);
    // Core highlight — a near-white hot center on each LED for a 3D bead look.
    final corePaint = Paint()
      ..color = Color.lerp(litColor, Colors.white, 0.5)!
          .withValues(alpha: 0.9 * litBright);
    // Two-pass bloom: a tight inner glow + a wide soft halo, scaled by `bloom`.
    final innerGlow = Paint()
      ..color = litColor.withValues(alpha: 0.30 * litBright * bloom)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    final outerGlow = Paint()
      ..color = litColor.withValues(alpha: 0.16 * litBright * bloom)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);

    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        final center = Offset(
          margin + cellW * (c + 0.5),
          margin + cellH * (r + 0.5) + f.faceDy * cellH, // happy bounce offset
        );
        if (f.isLit(c, r)) {
          canvas.drawCircle(center, dotR * 2.4, outerGlow);
          canvas.drawCircle(center, dotR * 1.5, innerGlow);
          canvas.drawCircle(center, dotR, litPaint);
          canvas.drawCircle(center, dotR * 0.42, corePaint);
        } else {
          canvas.drawCircle(center, dotR * 0.65, dimPaint);
        }
      }
    }
  }

  // --- Build the lit-cell test for the current expression + animation phase. --

  _Face _faceFor(RobotExpression e, FaceVariant v, double t) {
    // Sub-phases off the 6s clock.
    final blinkPhase = (t * 3) % 1.0; // blink ~ every 2s
    final blinking = blinkPhase > 0.94; // short closed window
    // Eyes glance left/right slowly (idle/attentive curiosity).
    final dart = (math.sin(t * 2 * math.pi * 0.5) * 2).round(); // -2..2 cols
    // Happy hop: quick little bounces.
    final hop = (expression == RobotExpression.happy)
        ? -(math.sin(t * 2 * math.pi * 4).abs() * 1.4) // up to ~1.4 cells up
        : 0.0;
    // Sparkle phase for happy eyes.
    final sparkle = (t * 8) % 1.0 < 0.5;

    // Per-variant static geometry. The SAME animation drives all variants; only
    // the eye style + accents (brow / lash) differ. `boy` = squarer eyes + a
    // flat brow; `girl` = the rounded base eyes + an outer lash; `neutral` =
    // exactly the original face.
    // Boy reads "stronger" via square (untrimmed) eyes + the antenna stalk; a
    // separate eyebrow fought the eyes at this LED density, so it's omitted.
    // Girl reads "softer" via the rounded base eyes + an outer lash flick + bow.
    final square = v == FaceVariant.boy;
    final lash = v == FaceVariant.girl;

    _Eye eye(int cx, int cy, int w, int h,
            {bool arc = false, bool sparkle = false, int side = 0}) =>
        _Eye(
          cx: cx,
          cy: cy,
          w: w,
          h: h,
          arc: arc,
          sparkle: sparkle,
          square: square && !arc,
          lash: lash && !arc && h > 0,
          side: side, // -1 = left eye, +1 = right eye (for outer accents)
        );

    final eyes = <_Eye>[];
    _MouthSpec mouth;

    switch (e) {
      case RobotExpression.calm:
        eyes
          ..add(eye(10 + dart ~/ 2, 7, 3, blinking ? 0 : 4, side: -1))
          ..add(eye(21 + dart ~/ 2, 7, 3, blinking ? 0 : 4, side: 1));
        mouth = _MouthSpec.smile;
      case RobotExpression.attentive:
        // Wide, alert eyes; still blink + dart.
        eyes
          ..add(eye(10 + dart, 7, 4, blinking ? 0 : 6, side: -1))
          ..add(eye(21 + dart, 7, 4, blinking ? 0 : 6, side: 1));
        mouth = _MouthSpec.smallO;
      case RobotExpression.talking:
        eyes
          ..add(eye(10, 7, 3, blinking ? 0 : 4, side: -1))
          ..add(eye(21, 7, 3, blinking ? 0 : 4, side: 1));
        // Mouth opens/closes a few times per second.
        mouth = (math.sin(t * 2 * math.pi * 9) > 0)
            ? _MouthSpec.openO
            : _MouthSpec.line;
      case RobotExpression.sleepy:
        // Half-closed eyes (a thin line), looking down; no dart, no accents.
        eyes
          ..add(eye(10, 9, 3, 1, side: -1))
          ..add(eye(21, 9, 3, 1, side: 1));
        mouth = _MouthSpec.line;
      case RobotExpression.happy:
        // Curved ^^ eyes (arc), sparkle, bouncing face — same for all variants.
        eyes
          ..add(eye(10, 6, 4, 3, arc: true, sparkle: sparkle, side: -1))
          ..add(eye(21, 6, 4, 3, arc: true, sparkle: sparkle, side: 1));
        mouth = _MouthSpec.grin;
    }

    return _Face(
      eyes: eyes,
      mouth: mouth,
      faceDy: hop,
      zzz: e == RobotExpression.sleepy,
      zzzPhase: (t * 2) % 1.0,
      antenna: e == RobotExpression.sleepy ? _Antenna.none : _antennaFor(v),
    );
  }

  _Antenna _antennaFor(FaceVariant v) => switch (v) {
        FaceVariant.boy => _Antenna.stalk, // a single antenna stalk + tip
        FaceVariant.girl => _Antenna.bow, // a little bow on top
        FaceVariant.neutral => _Antenna.none,
      };

  @override
  bool shouldRepaint(_RobotFacePainter old) =>
      old.expression != expression ||
      old.variant != variant ||
      old.t != t ||
      old.litColor != litColor ||
      old.screenColor != screenColor ||
      old.bloom != bloom;
}

/// One eye: a block centered at (cx,cy) spanning w x h cells. h==0 means blinking
/// (a flat line). `arc` draws a happy upward curve; `sparkle` adds a twinkle dot.
/// Variant decoration: `square` keeps the corners (boy, stronger); otherwise the
/// corners are trimmed (rounded). `lash` lights a short lash flick at the
/// outer-top (girl). `side` is -1 for the left eye, +1 for the right, so accents
/// flick outward.
class _Eye {
  _Eye({
    required this.cx,
    required this.cy,
    required this.w,
    required this.h,
    this.arc = false,
    this.sparkle = false,
    this.square = false,
    this.lash = false,
    this.side = 0,
  });
  final int cx, cy, w, h;
  final bool arc;
  final bool sparkle;
  final bool square;
  final bool lash;
  final int side;

  bool covers(int c, int r) {
    final dx = c - cx;
    final dy = r - cy;
    if (arc) {
      // Upward arc "^": lit where r ≈ a parabola of c across the eye width.
      if (dx.abs() > w) return false;
      final curve = cy - ((w - dx.abs()) ~/ 2); // higher toward the center
      if (r == curve || r == curve + 1) return true;
      return false;
    }
    if (h == 0) {
      // Blink: a single flat row.
      return dy == 0 && dx.abs() <= w;
    }
    final halfW = w;
    final halfH = h ~/ 2;
    // The lash accent sits OUTSIDE the eye box (with a clear gap) — test first.
    if (lash) {
      // A short outward lash flick at the outer-top corner of the eye, clearly
      // separated from the eye box.
      final outerC = cx + side * (halfW + 1);
      if ((c == outerC && r == cy - halfH - 1) ||
          (c == outerC + side && r == cy - halfH - 1) ||
          (c == outerC + side && r == cy - halfH)) {
        return true;
      }
    }
    if (dx.abs() > halfW || dy.abs() > halfH) {
      // sparkle dot sits just above-outer of the eye
      if (sparkle && c == cx + cx.sign.clamp(1, 1) + w && r == cy - h ~/ 2 - 1) {
        return true;
      }
      return false;
    }
    // Trim the four corners for a rounded look — unless `square` (keep them).
    if (!square && dx.abs() == halfW && dy.abs() == halfH) return false;
    return true;
  }
}

/// A small accent on top of the head: a boy's antenna stalk, a girl's bow, or
/// nothing (neutral / sleepy).
enum _Antenna { none, stalk, bow }

enum _MouthSpec { smile, grin, line, smallO, openO }

class _Face {
  _Face({
    required this.eyes,
    required this.mouth,
    required this.faceDy,
    required this.zzz,
    required this.zzzPhase,
    this.antenna = _Antenna.none,
  });
  final List<_Eye> eyes;
  final _MouthSpec mouth;
  final double faceDy; // vertical cell offset (happy bounce)
  final bool zzz;
  final double zzzPhase;
  final _Antenna antenna;

  bool isLit(int c, int r) {
    for (final e in eyes) {
      if (e.covers(c, r)) return true;
    }
    if (_mouthCovers(c, r)) return true;
    if (zzz && _zzzCovers(c, r)) return true;
    if (antenna != _Antenna.none && _antennaCovers(c, r)) return true;
    return false;
  }

  // Top-of-head accent, centered between the eyes (face center ≈ col 15-16).
  bool _antennaCovers(int c, int r) {
    switch (antenna) {
      case _Antenna.none:
        return false;
      case _Antenna.stalk:
        // A short vertical stalk rising from row 2 with a tip dot at the top.
        if (c == 15 && r >= 1 && r <= 2) return true; // stalk
        if (r == 0 && (c == 15 || c == 16)) return true; // tip
        return false;
      case _Antenna.bow:
        // A little bow: two small lobes either side of a center knot at row 1-2.
        if (r == 1 && (c == 14 || c == 17)) return true; // outer lobe tops
        if (r == 2 && (c == 13 || c == 14 || c == 17 || c == 18)) return true;
        if ((r == 1 || r == 2) && (c == 15 || c == 16)) return true; // knot
        return false;
    }
  }

  // Mouth is centered on the face (eyes are at cx 10 & 21 → face center ≈ 15.5).
  // Span columns 11..20 (10 wide), rows ~13..16.
  static const int _mouthL = 11;
  static const int _mouthR = 20;
  static const double _mouthMid = (_mouthL + _mouthR) / 2; // 15.5

  bool _mouthCovers(int c, int r) {
    if (c < _mouthL || c > _mouthR) return false;
    // Normalized distance from center, 0 at the middle, 1 at the ends.
    final span = (_mouthR - _mouthL) / 2;
    final norm = (c - _mouthMid).abs() / span; // 0..1

    switch (mouth) {
      case _MouthSpec.smile:
        // Upward smile: a continuous curve that lifts toward the ends.
        // baseline row 15 in the middle, rising up to row 13 at the corners.
        final row = 15 - (norm * norm * 2).round(); // 15 → 13
        return r == row;
      case _MouthSpec.grin:
        // Wide happy grin: a filled two-row curve (open mouth showing a smile).
        final topRow = 14 - (norm * norm * 2).round(); // upper edge curves up
        return r >= topRow && r <= 15 && r >= 14 - 2;
      case _MouthSpec.line:
        // Neutral straight line (slightly inset).
        return r == 14 && c >= _mouthL + 1 && c <= _mouthR - 1;
      case _MouthSpec.smallO:
        // Small round mouth in the very center.
        return c >= 15 && c <= 16 && r >= 13 && r <= 15;
      case _MouthSpec.openO:
        // Hollow open mouth (a ring) for "talking".
        if (r < 12 || r > 16) return false;
        final edge = (c == _mouthL + 2 || c == _mouthR - 2 || r == 12 || r == 16);
        // constrain the ring horizontally to cols 13..18
        if (c < _mouthL + 2 || c > _mouthR - 2) return false;
        return edge;
    }
  }

  // "z z z" rising near the top-right when sleepy; appears in phase to "drift up".
  bool _zzzCovers(int c, int r) {
    // Three little z marks at increasing height; show by phase so they rise.
    if (zzzPhase < 0.33) {
      return c == 26 && r == 6;
    } else if (zzzPhase < 0.66) {
      return (c == 26 && r == 6) || (c == 28 && r == 4);
    } else {
      return (c == 26 && r == 6) || (c == 28 && r == 4) || (c == 30 && r == 2);
    }
  }
}
