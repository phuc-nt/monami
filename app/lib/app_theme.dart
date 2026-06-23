// App theme + per-child visuals: a consistently dark theme with a rounded,
// kid-friendly font (Baloo 2), a dark flat AppBar (no light-bar clash), and a
// subtle per-child background gradient so each child's screen feels personal.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'child_model.dart';

const Color kBgDark = Color(0xFF0B1016);

/// Per-gender palette: the tint that colors a child's card, the voice-screen
/// gradient, and the robot-face LEDs. Girl = warm pink; boy = cool blue; neutral
/// (guest / unspecified) = a muted grey. The single source of per-child color, so
/// the face + screen always agree. (Replaces the stand-in `childTint` that lived
/// in the picker.)
Color paletteFor(ChildGender g) => switch (g) {
      ChildGender.girl => const Color(0xFFE8A0D8), // warm pink
      ChildGender.boy => const Color(0xFF7CC4F6), // cool blue
      ChildGender.neutral => const Color(0xFF9FA8B2), // muted grey
    };

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.indigo,
      brightness: Brightness.dark,
    ),
    scaffoldBackgroundColor: kBgDark,
  );
  return base.copyWith(
    // Rounded friendly font over the whole app.
    textTheme: GoogleFonts.baloo2TextTheme(base.textTheme),
    appBarTheme: const AppBarTheme(
      backgroundColor: kBgDark,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: Colors.white,
      centerTitle: true,
    ),
  );
}

/// A subtle vertical gradient from the child's tint into the dark base — carries
/// the child's color across the whole screen, not just the robot face.
BoxDecoration childBackground(Color tint) => BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.alphaBlend(tint.withValues(alpha: 0.14), kBgDark),
          kBgDark,
        ],
      ),
    );
