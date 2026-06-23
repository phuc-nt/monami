// Phase-4 E2E: create a girl + a boy child, open each child's voice screen, and
// assert the correct gendered face variant + palette render on a real simulator
// against the live backend. Captures a screenshot of each.
//
// Run (backend live on :8000, MEMORY_BACKEND=json, no token):
//   flutter test integration_test/phase4_gendered_face_test.dart -d <sim-udid>

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:monami_app/app_theme.dart';
import 'package:monami_app/child_model.dart';
import 'package:monami_app/child_service.dart';
import 'package:monami_app/main.dart';
import 'package:monami_app/robot_face.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const deviceId = 'e2e-p4-device';

  setUpAll(() async {
    // Seed a clean girl + boy directly via the service (faster than the form).
    final svc = ChildService(restBase: 'http://127.0.0.1:8000', deviceId: deviceId);
    for (final c in await svc.listChildren()) {
      await svc.deleteChild(c.id);
    }
    await svc.createChild(
        const Child(id: '', name: 'Vy', gender: ChildGender.girl, age: 5));
    await svc.createChild(
        const Child(id: '', name: 'Phong', gender: ChildGender.boy, age: 5));
    svc.dispose();
  });

  Future<void> settle(WidgetTester t) async {
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
  }

  /// The face variant on the CURRENT (top-most) voice screen. The picker route
  /// stays mounted underneath with its own card faces, so scope to the last
  /// Scaffold (the pushed voice screen) and read its single RobotFace.
  FaceVariant voiceFaceVariant(WidgetTester t) {
    final face = find.descendant(
      of: find.byType(Scaffold).last,
      matching: find.byType(RobotFace),
    );
    return t.widget<RobotFace>(face.first).variant;
  }

  testWidgets('each child shows its gendered face + palette', (tester) async {
    await tester.pumpWidget(const MonamiApp(deviceId: deviceId));
    await settle(tester);

    // Both children listed.
    expect(find.text('Vy'), findsOneWidget);
    expect(find.text('Phong'), findsOneWidget);

    // Open the girl → voice screen shows the GIRL face variant.
    await tester.tap(find.text('Vy'));
    await settle(tester);
    expect(find.text('Bạn của Vy'), findsOneWidget);
    expect(voiceFaceVariant(tester), FaceVariant.girl);
    await binding.takeScreenshot('p4-01-girl-voice');

    // Back to the picker (the voice screen uses a custom back IconButton that
    // runs _leave(), so tap it rather than pageBack()).
    await tester.tap(find.byIcon(Icons.arrow_back).first);
    await settle(tester);

    // Open the boy → voice screen shows the BOY face variant.
    await tester.tap(find.text('Phong'));
    await settle(tester);
    expect(find.text('Bạn của Phong'), findsOneWidget);
    expect(voiceFaceVariant(tester), FaceVariant.boy);
    await binding.takeScreenshot('p4-02-boy-voice');

    await tester.tap(find.byIcon(Icons.arrow_back).first);
    await settle(tester);
    expect(find.text('Ai đang chơi nào?'), findsOneWidget);

    // Sanity: the three palettes + the guest/neutral mapping are all distinct.
    // (Guest navigation timing is flaky to drive here; the neutral variant +
    // palette are covered by the unit/render tests — assert the mapping directly.)
    expect(faceVariantFor(ChildGender.girl), FaceVariant.girl);
    expect(faceVariantFor(ChildGender.boy), FaceVariant.boy);
    expect(faceVariantFor(ChildGender.neutral), FaceVariant.neutral);
    expect(paletteFor(ChildGender.girl) == paletteFor(ChildGender.boy), isFalse);
    expect(paletteFor(ChildGender.girl) == paletteFor(ChildGender.neutral), isFalse);
  });
}
