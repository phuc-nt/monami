// The learning modes the child can pick on the voice screen. `chat` is free chat
// (the default, unchanged) — it sends NO `mode` param, so the backend behaves
// exactly as before. The other two send `?mode=<wsValue>`.
//
// The `wsValue` strings MUST match the backend's learning_modes.VALID_MODES
// ("english"/"science") exactly — a mismatch would silently fall back to free
// chat on the server. This file is the single app-side source of truth.

import 'package:flutter/material.dart';

enum LearningMode {
  chat,
  english,
  science;

  /// The `mode` query value sent to the backend, or null for free chat (no param).
  String? get wsValue => switch (this) {
        LearningMode.chat => null,
        LearningMode.english => 'english',
        LearningMode.science => 'science',
      };

  /// Short VN label for the selector button (kid-facing).
  String get label => switch (this) {
        LearningMode.chat => 'Trò chuyện',
        LearningMode.english => 'Tiếng Anh',
        LearningMode.science => 'Khoa học',
      };

  /// Icon for the selector button.
  IconData get icon => switch (this) {
        LearningMode.chat => Icons.chat_bubble_outline,
        LearningMode.english => Icons.abc,
        LearningMode.science => Icons.science_outlined,
      };
}
