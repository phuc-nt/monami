// WebSocket transport to the local backend, matching backend/gemini_session.py.
//
// client -> server:
//   binary frame                = raw 16 kHz mono PCM16 audio chunk
//   {"type":"end_utterance"}    = push-to-talk released; flush the turn
// server -> client:
//   binary frame                = 24 kHz mono PCM16 response audio
//   {"type":"in_transcript", "text":…} / {"type":"out_transcript", "text":…}
//   {"type":"turn_complete"} / {"type":"error", "message":…}

import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

/// A decoded server->client event.
sealed class VoiceEvent {
  const VoiceEvent();
}

class AudioChunk extends VoiceEvent {
  const AudioChunk(this.pcm);
  final Uint8List pcm;
}

class InTranscript extends VoiceEvent {
  const InTranscript(this.text);
  final String text;
}

class OutTranscript extends VoiceEvent {
  const OutTranscript(this.text);
  final String text;
}

class TurnComplete extends VoiceEvent {
  const TurnComplete();
}

class SocketError extends VoiceEvent {
  const SocketError(this.message);
  final String message;
}

class VoiceSocket {
  VoiceSocket(this.url);

  /// e.g. ws://127.0.0.1:8000/ws/voice
  final String url;
  WebSocketChannel? _channel;

  /// Connect and return a stream of decoded events. Binary frames become
  /// [AudioChunk]; JSON frames map to the typed events above.
  Stream<VoiceEvent> connect() {
    final channel = WebSocketChannel.connect(Uri.parse(url));
    _channel = channel;
    return channel.stream.map(_decode).where((e) => e != null).cast<VoiceEvent>();
  }

  /// Completes when the underlying connection is actually open (or throws if it
  /// fails). Used to distinguish "still cold-starting" from "ready".
  Future<void> get ready async => _channel?.ready;

  VoiceEvent? _decode(dynamic message) {
    if (message is List<int>) {
      return AudioChunk(Uint8List.fromList(message));
    }
    if (message is String) {
      final Map<String, dynamic> obj;
      try {
        obj = jsonDecode(message) as Map<String, dynamic>;
      } on FormatException {
        return null; // ignore a malformed frame rather than killing the stream
      }
      switch (obj['type']) {
        case 'in_transcript':
          return InTranscript(obj['text'] as String? ?? '');
        case 'out_transcript':
          return OutTranscript(obj['text'] as String? ?? '');
        case 'turn_complete':
          return const TurnComplete();
        case 'error':
          return SocketError(obj['message'] as String? ?? 'unknown error');
      }
    }
    return null; // unknown frame type — ignore
  }

  /// Send a raw PCM16 audio chunk (binary frame).
  void sendAudio(Uint8List pcm) => _channel?.sink.add(pcm);

  /// Signal end-of-utterance so the backend flushes the turn (trailing silence).
  void sendEndUtterance() =>
      _channel?.sink.add(jsonEncode({'type': 'end_utterance'}));

  Future<void> close() async {
    await _channel?.sink.close(ws_status.normalClosure);
    _channel = null;
  }
}
