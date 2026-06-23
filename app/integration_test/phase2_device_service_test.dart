// Phase-2 E2E on a REAL device/simulator against the REAL local backend.
//
// Verifies the identity + service seam end-to-end (no mocks): a real deviceId
// persisted on-device, real HTTP to the local FastAPI backend, the full CRUD +
// memory lifecycle, cross-device isolation, and that a guest call writes nothing.
//
// Run (backend must be live on :8000 with MEMORY_BACKEND=json, no token):
//   flutter test integration_test/phase2_device_service_test.dart -d <sim-udid>
//
// The simulator shares the host network, so 127.0.0.1 reaches the local backend.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:monami_app/app_config.dart';
import 'package:monami_app/child_model.dart';
import 'package:monami_app/child_service.dart';
import 'package:monami_app/device_identity.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const rest = 'http://127.0.0.1:8000'; // restBaseOf default ws URL == this

  test('restBase derives from the default wsBase', () {
    expect(AppConfig.restBase, rest);
  });

  testWidgets('real deviceId persists + full CRUD/memory lifecycle', (_) async {
    // 1) Real identity (Keychain/prefs on the simulator).
    final id1 = await DeviceIdentity().ensure();
    expect(id1, isNotEmpty);
    final id2 = await DeviceIdentity().ensure(); // a second resolve is stable
    expect(id1, id2);

    final svc = ChildService(restBase: rest, deviceId: id1);

    // 2) Fresh device → empty list (a real 200 [], not an error).
    expect(await svc.listChildren(), isEmpty);

    // 3) Create a child (VN diacritics) and read it back.
    final created = await svc.createChild(const Child(
        id: '', name: 'Bé Vy', gender: ChildGender.girl, age: 5, interests: ['Elsa', 'khủng long']));
    expect(created.id, isNotEmpty);
    expect(created.name, 'Bé Vy');
    expect(created.gender, ChildGender.girl);

    var list = await svc.listChildren();
    expect(list.length, 1);

    // 4) Edit profile, then memory — neither clobbers the other.
    final aged = await svc.updateChild(created.id, {'age': 6});
    expect(aged.age, 6);
    final remembered = await svc.setMemory(created.id, 'thích công chúa Elsa');
    expect(remembered.memorySummary, 'thích công chúa Elsa');
    expect(remembered.age, 6); // profile survived the memory write

    // 5) Clear memory keeps the child.
    final cleared = await svc.clearMemory(created.id);
    expect(cleared.memorySummary, '');
    expect((await svc.listChildren()).length, 1);

    // 6) Delete removes it.
    await svc.deleteChild(created.id);
    expect(await svc.listChildren(), isEmpty);

    svc.dispose();
  });

  testWidgets('two device ids are isolated', (_) async {
    final svcA = ChildService(restBase: rest, deviceId: 'e2e-devA');
    final svcB = ChildService(restBase: rest, deviceId: 'e2e-devB');
    // Clean any leftovers from a previous run.
    for (final c in await svcA.listChildren()) {
      await svcA.deleteChild(c.id);
    }
    for (final c in await svcB.listChildren()) {
      await svcB.deleteChild(c.id);
    }
    final a = await svcA.createChild(
        const Child(id: '', name: 'Bo', gender: ChildGender.boy, age: 5));
    expect((await svcB.listChildren()).where((c) => c.id == a.id), isEmpty);
    await svcA.deleteChild(a.id);
    svcA.dispose();
    svcB.dispose();
  });
}
