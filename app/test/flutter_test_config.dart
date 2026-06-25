// Auto-loaded by `flutter test`. The flat-art UI renders text via GoogleFonts
// (Baloo 2), which is now bundled as an asset (see pubspec). Disable runtime
// fetching so tests load the bundled font instead of hitting the network.

import 'dart:async';

import 'package:google_fonts/google_fonts.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  await testMain();
}
