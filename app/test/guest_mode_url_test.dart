// Guest mode is just a profile/route variant — its only behavioral difference is
// the WS URL it connects with: NO `device` and `profile=guest`, so the backend
// (which keys persistence off the device) writes nothing. These tests lock in
// that URL shape via the pure builder (no controller / no plugins needed).

import 'package:flutter_test/flutter_test.dart';
import 'package:monami_app/voice_controller.dart';

void main() {
  const cloud = 'wss://x.run.app/ws/voice';

  test('guest session omits device and uses profile=guest', () {
    final url = buildConnectUrl(cloud, profileId: 'guest', deviceId: '', token: 't');
    expect(url, contains('profile=guest'));
    expect(url, isNot(contains('device='))); // empty deviceId dropped
    expect(url, contains('token=t'));
  });

  test('a registered child includes its device + child id', () {
    final url =
        buildConnectUrl(cloud, profileId: 'child123', deviceId: 'dev-abc', token: '');
    expect(url, contains('device=dev-abc'));
    expect(url, contains('profile=child123'));
    expect(url, isNot(contains('token='))); // empty token dropped
  });

  test('empty token is never appended (local dev)', () {
    final url = buildConnectUrl('ws://127.0.0.1:8000/ws/voice', profileId: 'guest');
    expect(url, isNot(contains('token=')));
    expect(url, contains('profile=guest'));
  });

  test('append order is device, profile, token, mode', () {
    final url = buildConnectUrl(cloud,
        profileId: 'p', deviceId: 'd', token: 't', mode: 'english');
    // The query string order is stable, matching what the backend expects.
    expect(url, endsWith('?device=d&profile=p&token=t&mode=english'));
  });

  test('free chat (empty mode) omits the mode param — backward compatible', () {
    final url = buildConnectUrl(cloud, profileId: 'p', mode: '');
    expect(url, isNot(contains('mode=')));
    expect(url, contains('profile=p'));
  });

  test('a learning mode appends mode=<value>', () {
    for (final m in ['english', 'stories', 'science']) {
      final url = buildConnectUrl(cloud, profileId: 'p', mode: m);
      expect(url, contains('mode=$m'));
    }
  });
}
