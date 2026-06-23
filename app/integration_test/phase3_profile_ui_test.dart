// Phase-3 visual E2E: drive the REAL profile-management UI against the REAL
// local backend on a simulator. Empty → add child → see card → manage →
// edit/clear memory → delete → back to empty. Captures screenshots.
//
// Run (backend live on :8000, MEMORY_BACKEND=json, no token):
//   flutter test integration_test/phase3_profile_ui_test.dart -d <sim-udid>

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:monami_app/child_service.dart';
import 'package:monami_app/main.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // A unique device per run so reruns start clean.
  const deviceId = 'e2e-p3-device';

  setUpAll(() async {
    // Clean any leftovers from a previous run.
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

  testWidgets('full profile management flow', (tester) async {
    await tester.pumpWidget(const MonamiApp(deviceId: deviceId));
    await settle(tester);

    // 1) Empty state (real backend, no children yet).
    expect(find.text('Thêm bé để bắt đầu'), findsOneWidget);
    await binding.takeScreenshot('p3-01-empty');

    // 2) Tap "Thêm bé" → form.
    await tester.tap(find.text('Thêm bé'));
    await settle(tester);
    expect(find.text('Tên bé'), findsOneWidget);

    // 3) Fill the form: name + gender (girl) and save.
    await tester.enterText(find.widgetWithText(TextFormField, '').first, 'Bé Vy');
    await tester.tap(find.text('Bạn gái'));
    await settle(tester);
    await binding.takeScreenshot('p3-02-form-filled');
    await tester.tap(find.widgetWithText(FilledButton, 'Thêm bé'));
    await settle(tester);

    // 4) Back on the picker — the card shows.
    expect(find.text('Bé Vy'), findsOneWidget);
    expect(find.text('Ai đang chơi nào?'), findsOneWidget);
    await binding.takeScreenshot('p3-03-one-child');

    // 5) Open manage (gear) → edit memory.
    await tester.tap(find.byIcon(Icons.settings).first);
    await settle(tester);
    expect(find.text('Bạn nhỏ đang nhớ về bé'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Sửa'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, 'thích Elsa và khủng long');
    await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
    await settle(tester);
    expect(find.text('thích Elsa và khủng long'), findsOneWidget);
    await binding.takeScreenshot('p3-04-memory-set');

    // 6) Clear memory (confirm).
    await tester.tap(find.widgetWithText(TextButton, 'Xóa trí nhớ'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Xóa trí nhớ'));
    await settle(tester);
    expect(find.text('(chưa nhớ gì)'), findsOneWidget);

    // 7) Delete the child (confirm) → back to empty.
    await tester.tap(find.widgetWithText(ListTile, 'Xóa bé'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Xóa bé'));
    await settle(tester);
    expect(find.text('Thêm bé để bắt đầu'), findsOneWidget);
    await binding.takeScreenshot('p3-05-back-to-empty');
  });
}
