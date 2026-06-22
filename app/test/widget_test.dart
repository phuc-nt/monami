// Smoke test: the app builds and shows its initial UI. It does NOT exercise the
// voice loop (that needs a running backend + a microphone); it only verifies the
// widget tree renders without throwing and the key affordances are present.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:monami_app/main.dart';

void main() {
  testWidgets('app renders initial voice UI', (WidgetTester tester) async {
    await tester.pumpWidget(const MonamiApp());
    await tester.pump();

    // The talk button label and the empty-state hint should be on screen.
    expect(find.text('Chạm để nói'), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
  });
}
