// Cute pixel-art LED robot face. Pure Flutter CustomPainter — no Rive, no
// assets, no audio lip-sync. The face is an LED dot-matrix "screen": every cell
// is drawn as a dim dot, and lit cells (eyes + mouth) form an expression.
//
// Phase 1 is visual only: RobotFace renders one of five expressions and animates
// blink (calm) + mouth (talking). Phase 2 maps the live VoiceState to these.

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The robot's expressions. Mapped from the voice state in Phase 2.
enum RobotExpression { calm, attentive, talking, sleepy, happy }

/// LED grid size. Small enough to read as "pixels", big enough for expression.
const int _cols = 16;
const int _rows = 10;

/// A cute pixel-art LED robot face. Drives its own blink/mouth animation.
class RobotFace extends StatefulWidget {
  const RobotFace({
    super.key,
    required this.expression,
    this.litColor = const Color(0xFF7CF6C8), // friendly mint-green LEDs
    this.screenColor = const Color(0xFF15202B),
  });

  final RobotExpression expression;
  final Color litColor;
  final Color screenColor;

  @override
  State<RobotFace> createState() => _RobotFaceState();
}

class _RobotFaceState extends State<RobotFace>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    // One always-running clock; the painter derives blink + mouth phases from it.
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
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
                t: _anim.value, // 0..1 over 4s
                litColor: widget.litColor,
                screenColor: widget.screenColor,
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
    required this.t,
    required this.litColor,
    required this.screenColor,
  });

  final RobotExpression expression;
  final double t; // 0..1 animation clock
  final Color litColor;
  final Color screenColor;

  @override
  void paint(Canvas canvas, Size size) {
    // Draw the dark rounded "screen" the LEDs sit on.
    final screenRect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.shortestSide * 0.12),
    );
    canvas.drawRRect(screenRect, Paint()..color = screenColor);

    final lit = _litCells(expression, t);

    // Cell geometry: leave a margin so dots don't touch the screen edge.
    final margin = size.width * 0.04;
    final gridW = size.width - margin * 2;
    final gridH = size.height - margin * 2;
    final cellW = gridW / _cols;
    final cellH = gridH / _rows;
    final dotR = math.min(cellW, cellH) * 0.42;

    final dimPaint = Paint()..color = litColor.withValues(alpha: 0.06);
    final litPaint = Paint()..color = litColor;
    final glowPaint = Paint()
      ..color = litColor.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        final center = Offset(
          margin + cellW * (c + 0.5),
          margin + cellH * (r + 0.5),
        );
        if (lit.contains(_key(c, r))) {
          canvas.drawCircle(center, dotR * 1.5, glowPaint); // soft glow
          canvas.drawCircle(center, dotR, litPaint);
        } else {
          canvas.drawCircle(center, dotR * 0.7, dimPaint); // faint unlit dot
        }
      }
    }
  }

  // --- Expression layout -----------------------------------------------------
  // Each expression returns the set of lit cells (encoded as r*_cols + c).
  // Eyes sit in the upper half; the mouth in the lower half. Helpers keep the
  // "pixel font" readable without a general sprite engine (YAGNI).

  static int _key(int c, int r) => r * _cols + c;

  Set<int> _litCells(RobotExpression e, double t) {
    final cells = <int>{};
    // Blink: eyes briefly close ~once every cycle (short closed window).
    final blink = t > 0.92; // ~0.32s closed out of 4s
    // Mouth phase for talking: open/closed a few times per second.
    final mouthOpen = (math.sin(t * 2 * math.pi * 8) > 0);

    switch (e) {
      case RobotExpression.calm:
        _addEyes(cells, closed: blink);
        _addMouth(cells, _MouthShape.smile);
      case RobotExpression.attentive:
        _addEyes(cells, big: true); // wide-open, paying attention
        _addMouth(cells, _MouthShape.smallO);
      case RobotExpression.talking:
        _addEyes(cells, closed: blink);
        _addMouth(cells, mouthOpen ? _MouthShape.openO : _MouthShape.line);
      case RobotExpression.sleepy:
        _addEyes(cells, sleepy: true); // half-closed, looking down
        _addMouth(cells, _MouthShape.line);
        _addZzz(cells, t);
      case RobotExpression.happy:
        _addEyes(cells, happy: true); // curved ^^ eyes
        _addMouth(cells, _MouthShape.grin);
    }
    return cells;
  }

  // Eyes occupy two clusters around columns 4-5 and 10-11, rows 2-4.
  void _addEyes(
    Set<int> cells, {
    bool closed = false,
    bool big = false,
    bool sleepy = false,
    bool happy = false,
  }) {
    const leftX = 4;
    const rightX = 10;
    void eye(int x) {
      if (closed) {
        // A flat closed lid (one row).
        for (var c = x; c <= x + 1; c++) {
          cells.add(_key(c, 3));
        }
      } else if (happy) {
        // Curved ^^ : two cells up, one down — a little arch.
        cells..add(_key(x, 3))..add(_key(x + 1, 2))..add(_key(x + 2, 3));
      } else if (sleepy) {
        // Half-lidded: a short lower line.
        cells..add(_key(x, 4))..add(_key(x + 1, 4));
      } else {
        // Open eye block; wider AND taller when "attentive" so it reads as
        // wide-eyed/alert vs the calm 2x2 eye.
        final rows = big ? [1, 2, 3, 4] : [2, 3];
        final colsE = big ? [x - 1, x, x + 1, x + 2] : [x, x + 1];
        for (final rr in rows) {
          for (final cc in colsE) {
            cells.add(_key(cc, rr));
          }
        }
      }
    }

    eye(leftX);
    eye(rightX);
  }

  // Mouth occupies rows 6-8, columns ~5-10.
  void _addMouth(Set<int> cells, _MouthShape shape) {
    switch (shape) {
      case _MouthShape.smile:
        // Gentle upward curve.
        cells
          ..add(_key(5, 7))
          ..add(_key(6, 8))
          ..add(_key(7, 8))
          ..add(_key(8, 8))
          ..add(_key(9, 8))
          ..add(_key(10, 7));
      case _MouthShape.grin:
        // Wide happy grin (two rows).
        for (var c = 5; c <= 10; c++) {
          cells.add(_key(c, 7));
        }
        cells..add(_key(5, 8))..add(_key(10, 8))..add(_key(6, 8))..add(_key(9, 8));
      case _MouthShape.line:
        for (var c = 6; c <= 9; c++) {
          cells.add(_key(c, 7));
        }
      case _MouthShape.smallO:
        cells
          ..add(_key(7, 7))
          ..add(_key(8, 7))
          ..add(_key(7, 8))
          ..add(_key(8, 8));
      case _MouthShape.openO:
        cells
          ..add(_key(6, 6))
          ..add(_key(7, 6))
          ..add(_key(8, 6))
          ..add(_key(9, 6))
          ..add(_key(6, 7))
          ..add(_key(9, 7))
          ..add(_key(6, 8))
          ..add(_key(7, 8))
          ..add(_key(8, 8))
          ..add(_key(9, 8));
    }
  }

  // A little "z z z" rising for the sleepy state, top-right corner.
  void _addZzz(Set<int> cells, double t) {
    // Twinkle: show the z-dots only part of the cycle so they "rise".
    if (t % 0.5 > 0.25) {
      cells..add(_key(13, 1))..add(_key(14, 0))..add(_key(14, 2));
    }
  }

  @override
  bool shouldRepaint(_RobotFacePainter old) =>
      old.expression != expression ||
      old.t != t ||
      old.litColor != litColor ||
      old.screenColor != screenColor;
}

enum _MouthShape { smile, grin, line, smallO, openO }
