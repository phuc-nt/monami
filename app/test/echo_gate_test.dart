// Half-duplex echo gate: while the bot is speaking (and briefly after), mic audio
// must NOT be forwarded to the server, else an open speaker feeds the bot's own
// voice back into the mic and it replies to itself in a loop. Pure-function test
// of the decision (no platform plugins).

import 'package:flutter_test/flutter_test.dart';
import 'package:monami_app/voice_controller.dart';

void main() {
  final t0 = DateTime(2026, 6, 24, 12, 0, 0);
  bool send(VoiceState s, DateTime? endedAt, DateTime now) =>
      VoiceController.shouldSendMicAudio(s, endedAt, now);

  test('suppresses mic audio while the bot is speaking', () {
    expect(send(VoiceState.speaking, null, t0), isFalse);
  });

  test('sends mic audio while listening (normal case, no prior speech)', () {
    expect(send(VoiceState.listening, null, t0), isTrue);
    expect(send(VoiceState.idle, null, t0), isTrue);
  });

  test('suppresses within the echo-guard window after speech ends', () {
    final justEnded = t0;
    final within = t0.add(VoiceController.echoGuard - const Duration(milliseconds: 1));
    expect(send(VoiceState.listening, justEnded, within), isFalse);
  });

  test('resumes sending once the echo-guard window elapses', () {
    final ended = t0;
    final after = t0.add(VoiceController.echoGuard + const Duration(milliseconds: 1));
    expect(send(VoiceState.listening, ended, after), isTrue);
  });

  test('speaking always wins even if a stale guard timestamp is present', () {
    // If somehow still speaking, suppress regardless of the guard timestamp.
    final old = t0.subtract(const Duration(seconds: 10));
    expect(send(VoiceState.speaking, old, t0), isFalse);
  });
}
