// The app-side LearningMode enum must mirror the backend's mode strings exactly
// (backend learning_modes.VALID_MODES = english|science). A drift here would
// silently fall back to free chat on the server.

import 'package:flutter_test/flutter_test.dart';
import 'package:monami_app/learning_mode.dart';

void main() {
  test('chat sends no mode (free chat = backend default)', () {
    expect(LearningMode.chat.wsValue, isNull);
  });

  test('learning modes map to the exact backend strings', () {
    expect(LearningMode.english.wsValue, 'english');
    expect(LearningMode.science.wsValue, 'science');
  });

  test('science label is "Khoa học" (renamed from "Vì sao?")', () {
    expect(LearningMode.science.label, 'Khoa học');
  });

  test('every mode has a VN label + icon', () {
    for (final m in LearningMode.values) {
      expect(m.label, isNotEmpty);
      expect(m.icon, isNotNull);
    }
  });

  test('there are exactly 3 modes (chat + 2 learning)', () {
    expect(LearningMode.values.length, 3);
  });
}
