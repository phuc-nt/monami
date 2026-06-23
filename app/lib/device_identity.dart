// Anonymous per-install device identity.
//
// The app has no accounts: a child's profiles + memory are scoped under a
// `deviceId` the app generates once and reuses forever. Persistence strategy:
//
//   - PRIMARY: the iOS Keychain (flutter_secure_storage) — survives an app
//     delete/reinstall, so a family doesn't lose their children's profiles when
//     they update the app. (May also sync via iCloud Keychain.)
//   - CACHE/FALLBACK: shared_preferences — a fast local copy, and a degraded
//     fallback if the Keychain is briefly unavailable (e.g. on a simulator).
//
// The deviceId is a bearer capability (whoever holds it can reach that device's
// children via the REST API), so it is NEVER logged or printed.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceIdentity {
  DeviceIdentity({
    FlutterSecureStorage? secure,
    SharedPreferencesAsync? prefs,
  })  : _secure = secure ?? const FlutterSecureStorage(),
        _prefs = prefs ?? SharedPreferencesAsync();

  static const _key = 'monami_device_id';

  final FlutterSecureStorage _secure;
  final SharedPreferencesAsync _prefs;

  String? _cached;

  /// Return the persistent deviceId, generating + storing one on first launch.
  ///
  /// Resolution order: in-memory → Keychain → prefs → generate new. Whatever is
  /// found is written back to BOTH stores so they converge.
  Future<String> ensure() async {
    if (_cached != null) return _cached!;

    String? id = await _readSecure();
    id ??= await _readPrefs(); // Keychain miss → try the prefs fallback.
    id ??= const Uuid().v4(); // First launch (or both stores empty).

    await _writeBoth(id);
    _cached = id;
    return id;
  }

  Future<String?> _readSecure() async {
    try {
      return await _secure.read(key: _key);
    } catch (_) {
      // Keychain can be unavailable (locked device, simulator quirks). Degrade
      // to prefs rather than failing identity entirely.
      return null;
    }
  }

  Future<String?> _readPrefs() async {
    try {
      return await _prefs.getString(_key);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeBoth(String id) async {
    try {
      await _secure.write(key: _key, value: id);
    } catch (_) {
      // Best-effort: if the Keychain write fails, prefs still carries the id for
      // this install (it just won't survive a reinstall — acceptable fallback).
    }
    try {
      await _prefs.setString(_key, id);
    } catch (_) {/* ignore: cache write is non-critical */}
  }
}
