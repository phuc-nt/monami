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

// `connecting` covers the cold-start wait (scale-to-zero backend waking up) —
// the UI shows a friendly "waking" state and locks the talk button until idle.
enum VoiceState { disconnected, connecting, idle, listening, speaking }

/// Build the WS URL for a session. Empty values are dropped, so a guest session
/// (empty `deviceId`) connects with `?profile=guest` and NO `device` — which is
/// exactly what makes the backend persist nothing. Pure + side-effect-free so it
/// can be unit-tested without constructing a VoiceController (which would need
/// platform plugins). Order: device, profile, token.
String buildConnectUrl(
  String base, {
  required String profileId,
  String token = '',
  String deviceId = '',
}) {
  String url = base;
  void add(String key, String value) {
    if (value.isEmpty) return;
    final sep = url.contains('?') ? '&' : '?';
    url = '$url$sep$key=$value';
  }

  add('device', deviceId);
  add('profile', profileId);
  add('token', token);
  return url;
}

class VoiceController extends ChangeNotifier {
  /// [profileId] selects which child; it's passed to the backend as `?profile=`.
  /// [deviceId] scopes the child to this install (`?device=`); omit/empty for a
  /// guest session (the backend then persists nothing). [base] + [token] come
  /// from AppConfig (build-time); the token (if any) is `&token=` for the gate.
  ///
  /// The URL is assembled lazily at connect-time (not stored as a field) so the
  /// token + deviceId — both bearer secrets — never sit on the instance where a
  /// `toString()`/crash reporter could capture them.
  VoiceController({
    required String profileId,
    required String base,
    String token = '',
    String deviceId = '',
  })  : _base = base,
        _profileId = profileId,
        _token = token,
        _deviceId = deviceId;

  // ignore_for_file: prefer_initializing_formals
  // (the ctor maps named params straight to the private fields above)

  // Stored as private fields (not assembled into a URL field) so the token +
  // deviceId never live on the instance as a single capturable string.
  final String _base;
  final String _profileId;
  final String _token;
  final String _deviceId;

  String _buildUrl() =>
      buildConnectUrl(_base, profileId: _profileId, token: _token, deviceId: _deviceId);

  // How long to wait for the backend (incl. cold start) before showing an error.
  static const _connectTimeout = Duration(seconds: 15);
  Timer? _connectTimer;

  final AudioCapture _capture = AudioCapture();
  final AudioPlayback _playback = AudioPlayback();
  VoiceSocket? _socket;
  StreamSubscription<VoiceEvent>? _events;

  VoiceState _state = VoiceState.disconnected;
  VoiceState get state => _state;

  // Set in dispose() so async socket.ready callbacks (which can resolve a few
  // seconds after a back-tap during cold start) don't notify a disposed notifier.
  bool _disposed = false;

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

  // A short-lived "happy" effect right after a turn completes — a UI-only
  // transient, deliberately NOT a VoiceState (it's an expression, not a state).
  bool _happyPulse = false;
  bool get happyPulse => _happyPulse;
  Timer? _happyTimer;
  static const _happyPulseDuration = Duration(milliseconds: 900);

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
    // Build the URL here (not at construction) so the token/deviceId live only
    // for the duration of the call, never as a captured instance field.
    final socket = VoiceSocket(_buildUrl());
    _socket = socket;
    _setState(VoiceState.connecting); // cold-start wait; UI locks the talk button
    _events = socket.connect().listen(
          _onEvent,
          // Generic message — the raw error can contain the URL + token.
          onError: (_) => _disconnect('mất kết nối'),
          onDone: () => _disconnect(null),
        );
    // Watchdog: if the backend doesn't come up in time, surface a retry.
    _connectTimer?.cancel();
    _connectTimer = Timer(_connectTimeout, () {
      if (_state == VoiceState.connecting) {
        _disconnect('không kết nối được (thử lại?)');
      }
    });
    // The connection is "ready" only when the socket actually opens (after a
    // cold start this can take a few seconds) — then we go idle. These fire
    // async, so bail if the controller was disposed (e.g. back-tap mid cold start).
    socket.ready.then((_) {
      if (_disposed) return;
      _connectTimer?.cancel();
      if (_state == VoiceState.connecting) _setState(VoiceState.idle);
    }).catchError((_) {
      if (_disposed) return;
      _connectTimer?.cancel();
      // Don't surface the raw error — the WS URL (with the token) can appear in
      // it. Show a friendly, generic message instead.
      _disconnect('không kết nối được (thử lại?)');
    });
  }

  // Debounce rapid double-taps (a 5-year-old mashing the button) so a quick
  // second tap doesn't immediately toggle the mic back off.
  DateTime? _lastToggle;
  static const _toggleDebounce = Duration(milliseconds: 500);

  /// Tap the talk button: toggle the mic open/closed. Ignored until connected
  /// (the UI also disables the button while connecting/disconnected).
  Future<void> toggleMic() async {
    if (_state == VoiceState.disconnected || _state == VoiceState.connecting) {
      return;
    }
    // Only debounce RE-OPENING the mic (the rapid-mash pattern). A stop tap is
    // a deliberate action and is always honored — never leave the mic stuck open.
    final now = DateTime.now();
    if (!_micOpen &&
        _lastToggle != null &&
        now.difference(_lastToggle!) < _toggleDebounce) {
      return; // ignore a too-fast re-open
    }
    _lastToggle = now;
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
        // The happy pulse fires when playback DRAINS (the bot stops talking),
        // not here — see _onPlaybackDrained.
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

  void _triggerHappyPulse() {
    _happyPulse = true;
    notifyListeners();
    _happyTimer?.cancel();
    _happyTimer = Timer(_happyPulseDuration, () {
      _happyPulse = false;
      notifyListeners();
    });
  }

  void _onPlaybackDrained() {
    // A reply finished playing — celebrate, then settle to the live state.
    if (_state == VoiceState.speaking) {
      _triggerHappyPulse();
      _setState(_micOpen ? VoiceState.listening : VoiceState.idle);
    }
  }

  void _setState(VoiceState s) {
    if (_disposed) return; // never notify after dispose
    _state = s;
    notifyListeners();
  }

  void _fail(String message) {
    _error = message;
    _micOpen = false;
    _setState(VoiceState.idle);
  }

  void _disconnect(String? message) {
    _connectTimer?.cancel();
    _micOpen = false;
    if (message != null) _error = message;
    _setState(VoiceState.disconnected);
  }

  /// Gracefully end the session: stop the mic and CLOSE the socket, awaiting the
  /// close so the backend sees the disconnect promptly and summarizes this
  /// child's memory now (not when the next session opens). Call before popping
  /// the screen; dispose() is still safe to call afterwards.
  Future<void> shutdown() async {
    _happyTimer?.cancel();
    _connectTimer?.cancel();
    await _capture.stop();
    await _socket?.close(); // await: ensure the WS FIN flushes before we leave
    await _events?.cancel();
  }

  @override
  void dispose() {
    _disposed = true; // block any late async callbacks from notifying
    _happyTimer?.cancel();
    _connectTimer?.cancel();
    _socket?.close();
    _events?.cancel();
    _capture.dispose();
    _playback.dispose();
    super.dispose();
  }
}

/// One exchange in the conversation: what the child said + the companion's reply.
class Turn {
  String inText = '';
  String outText = '';
}
