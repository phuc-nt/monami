// The six Sticker-Scene worlds: Night, Space, Underwater, Forest, Rainbow, Snow.
// Each is a SceneSpec — a gradient + a painter that draws that world's props + a
// few accent tokens. The shared scene widgets (scene_widgets.dart) do everything
// else. Ported verbatim from the approved UI preview.
//
// Painters use only `t` (0..1 loop) for motion and deterministic pseudo-random
// placement (no Random / DateTime — keeps frames stable across resume).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'flat_art_kit.dart';
import 'scene_spec.dart';

// Helpers shared by the painters ──────────────────────────────────────────────

void _strokePath(Canvas c, Path p, {double w = 2.5, Color? color}) {
  c.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..color = color ?? FlatArt.ink);
}

void _outlinedCircle(Canvas c, Offset o, double r, Color fill,
    {double stroke = 2.5}) {
  c.drawCircle(o, r, Paint()..color = fill);
  c.drawCircle(
      o,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = FlatArt.ink);
}

/// A 4-point twinkle star (a plus with a slight diamond), used by night/space.
void _twinkle(Canvas c, Offset o, double r, Color color) {
  final p = Path();
  for (var i = 0; i < 8; i++) {
    final rad = i.isEven ? r : r * 0.34;
    final a = -math.pi / 2 + i * math.pi / 4;
    final pt = Offset(o.dx + rad * math.cos(a), o.dy + rad * math.sin(a));
    i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
  }
  p.close();
  c.drawPath(p, Paint()..color = color);
}

/// A rolling ground/hill across the bottom.
Path _ground(Size size, double topFrac) {
  final w = size.width, h = size.height;
  return Path()
    ..moveTo(0, h)
    ..lineTo(0, h * topFrac)
    ..quadraticBezierTo(w * 0.30, h * (topFrac - 0.06), w * 0.55, h * topFrac)
    ..quadraticBezierTo(w * 0.80, h * (topFrac + 0.05), w, h * (topFrac - 0.02))
    ..lineTo(w, h)
    ..close();
}

// ── NIGHT SKY ─────────────────────────────────────────────────────────────────

