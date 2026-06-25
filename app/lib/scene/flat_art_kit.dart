// Shared flat-art style kit for the Sticker-Scene UI: thick navy ink borders,
// hard *offset* shadows (no blur — reads like a sticker), confident color blocks,
// Baloo 2 type, and the LED robot face in a dark "screen".
//
// Ported from the approved UI preview (preview/lib/shared/flat_art_kit.dart). The
// palette + FaBlock/FaPressable are the building blocks every flat-art surface
// (picker / voice / form) is composed from.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The shared flat-art palette (navy ink + magenta/cyan + pop yellow on cream).
class FlatArt {
  static const ink = Color(0xFF22324A); // deep navy — borders + text
  static const inkSoft = Color(0xFF6E7E96);
  static const cream = Color(0xFFFDF7EE); // bg top
  static const creamDeep = Color(0xFFFCEFE0); // bg bottom
  static const surface = Color(0xFFFFFFFF);
  static const magenta = Color(0xFFF15BB5);
  static const cyan = Color(0xFF00BBF9);
  static const yellow = Color(0xFFFEE440);
  static const mint = Color(0xFF00F5D4);
  static const screen = Color(0xFF14213D); // dark robot screen

  /// Per-gender tint.
  static Color tintFor(bool isGirl) => isGirl ? magenta : cyan;
}

/// The warm cream background gradient (used by Material parent screens).
const flatArtBg = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [FlatArt.cream, FlatArt.creamDeep],
  ),
);

/// The signature hard offset shadow — no blur, like a paper sticker.
List<BoxShadow> hardShadow({Offset offset = const Offset(0, 5), Color? color}) =>
    [BoxShadow(color: color ?? FlatArt.ink, offset: offset, blurRadius: 0)];

/// A thick ink border at a given width.
Border inkBorder([double width = 2.5]) =>
    Border.all(color: FlatArt.ink, width: width);

/// Baloo-2 text in the flat-art weight scale.
///
/// Wrapped so a font-load failure (no network + font not bundled, e.g. in the
/// test sandbox or an offline first launch) degrades gracefully to a plain
/// system-font TextStyle instead of throwing — the UI stays legible, just not in
/// Baloo 2.
TextStyle faFont(double size,
    {FontWeight w = FontWeight.w700, Color? c, double? spacing}) {
  final color = c ?? FlatArt.ink;
  try {
    return GoogleFonts.baloo2(
        fontSize: size, fontWeight: w, color: color, letterSpacing: spacing);
  } catch (_) {
    return TextStyle(
        fontSize: size, fontWeight: w, color: color, letterSpacing: spacing);
  }
}

/// A reusable flat "block" container: color fill, thick ink border, hard shadow.
/// The building block of every flat-art surface.
class FaBlock extends StatelessWidget {
  const FaBlock({
    super.key,
    required this.child,
    this.color = FlatArt.surface,
    this.radius = 22,
    this.borderWidth = 2.5,
    this.padding,
    this.shadow = true,
    this.shadowOffset = const Offset(0, 5),
    this.width,
    this.height,
  });
  final Widget child;
  final Color color;
  final double radius;
  final double borderWidth;
  final EdgeInsets? padding;
  final bool shadow;
  final Offset shadowOffset;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: inkBorder(borderWidth),
        boxShadow: shadow ? hardShadow(offset: shadowOffset) : null,
      ),
      child: child,
    );
  }
}

/// A press-animated flat block button: drops down onto its shadow on tap-down
/// (the shadow vanishes), giving the satisfying "press a sticker" feel shared by
/// every flat-art button + card.
class FaPressable extends StatefulWidget {
  const FaPressable({
    super.key,
    required this.child,
    required this.onTap,
    this.color = FlatArt.surface,
    this.radius = 22,
    this.borderWidth = 2.5,
    this.padding,
    this.shadowOffset = const Offset(0, 5),
    this.width,
    this.height,
  });
  final Widget child;
  final VoidCallback? onTap;
  final Color color;
  final double radius;
  final double borderWidth;
  final EdgeInsets? padding;
  final Offset shadowOffset;
  final double? width;
  final double? height;

  @override
  State<FaPressable> createState() => _FaPressableState();
}

class _FaPressableState extends State<FaPressable> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final on = widget.onTap != null;
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: on ? (_) => setState(() => _pressed = true) : null,
      onTapUp: on ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        transform: Matrix4.translationValues(
            0, _pressed ? widget.shadowOffset.dy : 0, 0),
        width: widget.width,
        height: widget.height,
        padding: widget.padding,
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.circular(widget.radius),
          border: inkBorder(widget.borderWidth),
          boxShadow: _pressed ? null : hardShadow(offset: widget.shadowOffset),
        ),
        child: widget.child,
      ),
    );
  }
}
