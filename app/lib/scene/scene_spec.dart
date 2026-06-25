// A SceneSpec describes ONE illustrated world for the Sticker-Scene UI. The
// shared scene widgets (scene_widgets.dart) render every world identically;
// only the SceneSpec changes — its sky gradient, its painted props
// (sun/moon/stars/fish…), the ground/floor color, and accent tints.
//
// Ported from the approved UI preview. Keeps the worlds DRY: each is just a
// gradient + a CustomPainter + a few colors, not a forked screen.

import 'package:flutter/material.dart';

import 'flat_art_kit.dart';

/// Paints the world's background props (behind the character). Given the canvas
/// size + an animation clock `t` (0..1, ~loops slowly) for drifting elements.
typedef ScenePainterFn = void Function(Canvas canvas, Size size, double t);

/// Everything that makes one world distinct.
class SceneSpec {
  const SceneSpec({
    required this.id,
    required this.title,
    required this.tagline,
    required this.skyColors,
    required this.skyStops,
    required this.groundColor,
    required this.paint,
    required this.bubbleColor,
    required this.bubbleInk,
    required this.talkColor,
    required this.ctaColor,
    this.headingOnDark = false,
  });

  /// Stable key (persisted by ThemeRotation; used by specForId).
  final String id;
  final String title;
  final String tagline;

  /// Sky / water gradient (top → bottom) + its stops.
  final List<Color> skyColors;
  final List<double> skyStops;

  /// The hill / sea-floor the character stands on.
  final Color groundColor;

  /// Paints the world's props (sun, stars, fish…). Animated by `t`.
  final ScenePainterFn paint;

  /// Idle speech-bubble color + its text ink (some worlds need light text).
  final Color bubbleColor;
  final Color bubbleInk;

  /// Talk button + form CTA fills.
  final Color talkColor;
  final Color ctaColor;

  /// When the sky is dark, headings/labels flip to light ink.
  final bool headingOnDark;

  Color get headingInk => headingOnDark ? Colors.white : FlatArt.ink;
}
