// App theme + per-child visuals. The kid-facing screens (picker / voice / form)
// use the flat-art "Sticker Scene" look (see lib/scene/); this LIGHT Material
// theme (rounded Baloo 2 font, warm cream surfaces, navy ink) governs the
// parent-facing Material screens (child management, dialogs) so they read
// coherently with the new look instead of clashing as a dark sheet.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'child_model.dart';
import 'scene/flat_art_kit.dart';

/// Per-gender palette: the tint that colors a child's character body + the
/// robot-face LEDs. Girl = flat-art magenta; boy = flat-art cyan; neutral
/// (guest / unspecified) = a muted grey. The single source of per-child color, so
/// the face + body always agree. Aligned with the flat-art palette (FlatArt).
Color paletteFor(ChildGender g) => switch (g) {
      ChildGender.girl => FlatArt.magenta, // warm pink
      ChildGender.boy => FlatArt.cyan, // cool blue
      ChildGender.neutral => const Color(0xFF9FA8B2), // muted grey
    };

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: FlatArt.magenta,
      brightness: Brightness.light,
    ).copyWith(
      surface: FlatArt.cream,
      onSurface: FlatArt.ink,
    ),
    scaffoldBackgroundColor: FlatArt.cream,
  );
  return base.copyWith(
    // Rounded friendly font over the whole app.
    textTheme: GoogleFonts.baloo2TextTheme(base.textTheme)
        .apply(bodyColor: FlatArt.ink, displayColor: FlatArt.ink),
    appBarTheme: const AppBarTheme(
      backgroundColor: FlatArt.cream,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: FlatArt.ink,
      centerTitle: true,
    ),
  );
}
