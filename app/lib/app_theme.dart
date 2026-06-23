// App theme + per-child visuals: a consistently dark theme with a rounded,
// kid-friendly font (Baloo 2), a dark flat AppBar (no light-bar clash), and a
// subtle per-child background gradient so each child's screen feels personal.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const Color kBgDark = Color(0xFF0B1016);

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
