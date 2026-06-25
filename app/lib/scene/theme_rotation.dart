// Device-wide world rotation for the Sticker-Scene UI. A single active world is
// shared across all children (not per-child) and persisted in shared_preferences.
//
// Behavior (from the approved handoff spec §3):
//   - randomPerSession (default): after a voice session longer than 2 minutes,
//     the NEXT time the picker shows, the world changes to a random DIFFERENT one.
//   - fixed: the chosen world is locked; no auto-rotation.
// First-run default world = 'night'.

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'scene_spec.dart';
import 'scene_worlds.dart';

/// A voice session must last at least this long to trigger a world rotation.
const Duration kRotationDwellThreshold = Duration(minutes: 2);

class ThemeRotation extends ChangeNotifier {
  ThemeRotation({String worldId = 'night', bool randomPerSession = true})
      // ignore: prefer_initializing_formals
      : _worldId = worldId,
        // ignore: prefer_initializing_formals
        _randomPerSession = randomPerSession;

  static const _kWorldId = 'theme_world_id';
  static const _kRandom = 'theme_random_per_session';

  String _worldId;
  bool _randomPerSession;

  // Seeded lazily; only used for runtime rotation choice (NOT in any painter, so
  // the "deterministic painters" rule is unaffected).
  final Random _rng = Random();

  String get currentWorldId => _worldId;
  bool get randomPerSession => _randomPerSession;

  /// The active world's SceneSpec (resolves an unknown id to the first world).
  SceneSpec get spec => specForId(_worldId);

  /// Load the persisted state (or first-run defaults). Call before runApp.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_kWorldId);
    if (id != null && allScenes.any((s) => s.id == id)) {
      _worldId = id;
    }
    _randomPerSession = prefs.getBool(_kRandom) ?? true;
    notifyListeners();
  }

  /// Call when a voice session ends, passing how long the child was on the voice
  /// screen. Rotates to a different world iff random mode AND dwell exceeded the
  /// threshold. No-op (and no notify) otherwise.
  Future<void> onSessionEnd(Duration dwell) async {
    if (!_randomPerSession) return; // fixed → never auto-change
    if (dwell < kRotationDwellThreshold) return;
    final next = _pickDifferent(_worldId);
    if (next == _worldId) return; // (defensive) nothing changed
    _worldId = next;
    await _save();
    notifyListeners();
  }

  /// Lock a specific world (fixed mode).
  Future<void> setFixed(String worldId) async {
    _randomPerSession = false;
    if (allScenes.any((s) => s.id == worldId)) _worldId = worldId;
    await _save();
    notifyListeners();
  }

  /// Switch to random-per-session rotation (keeps the current world until the
  /// next qualifying session).
  Future<void> setRandom() async {
    _randomPerSession = true;
    await _save();
    notifyListeners();
  }

  /// A random world id different from [current] (uniform over the other worlds).
  String _pickDifferent(String current) {
    final others = allScenes.where((s) => s.id != current).toList();
    if (others.isEmpty) return current; // (only one world — can't differ)
    return others[_rng.nextInt(others.length)].id;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kWorldId, _worldId);
    await prefs.setBool(_kRandom, _randomPerSession);
  }
}
