// Smoke test: the app builds and shows its initial UI. It does NOT exercise the
// voice loop or a real backend; with no backend reachable, the service-backed
// picker resolves to its error/retry state — which is the correct, non-crashing
// behavior we want to assert (the tree renders + the 3-state handling works).

import 'package:flutter_test/flutter_test.dart';

import 'package:monami_app/main.dart';

void main() {
  testWidgets('app boots to the picker; failed fetch shows error not empty',
      (tester) async {
    await tester.pumpWidget(const MonamiApp(deviceId: 'test-device'));
    // In the test binding, http returns 400 with no real network, so the picker
    // resolves to its ERROR state. Pump until it settles.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // The error state (retry), NOT the empty state — a failed fetch must never
    // look like "no children" (which would invite duplicate creation).
    expect(find.text('Không tải được danh sách bé'), findsOneWidget);
    expect(find.text('Thử lại'), findsOneWidget);
    expect(find.text('Thêm bé để bắt đầu'), findsNothing);
  });
}
