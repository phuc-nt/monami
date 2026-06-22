// Voice state machine: ties mic capture, the WebSocket, and playback together.
//
// Interaction model: TAP-TO-TOGGLE (easy for a 5-year-old). One tap opens the
// mic and streams continuously; the backend's server VAD detects turn
// boundaries on natural pauses and Gemini replies per utterance. A second tap
// closes the mic. So one open-mic session can contain MANY turns.
//
//   idle --(tap)--> listening : mic streams 16k PCM continuously
//   listening : each turn the backend streams 24k PCM down + a turn_complete;
//               we play the reply and reset transcripts for the next utterance,
//               WITHOUT leaving listening (the child can just keep talking).
//   listening --(tap)--> idle : stop the mic.
//
// The Gemini Live session stays open across turns, so one socket serves the
// whole conversation. We rely on server VAD (proven in Phase 1) — no manual
// end_utterance is sent while the mic streams continuously.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'audio_capture.dart';
import 'audio_playback.dart';
import 'voice_socket.dart';

enum VoiceState { disconnected, idle, listening, speaking }

class VoiceController extends ChangeNotifier {
  VoiceController({String? url})
      : _url = url ?? 'ws://127.0.0.1:8000/ws/voice';

  final String _url;
  final AudioCapture _capture = AudioCapture();
  final AudioPlayback _playback = AudioPlayback();
  VoiceSocket? _socket;
  StreamSubscription<VoiceEvent>? _events;

  VoiceState _state = VoiceState.disconnected;
  VoiceState get state => _state;

  // True while the mic is open (the child tapped to talk). Independent of
  // whether the bot is currently speaking a reply — the mic stays open so the
  // child can keep the conversation going.
  bool _micOpen = false;
  bool get micOpen => _micOpen;

  // Conversation history: one Turn per utterance/reply pair. The last entry is
  // the current turn, which accumulates text until turn_complete; the next
  // input starts a fresh Turn so the chat reads top-to-bottom.
  final List<Turn> _turns = [];
  List<Turn> get turns => List.unmodifiable(_turns);
  bool _startNewTurnOnNextInput = false;

  String? _error;
  String? get error => _error;

  /// Connect to the backend and prepare playback. Call once at startup.
  Future<void> connect() async {
    _error = null;
    await _playback.init();
    _playback.onDrained = _onPlaybackDrained;
    _openSocket();
  }

  /// Manual reconnect (e.g. after a backend restart).
  Future<void> reconnect() async {
    await _stopMic();
    await _socket?.close();
    await _events?.cancel();
    _error = null;
    _openSocket();
  }

  void _openSocket() {
    final socket = VoiceSocket(_url);
    _socket = socket;
    _events = socket.connect().listen(
          _onEvent,
          onError: (e) => _disconnect('socket error: $e'),
          onDone: () => _disconnect(null),
        );
    _setState(VoiceState.idle);
  }

  /// Tap the talk button: toggle the mic open/closed.
  Future<void> toggleMic() async {
    if (_state == VoiceState.disconnected) return;
    if (_micOpen) {
      await _stopMic();
      _setState(VoiceState.idle);
    } else {
      await _startMic();
    }
  }

  Future<void> _startMic() async {
    if (!await _capture.hasPermission()) {
      _fail('no microphone permission / no input device');
      return;
    }
    _startNewTurnOnNextInput = true; // first input opens a fresh turn
    try {
      await _capture.start((chunk) => _socket?.sendAudio(chunk));
      _micOpen = true;
      _setState(VoiceState.listening);
    } catch (e) {
      _fail('capture failed: $e');
    }
  }

  Future<void> _stopMic() async {
    if (!_micOpen) return;
    _micOpen = false;
    await _capture.stop();
    // Flush any in-flight final utterance so the backend commits the last turn.
    _socket?.sendEndUtterance();
  }

  void _onEvent(VoiceEvent event) {
    switch (event) {
      case AudioChunk(:final pcm):
        if (_state == VoiceState.listening) {
          _setState(VoiceState.speaking);
          _playback.beginTurn(); // reply audio for this turn is arriving
        }
        _playback.enqueue(pcm);
      case InTranscript(:final text):
        // Gemini sends deltas (verified Phase 1).
        _currentTurn().inText += text;
        notifyListeners();
      case OutTranscript(:final text):
        _currentTurn().outText += text;
        notifyListeners();
      case TurnComplete():
        // Backend finished SENDING this reply. Let queued audio play out;
        // the next utterance starts a fresh Turn so history reads top-to-bottom.
        _playback.endTurn();
        _startNewTurnOnNextInput = true;
      case SocketError(:final message):
        _fail(message);
    }
  }

  // The turn that incoming transcript text belongs to. Starts a new one after a
  // completed turn (or at mic start) so consecutive turns don't run together.
  Turn _currentTurn() {
    if (_startNewTurnOnNextInput || _turns.isEmpty) {
      _turns.add(Turn());
      _startNewTurnOnNextInput = false;
    }
    return _turns.last;
  }

  void _onPlaybackDrained() {
    // A reply finished playing. If the mic is closed, we're fully idle.
    if (!_micOpen && _state == VoiceState.speaking) {
      _setState(VoiceState.idle);
    } else if (_micOpen && _state == VoiceState.speaking) {
      _setState(VoiceState.listening);
    }
  }

  void _setState(VoiceState s) {
    _state = s;
    notifyListeners();
  }

  void _fail(String message) {
    _error = message;
    _micOpen = false;
    _setState(VoiceState.idle);
  }

  void _disconnect(String? message) {
    _micOpen = false;
    if (message != null) _error = message;
    _setState(VoiceState.disconnected);
  }

  @override
  void dispose() {
    _events?.cancel();
    _capture.dispose();
    _playback.dispose();
    _socket?.close();
    super.dispose();
  }
}

/// One exchange in the conversation: what the child said + the companion's reply.
class Turn {
  String inText = '';
  String outText = '';
}
