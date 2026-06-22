// Mic capture: start/stop a 16 kHz mono PCM16 stream from the default input.
//
// Verified in the Phase 2 audio spike: `record`'s startStream with
// AudioEncoder.pcm16bits delivers raw little-endian PCM16 on macOS desktop
// (NOT 32-bit float). The backend expects exactly 16 kHz mono PCM16 chunks.

import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

class AudioCapture {
  AudioCapture({this.sampleRate = 16000});

  final int sampleRate;
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _sub;

  /// True if the input device + permission allow recording.
  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Start capturing; each emitted chunk is raw 16 kHz mono PCM16 bytes.
  /// Throws if no input device is available or permission is denied.
  Future<void> start(void Function(Uint8List chunk) onChunk) async {
    final config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: sampleRate,
      numChannels: 1,
    );
    final stream = await _recorder.startStream(config);
    _sub = stream.listen(onChunk);
  }

  /// Stop capturing and release the input stream.
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
  }

  Future<void> dispose() async {
    await stop();
    await _recorder.dispose();
  }
}
