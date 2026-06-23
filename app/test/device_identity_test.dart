import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monami_app/device_identity.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Fresh in-memory prefs each test; clear any mocked Keychain values.
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('first launch generates + persists a deviceId', () async {
    final id = await DeviceIdentity().ensure();
    expect(id, isNotEmpty);
    // Persisted to BOTH stores so they converge.
    expect(await const FlutterSecureStorage().read(key: 'monami_device_id'), id);
    expect(await SharedPreferencesAsync().getString('monami_device_id'), id);
  });

  test('reinstall: prefs wiped but Keychain kept -> same id returned', () async {
    // Simulate a prior install whose id survives in the Keychain.
    FlutterSecureStorage.setMockInitialValues({'monami_device_id': 'kept-id'});
    // prefs is empty (reinstall wipes it).
    final id = await DeviceIdentity().ensure();
    expect(id, 'kept-id');
    // The cache is repopulated from the Keychain.
    expect(await SharedPreferencesAsync().getString('monami_device_id'), 'kept-id');
  });

  test('same instance returns a stable id across calls', () async {
    final d = DeviceIdentity();
    final a = await d.ensure();
    final b = await d.ensure();
    expect(a, b);
  });

  test('two ensures (new instances) read back the same persisted id', () async {
    final first = await DeviceIdentity().ensure();
    final second = await DeviceIdentity().ensure();
    expect(first, second);
  });
}
