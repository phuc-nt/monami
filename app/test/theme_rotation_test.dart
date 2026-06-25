// Unit tests for the device-wide world rotation (ThemeRotation). Uses an
// in-memory SharedPreferences so nothing touches the device. Asserts: default
// world, the >2-min rotation rule, the <2-min no-op, fixed-mode locking, the
// "never the current world" invariant, and persistence round-trips.

import 'package:flutter_test/flutter_test.dart';
import 'package:monami_app/scene/scene_worlds.dart';
import 'package:monami_app/scene/theme_rotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('first run defaults to night + random mode', () async {
    final tr = ThemeRotation();
    await tr.load();
    expect(tr.currentWorldId, 'night');
    expect(tr.randomPerSession, isTrue);
    expect(tr.spec.id, 'night');
  });

  test('a >2-min session in random mode rotates to a DIFFERENT world', () async {
    final tr = ThemeRotation();
    await tr.load();
    final before = tr.currentWorldId;
    await tr.onSessionEnd(const Duration(minutes: 3));
    expect(tr.currentWorldId, isNot(before)); // changed
    expect(allScenes.any((s) => s.id == tr.currentWorldId), isTrue); // valid
  });

  test('a <2-min session never rotates', () async {
    final tr = ThemeRotation();
    await tr.load();
    final before = tr.currentWorldId;
    await tr.onSessionEnd(const Duration(seconds: 119));
    expect(tr.currentWorldId, before); // unchanged
  });

  test('fixed mode never auto-rotates, even after a long session', () async {
    final tr = ThemeRotation();
    await tr.load();
    await tr.setFixed('forest');
    expect(tr.currentWorldId, 'forest');
    expect(tr.randomPerSession, isFalse);
    await tr.onSessionEnd(const Duration(minutes: 10));
    expect(tr.currentWorldId, 'forest'); // locked
  });

  test('rotation never returns the current world (many draws)', () async {
    final tr = ThemeRotation();
    await tr.load();
    for (var i = 0; i < 50; i++) {
      final before = tr.currentWorldId;
      await tr.onSessionEnd(const Duration(minutes: 3));
      expect(tr.currentWorldId, isNot(before));
    }
  });

  test('state persists across a reload', () async {
    final tr1 = ThemeRotation();
    await tr1.load();
    await tr1.setFixed('snow');
    // A fresh instance reads the same persisted state.
    final tr2 = ThemeRotation();
    await tr2.load();
    expect(tr2.currentWorldId, 'snow');
    expect(tr2.randomPerSession, isFalse);
  });

  test('setRandom switches mode but keeps the current world', () async {
    final tr = ThemeRotation();
    await tr.load();
    await tr.setFixed('rainbow');
    await tr.setRandom();
    expect(tr.randomPerSession, isTrue);
    expect(tr.currentWorldId, 'rainbow'); // unchanged until a qualifying session
  });
}
