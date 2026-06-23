import 'package:flutter_test/flutter_test.dart';
import 'package:monami_app/app_config.dart';

void main() {
  group('AppConfig.restBaseOf', () {
    test('cloud wss + /ws/voice path -> https origin (path stripped)', () {
      expect(
        AppConfig.restBaseOf('wss://foo.run.app/ws/voice'),
        'https://foo.run.app',
      );
    });

    test('local ws + port -> http origin with port (path stripped)', () {
      expect(
        AppConfig.restBaseOf('ws://127.0.0.1:8000/ws/voice'),
        'http://127.0.0.1:8000',
      );
    });

    test('already-http url is left as the origin', () {
      expect(AppConfig.restBaseOf('http://localhost:8000/ws/voice'),
          'http://localhost:8000');
    });

    test('no path still yields the bare origin', () {
      expect(AppConfig.restBaseOf('wss://foo.run.app'), 'https://foo.run.app');
    });
  });
}
