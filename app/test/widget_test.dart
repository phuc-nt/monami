// Smoke test: the app builds and shows its initial UI. It does NOT exercise the
// voice loop (that needs a running backend + a microphone); it only verifies the
// widget tree renders without throwing and the key affordances are present.

import 'package:flutter_test/flutter_test.dart';

import 'package:monami_app/main.dart';

void main() {
  testWidgets('app opens on the child picker', (WidgetTester tester) async {
    await tester.pumpWidget(const MonamiApp());
    await tester.pump();

    // The picker prompts the child to choose, with both children present.
    expect(find.text('Ai đang chơi nào?'), findsOneWidget);
    expect(find.text('Vy'), findsOneWidget);
    expect(find.text('Phong'), findsOneWidget);
  });
}
