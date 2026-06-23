// Phase-5 E2E: tapping "Khách" opens a guest voice session with a neutral face,
// and the session writes NOTHING to the backend store. Runs against the live
// local backend on a simulator.
//
// Run (backend live on :8000, MEMORY_BACKEND=json, no token):
//   flutter test integration_test/phase5_guest_mode_test.dart -d <sim-udid>

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:monami_app/child_service.dart';
import 'package:monami_app/main.dart';
import 'package:monami_app/robot_face.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const deviceId = 'e2e-p5-device';

  setUpAll(() async {
    // Start from an empty device so the picker shows the guest entry directly.
    final svc = ChildService(restBase: 'http://127.0.0.1:8000', deviceId: deviceId);
    for (final c in await svc.listChildren()) {
      await svc.deleteChild(c.id);
    }
    svc.dispose();
  });

  Future<void> settle(WidgetTester t) async {
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
  }

  FaceVariant topFaceVariant(WidgetTester t) {
    final face = find.descendant(
      of: find.byType(Scaffold).last,
      matching: find.byType(RobotFace),
    );
    return t.widget<RobotFace>(face.first).variant;
  }

  testWidgets('guest opens a neutral session and persists nothing', (tester) async {
    await tester.pumpWidget(const MonamiApp(deviceId: deviceId));
    await settle(tester);

    // Empty device → guest entry is visible.
    expect(find.text('Khách (chơi nhanh)'), findsOneWidget);

    // Tap "Khách" → guest voice screen with the NEUTRAL face.
    await tester.tap(find.text('Khách (chơi nhanh)'));
    await settle(tester);
    expect(find.text('Bạn của Khách'), findsOneWidget);
    expect(topFaceVariant(tester), FaceVariant.neutral);

    // Give the (cold-start) socket a moment; a guest session must still write
    // nothing regardless of whether the Gemini session opens.
    await tester.pump(const Duration(seconds: 2));

    // Leave the guest session (custom back button).
    await tester.tap(find.byIcon(Icons.arrow_back).first);
    await settle(tester);
    expect(find.text('Khách (chơi nhanh)'), findsOneWidget); // back on picker

    // The KEY invariant: the guest device created NO children on the backend.
    final svc = ChildService(restBase: 'http://127.0.0.1:8000', deviceId: deviceId);
    expect(await svc.listChildren(), isEmpty);
    svc.dispose();
  });
}