void _paintNight(Canvas canvas, Size size, double t) {
  final w = size.width, h = size.height;
  // Stars (twinkle: size pulses by phase).
  for (var i = 0; i < 22; i++) {
    final fx = ((i * 71) % 100) / 100;
    final fy = ((i * 137) % 100) / 100 * 0.62;
    final phase = (t + i / 22) % 1.0;
    final tw = 0.6 + 0.4 * math.sin(phase * 2 * math.pi).abs();
    _twinkle(canvas, Offset(fx * w, fy * h), (3.0 + (i % 3)) * tw,
        Colors.white.withValues(alpha: 0.9));
  }
  // Crescent moon, top-right (a yellow disc with a sky-colored bite).
  final moonC = Offset(w * 0.78, h * 0.16);
  _outlinedCircle(canvas, moonC, 36, const Color(0xFFFFF1A8));
  canvas.drawCircle(moonC + const Offset(14, -6), 32,
      Paint()..color = const Color(0xFF1B2A4A));
  // A couple drifting fireflies near the hill.
  for (var i = 0; i < 4; i++) {
    final drift = math.sin((t + i / 4) * 2 * math.pi) * 14;
    final fc = Offset(w * (0.2 + i * 0.18) + drift, h * (0.6 + (i % 2) * 0.05));
    canvas.drawCircle(
        fc, 5, Paint()..color = FlatArt.yellow.withValues(alpha: 0.95));
    canvas.drawCircle(
        fc,
        9,
        Paint()
          ..color = FlatArt.yellow.withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
  }
  // Night hill.
  final hill = _ground(size, 0.72);
  canvas.drawPath(hill, Paint()..color = const Color(0xFF2E7D5B));
  _strokePath(canvas, hill, w: 3);
}

const sceneNight = SceneSpec(
  id: 'night',
  title: 'Trời đêm',
  tagline: 'Trăng sao, đom đóm — kể chuyện ngủ',
  skyColors: [Color(0xFF14213D), Color(0xFF26365E), Color(0xFF3C4E78)],
  skyStops: [0.0, 0.55, 1.0],
  groundColor: Color(0xFF2E7D5B),
  paint: _paintNight,
  bubbleColor: Colors.white,
  bubbleInk: FlatArt.ink,
  talkColor: FlatArt.yellow,
  ctaColor: FlatArt.yellow,
  headingOnDark: true,
);

// ── OUTER SPACE ───────────────────────────────────────────────────────────────

void _paintSpace(Canvas canvas, Size size, double t) {
  final w = size.width, h = size.height;
  // Starfield.
  for (var i = 0; i < 26; i++) {
    final fx = ((i * 67) % 100) / 100;
    final fy = ((i * 151) % 100) / 100 * 0.66;
    final phase = (t + i / 26) % 1.0;
    final tw = 0.5 + 0.5 * math.sin(phase * 2 * math.pi).abs();
    canvas.drawCircle(Offset(fx * w, fy * h), (1.6 + (i % 3)) * tw,
        Paint()..color = Colors.white.withValues(alpha: 0.85));
  }
  // Floating planets (one ringed), slow vertical bob.
  final bob = math.sin(t * 2 * math.pi) * 8;
  _outlinedCircle(
      canvas, Offset(w * 0.2, h * 0.18 + bob), 26, const Color(0xFFFF8FB1));
  // Ringed planet, top-right.
  final ringC = Offset(w * 0.8, h * 0.2 - bob);
  canvas.save();
  canvas.translate(ringC.dx, ringC.dy);
  canvas.rotate(-0.4);
  final ringRect = Rect.fromCenter(center: Offset.zero, width: 88, height: 30);
  canvas.drawOval(
      ringRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = FlatArt.yellow);
  canvas.drawOval(
      ringRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..color = FlatArt.ink
        ..strokeCap = StrokeCap.round
        ..blendMode = BlendMode.dstOver);
  canvas.restore();
  _outlinedCircle(canvas, ringC, 22, const Color(0xFF8FE3C4));
  // A little rocket zipping across, looping by t.
  final rx = (t * 1.2 % 1.2 - 0.1) * w;
  final ry = h * 0.34;
  _rocket(canvas, Offset(rx, ry));
  // Cratered planet surface across the bottom.
  final ground = _ground(size, 0.74);
  canvas.drawPath(ground, Paint()..color = const Color(0xFF6C5CE7));
  _strokePath(canvas, ground, w: 3);
  // Craters.
  for (var i = 0; i < 4; i++) {
    final cx = w * (0.15 + i * 0.22);
    _outlinedCircle(canvas, Offset(cx, h * (0.85 + (i % 2) * 0.04)), 10,
        const Color(0xFF5A4BD1),
        stroke: 2);
  }
}

void _rocket(Canvas canvas, Offset o) {
  canvas.save();
  canvas.translate(o.dx, o.dy);
  canvas.rotate(0.5);
  // Body.
  final body = Path()
    ..moveTo(0, -16)
    ..quadraticBezierTo(10, -6, 8, 10)
    ..lineTo(-8, 10)
    ..quadraticBezierTo(-10, -6, 0, -16)
    ..close();
  canvas.drawPath(body, Paint()..color = Colors.white);
  _strokePath(canvas, body, w: 2.5);
  // Window.
  _outlinedCircle(canvas, const Offset(0, -2), 4, FlatArt.cyan, stroke: 2);
  // Flame.
  final flame = Path()
    ..moveTo(-5, 10)
    ..lineTo(0, 22)
    ..lineTo(5, 10)
    ..close();
  canvas.drawPath(flame, Paint()..color = FlatArt.yellow);
  _strokePath(canvas, flame, w: 2);
  canvas.restore();
}

const sceneSpace = SceneSpec(
  id: 'space',
  title: 'Vũ trụ',
  tagline: 'Hành tinh, tên lửa — phiêu lưu',
  skyColors: [Color(0xFF0B1026), Color(0xFF1A1147), Color(0xFF2A1A5E)],
  skyStops: [0.0, 0.5, 1.0],
  groundColor: Color(0xFF6C5CE7),
  paint: _paintSpace,
  bubbleColor: Colors.white,
  bubbleInk: FlatArt.ink,
  talkColor: FlatArt.cyan,
  ctaColor: FlatArt.yellow,
  headingOnDark: true,
);

// ── UNDERWATER ────────────────────────────────────────────────────────────────

void _paintUnderwater(Canvas canvas, Size size, double t) {
  final w = size.width, h = size.height;
  // Sun rays from the surface (soft light shafts).
  final ray = Paint()..color = Colors.white.withValues(alpha: 0.06);
  for (var i = 0; i < 3; i++) {
    final x = w * (0.25 + i * 0.28);
    final path = Path()
      ..moveTo(x, 0)
      ..lineTo(x + 30, 0)
      ..lineTo(x - 30, h * 0.7)
      ..lineTo(x - 90, h * 0.7)
      ..close();
    canvas.drawPath(path, ray);
  }
  // Rising bubbles.
  for (var i = 0; i < 14; i++) {
    final fx = ((i * 83) % 100) / 100;
    final rise = ((t * 1.3 + i / 14) % 1.0);
    final by = h * (1.0 - rise) * 0.8 + h * 0.12;
    final r = 3.0 + (i % 4);
    canvas.drawCircle(Offset(fx * w, by), r,
        Paint()..color = Colors.white.withValues(alpha: 0.5));
    canvas.drawCircle(
        Offset(fx * w, by),
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white.withValues(alpha: 0.7));
  }
  // A couple fish swimming across (loop by t).
  _fish(canvas, Offset(((t + 0.0) % 1.0) * w, h * 0.24), FlatArt.yellow, 1.0);
  _fish(canvas, Offset(((t * 0.8 + 0.5) % 1.0) * w, h * 0.40),
      const Color(0xFFFF8FB1), -1.0);
  // Sea floor (sand) with seaweed + coral.
  final floor = _ground(size, 0.78);
  canvas.drawPath(floor, Paint()..color = const Color(0xFFF2C879));
  _strokePath(canvas, floor, w: 3);
  // Seaweed sways.
  for (var i = 0; i < 3; i++) {
    final x = w * (0.12 + i * 0.3);
    final sway = math.sin((t + i / 3) * 2 * math.pi) * 6;
    final weed = Path()
      ..moveTo(x, h * 0.82)
      ..quadraticBezierTo(x + sway, h * 0.74, x - sway, h * 0.66)
      ..quadraticBezierTo(x + sway, h * 0.6, x, h * 0.55);
    _strokePath(canvas, weed, w: 6, color: const Color(0xFF2E9E6B));
  }
  // Coral clump, bottom-right.
  _outlinedCircle(canvas, Offset(w * 0.82, h * 0.82), 14, FlatArt.magenta,
      stroke: 2.5);
  _outlinedCircle(canvas, Offset(w * 0.9, h * 0.85), 10, const Color(0xFFFF8FB1),
      stroke: 2.5);
}

void _fish(Canvas canvas, Offset o, Color color, double dir) {
  canvas.save();
  canvas.translate(o.dx, o.dy);
  canvas.scale(dir, 1); // flip to face swim direction
  // Body.
  final body = Path()
    ..addOval(Rect.fromCenter(center: Offset.zero, width: 30, height: 18));
  canvas.drawPath(body, Paint()..color = color);
  _strokePath(canvas, body, w: 2.5);
  // Tail.
  final tail = Path()
    ..moveTo(-14, 0)
    ..lineTo(-24, -8)
    ..lineTo(-24, 8)
    ..close();
  canvas.drawPath(tail, Paint()..color = color);
  _strokePath(canvas, tail, w: 2.5);
  // Eye.
  canvas.drawCircle(const Offset(8, -3), 2.4, Paint()..color = FlatArt.ink);
  canvas.restore();
}

const sceneUnderwater = SceneSpec(
  id: 'underwater',
  title: 'Dưới biển',
  tagline: 'Cá, bọt nước, san hô — mơ màng',
  skyColors: [Color(0xFF1E88C7), Color(0xFF2BA8D9), Color(0xFF7FD6E8)],
  skyStops: [0.0, 0.5, 1.0],
  groundColor: Color(0xFFF2C879),
  paint: _paintUnderwater,
  bubbleColor: Colors.white,
  bubbleInk: FlatArt.ink,
  talkColor: FlatArt.yellow,
  ctaColor: FlatArt.yellow,
  headingOnDark: true,
);

// ── FOREST ────────────────────────────────────────────────────────────────────

/// A flat round-canopy tree at x with its trunk meeting the ground at `baseY`.
void _tree(Canvas canvas, double x, double baseY, double scale, Color canopy) {
  // Trunk.
  final trunkW = 12.0 * scale;
  final trunk =
      Rect.fromLTWH(x - trunkW / 2, baseY - 46 * scale, trunkW, 50 * scale);
  final trunkR = RRect.fromRectAndRadius(trunk, Radius.circular(4 * scale));
  canvas.drawRRect(trunkR, Paint()..color = const Color(0xFF8D5A2B));
  canvas.drawRRect(
      trunkR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = FlatArt.ink);
  // Canopy: three overlapping circles.
  final cy = baseY - 56 * scale;
  final r = 26.0 * scale;
  final path = Path()
    ..addOval(Rect.fromCircle(center: Offset(x, cy), radius: r))
    ..addOval(Rect.fromCircle(
        center: Offset(x - r * 0.8, cy + r * 0.4), radius: r * 0.8))
    ..addOval(Rect.fromCircle(
        center: Offset(x + r * 0.8, cy + r * 0.4), radius: r * 0.8));
  canvas.drawPath(path, Paint()..color = canopy);
  _strokePath(canvas, path, w: 2.5);
}

void _paintForest(Canvas canvas, Size size, double t) {
  final w = size.width, h = size.height;
  // Soft sun-rays from top-left.
  final ray = Paint()..color = Colors.white.withValues(alpha: 0.10);
  for (var i = 0; i < 3; i++) {
    final x = w * (0.1 + i * 0.2);
    final path = Path()
      ..moveTo(x, 0)
      ..lineTo(x + 24, 0)
      ..lineTo(x + 90, h * 0.6)
      ..lineTo(x + 50, h * 0.6)
      ..close();
    canvas.drawPath(path, ray);
  }
  // Sun, top-right.
  _outlinedCircle(canvas, Offset(w * 0.85, h * 0.12), 28, const Color(0xFFFFE066));
  // Grass floor.
  final floor = _ground(size, 0.74);
  canvas.drawPath(floor, Paint()..color = const Color(0xFF4CAF50));
  _strokePath(canvas, floor, w: 3);
  // A back row of darker trees, then a front row.
  _tree(canvas, w * 0.18, h * 0.76, 0.85, const Color(0xFF2E7D5B));
  _tree(canvas, w * 0.84, h * 0.77, 0.95, const Color(0xFF2E7D5B));
  _tree(canvas, w * 0.5, h * 0.74, 0.7, const Color(0xFF3E9D6B));
  // Flowers on the grass (gentle bob).
  for (var i = 0; i < 4; i++) {
    final x = w * (0.12 + i * 0.24);
    final bob = math.sin((t + i / 4) * 2 * math.pi) * 2;
    final fc = Offset(x, h * 0.86 + bob);
    final color = i.isEven ? FlatArt.magenta : FlatArt.yellow;
    for (var p = 0; p < 5; p++) {
      final a = p * 2 * math.pi / 5;
      canvas.drawCircle(fc + Offset(math.cos(a) * 5, math.sin(a) * 5), 3.2,
          Paint()..color = color);
    }
    canvas.drawCircle(fc, 3, Paint()..color = Colors.white);
  }
}

const sceneForest = SceneSpec(
  id: 'forest',
  title: 'Khu rừng',
  tagline: 'Cây xanh, hoa, nắng xuyên lá — vui tươi',
  skyColors: [Color(0xFFBDEBC9), Color(0xFFDCF5E1), Color(0xFFF1FBEE)],
  skyStops: [0.0, 0.5, 1.0],
  groundColor: Color(0xFF4CAF50),
  paint: _paintForest,
  bubbleColor: Colors.white,
  bubbleInk: FlatArt.ink,
  talkColor: FlatArt.yellow,
  ctaColor: FlatArt.yellow,
);

// ── RAINBOW ───────────────────────────────────────────────────────────────────

void _paintRainbow(Canvas canvas, Size size, double t) {
  final w = size.width, h = size.height;
  // Rainbow arc: concentric stroked bands centered below the screen.
  final center = Offset(w / 2, h * 0.95);
  const bands = [
    Color(0xFFFF6B6B),
    Color(0xFFFFA94D),
    Color(0xFFFFE066),
    Color(0xFF69DB7C),
    Color(0xFF4DABF7),
    Color(0xFFB197FC),
  ];
  const bandW = 16.0;
  for (var i = 0; i < bands.length; i++) {
    final r = w * 0.62 - i * bandW;
    canvas.drawArc(
        Rect.fromCircle(center: center, radius: r),
        math.pi,
        math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = bandW
          ..color = bands[i]);
  }
  // Thin ink outline on the outer edge.
  canvas.drawArc(
      Rect.fromCircle(center: center, radius: w * 0.62 + bandW / 2),
      math.pi,
      math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = FlatArt.ink);
  // Fluffy clouds at the rainbow's feet (drift).
  final drift = math.sin(t * 2 * math.pi) * 8;
  _cloudPuff(canvas, Offset(w * 0.16 + drift, h * 0.5), 1.1);
  _cloudPuff(canvas, Offset(w * 0.85 - drift, h * 0.52), 1.0);
  // Sparkles around the arc.
  for (var i = 0; i < 8; i++) {
    final fx = ((i * 79) % 100) / 100;
    final fy = ((i * 131) % 100) / 100 * 0.45;
    final phase = (t + i / 8) % 1.0;
    final tw = 0.5 + 0.5 * math.sin(phase * 2 * math.pi).abs();
    _twinkle(canvas, Offset(fx * w, h * 0.1 + fy * h), 5 * tw, Colors.white);
  }
  // Green hill.
  final hill = _ground(size, 0.76);
  canvas.drawPath(hill, Paint()..color = const Color(0xFF63D27A));
  _strokePath(canvas, hill, w: 3);
}

void _cloudPuff(Canvas canvas, Offset c, double s) {
  final fill = Paint()..color = Colors.white;
  final path = Path()
    ..addOval(Rect.fromCircle(center: c, radius: 20 * s))
    ..addOval(Rect.fromCircle(center: c + Offset(22 * s, 4 * s), radius: 15 * s))
    ..addOval(Rect.fromCircle(center: c + Offset(-20 * s, 5 * s), radius: 14 * s));
  canvas.drawPath(path, fill);
  _strokePath(canvas, path, w: 2.5);
}

const sceneRainbow = SceneSpec(
  id: 'rainbow',
  title: 'Cầu vồng',
  tagline: 'Cầu vồng, mây bông, lấp lánh — rực rỡ',
  skyColors: [Color(0xFFBFE9FF), Color(0xFFE3F6FF), Color(0xFFFDF7EE)],
  skyStops: [0.0, 0.55, 1.0],
  groundColor: Color(0xFF63D27A),
  paint: _paintRainbow,
  bubbleColor: Colors.white,
  bubbleInk: FlatArt.ink,
  talkColor: FlatArt.magenta,
  ctaColor: FlatArt.yellow,
);

// ── SNOW ──────────────────────────────────────────────────────────────────────

/// A simple flat pine (triangle stack) on the snow.
void _pine(Canvas canvas, double x, double baseY, double scale) {
  const color = Color(0xFF2E7D5B);
  for (var i = 0; i < 3; i++) {
    final top = baseY - (54 - i * 14) * scale;
    final halfW = (16 + i * 9) * scale;
    final bottom = baseY - (30 - i * 14) * scale;
    final tri = Path()
      ..moveTo(x, top)
      ..lineTo(x - halfW, bottom)
      ..lineTo(x + halfW, bottom)
      ..close();
    canvas.drawPath(tri, Paint()..color = color);
    _strokePath(canvas, tri, w: 2.5);
    // Snow caps on the branch edges.
    canvas.drawCircle(
        Offset(x, top + 2 * scale), 3 * scale, Paint()..color = Colors.white);
  }
}

void _paintSnow(Canvas canvas, Size size, double t) {
  final w = size.width, h = size.height;
  // Faint sun behind the haze.
  _outlinedCircle(canvas, Offset(w * 0.8, h * 0.14), 26,
      const Color(0xFFFFF4D6),
      stroke: 2);
  // Snow drifts (rolling white ground).
  final drift = _ground(size, 0.74);
  canvas.drawPath(drift, Paint()..color = Colors.white);
  _strokePath(canvas, drift, w: 3, color: const Color(0xFFB9CBDD));
  // Pines on the snow.
  _pine(canvas, w * 0.16, h * 0.78, 0.9);
  _pine(canvas, w * 0.85, h * 0.79, 1.0);
  _pine(canvas, w * 0.52, h * 0.76, 0.7);
  // Falling snowflakes (drift down + sideways sway, loop by t).
  for (var i = 0; i < 26; i++) {
    final fx = ((i * 73) % 100) / 100;
    final fall = ((t * 0.8 + i / 26) % 1.0);
    final sway = math.sin((t + i) * 2 * math.pi) * 10;
    final sy = fall * h * 0.72;
    final r = 2.5 + (i % 3);
    canvas.drawCircle(Offset(fx * w + sway, sy), r.toDouble(),
        Paint()..color = Colors.white);
    canvas.drawCircle(
        Offset(fx * w + sway, sy),
        r.toDouble(),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = const Color(0xFFB9CBDD));
  }
}

const sceneSnow = SceneSpec(
  id: 'snow',
  title: 'Mùa tuyết',
  tagline: 'Tuyết rơi, thông xanh — dịu êm',
  skyColors: [Color(0xFFAFC6E0), Color(0xFFCFDDEE), Color(0xFFEAF2FA)],
  skyStops: [0.0, 0.5, 1.0],
  groundColor: Colors.white,
  paint: _paintSnow,
  bubbleColor: Colors.white,
  bubbleInk: FlatArt.ink,
  talkColor: FlatArt.cyan,
  ctaColor: FlatArt.yellow,
);

/// All worlds, in display order. The FIRST entry is the first-run default.
const allScenes = <SceneSpec>[
  sceneNight,
  sceneSpace,
  sceneUnderwater,
  sceneForest,
  sceneRainbow,
  sceneSnow,
];

/// Resolve a persisted world id to its SceneSpec; falls back to the first world
/// (night) for an unknown id, so a bad stored value never crashes the app.
SceneSpec specForId(String id) =>
    allScenes.firstWhere((s) => s.id == id, orElse: () => allScenes.first);
