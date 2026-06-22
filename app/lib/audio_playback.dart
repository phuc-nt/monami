// Streaming playback of raw 24 kHz mono PCM16 received from the backend.
//
// flutter_pcm_sound (verified on macOS in the Phase 2 spike) uses a feed-callback
// model: it fires onFeed when its internal buffer runs low, and we hand it more
// samples. Response audio arrives over the WebSocket in chunks, so we queue
// arrivals and drain the queue on each feed callback.
//
// Keep-alive vs. idle: while a reply is in progress (more chunks expected) we
// feed short silence to bridge a momentarily-starved queue without glitching.
// Once the turn is marked complete AND the queue has fully drained, we stop
// feeding so the engine goes idle (no silence treadmill) and we fire onDrained
// so the controller knows the reply finished PLAYING (not just finished arriving).

import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';

class AudioPlayback {
  AudioPlayback({this.sampleRate = 24000});

  final int sampleRate;
  final Queue<Uint8List> _queue = Queue<Uint8List>();
  bool _ready = false;

  // True while the backend may still send more audio for the current reply.
  // When false, an empty queue means the reply has fully played out.
  bool _turnActive = false;

  /// Called when the current reply has finished PLAYING (queue drained after the
  /// turn was marked complete). Lets the controller move speaking -> idle.
  void Function()? onDrained;

  /// One-time engine setup. Safe to call once at startup.
  Future<void> init() async {
    if (_ready) return;
    await FlutterPcmSound.setup(sampleRate: sampleRate, channelCount: 1);
    // Fire the feed callback while the buffered frame count is below this.
    await FlutterPcmSound.setFeedThreshold(sampleRate ~/ 10); // ~100ms
    FlutterPcmSound.setFeedCallback(_onFeed);
    _ready = true;
  }

  /// Mark the start of a reply: audio chunks are about to stream in.
  void beginTurn() {
    _turnActive = true;
  }

  /// Backend signalled turn_complete: no more audio will arrive. Remaining
  /// queued audio still plays out; onDrained fires once it does. Returns true if
  /// audio is still pending (drain will fire later), false if nothing was queued
  /// (the caller should go idle now — the feed callback won't fire on its own).
  bool endTurn() {
    _turnActive = false;
    return _queue.isNotEmpty;
  }

  /// Enqueue a chunk of raw 24 kHz mono PCM16 from the backend.
  void enqueue(Uint8List pcm) {
    if (!_ready) return;
    _queue.add(pcm);
    // Kick the engine in case it went idle after the previous reply drained.
    FlutterPcmSound.start();
  }

  /// Drop any pending audio (e.g. on disconnect). NOTE: do not call mid-reply
  /// unless you intend to cut it off — the controller only clears between turns.
  void clear() {
    _queue.clear();
    _turnActive = false;
  }

  void _onFeed(int remainingFrames) {
    if (!_ready) return;
    if (_queue.isNotEmpty) {
      final chunk = _queue.removeFirst();
      FlutterPcmSound.feed(PcmArrayInt16(bytes: chunk.buffer.asByteData()));
      return;
    }
    // Queue empty.
    if (_turnActive) {
      // Reply still streaming but momentarily starved: feed a little silence to
      // keep the engine calling back until the next chunk arrives.
      FlutterPcmSound.feed(PcmArrayInt16.zeros(count: sampleRate ~/ 20)); // 50ms
      return;
    }
    // Turn done and queue drained. Stop feeding (engine idles; the next
    // enqueue() re-arms via start()) and tell the controller playback finished.
    if (remainingFrames == 0) {
      onDrained?.call();
    }
  }

  Future<void> dispose() async {
    _queue.clear();
    onDrained = null;
    await FlutterPcmSound.release();
    _ready = false;
  }
}
