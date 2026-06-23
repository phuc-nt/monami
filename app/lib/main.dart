// Voice companion home: a cute LED robot face the child talks to. Tap the button
// to talk; the face reacts to the live voice state (listening / talking / happy /
// sleepy). The transcript chat is hidden by default behind a small dev toggle.

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import 'app_config.dart';
import 'app_theme.dart';
import 'child_model.dart';
import 'child_service.dart';
import 'device_identity.dart';
import 'profile_picker.dart';
import 'responsive.dart';
import 'robot_face.dart';
import 'voice_controller.dart';

/// Map the voice state (+ happy pulse) to a robot expression. The happy pulse
/// wins over a connected state, but a disconnect (sleepy) always shows through.
RobotExpression _expressionFor(VoiceController c) {
  if (c.happyPulse && c.state != VoiceState.disconnected) {
    return RobotExpression.happy;
  }
  return switch (c.state) {
    VoiceState.disconnected => RobotExpression.sleepy,
    VoiceState.connecting => RobotExpression.sleepy, // waking up (cold start)
    VoiceState.idle => RobotExpression.calm,
    VoiceState.listening => RobotExpression.attentive,
    VoiceState.speaking => RobotExpression.talking,
  };
}

Future<void> main() async {
  // Platform channels (Keychain via flutter_secure_storage, shared_preferences)
  // need the binding initialized before we resolve the device identity.
  WidgetsFlutterBinding.ensureInitialized();
  final deviceId = await DeviceIdentity().ensure();
  runApp(MonamiApp(deviceId: deviceId));
}

class MonamiApp extends StatelessWidget {
  const MonamiApp({super.key, required this.deviceId});

  /// This install's anonymous id; scopes children + memory on the backend.
  final String deviceId;

  @override
  Widget build(BuildContext context) {
    // One service for the app, bound to this device + the build-time config.
    final service = ChildService(
      restBase: AppConfig.restBase,
      deviceId: deviceId,
      token: AppConfig.token,
    );
    return MaterialApp(
      title: 'monami',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: Builder(
        builder: (context) => ProfilePicker(
          service: service,
          onPick: (child) {
            final nav = Navigator.of(context);
            // Guard a fast double-tap (likely with a 5-year-old): if we've
            // already pushed VoiceHome, ignore the extra tap so we don't open a
            // second session/socket/mic.
            if (nav.canPop()) return;
            nav.push(MaterialPageRoute(
              builder: (_) => VoiceHome(child: child, deviceId: deviceId),
            ));
          },
          onGuest: () {
            final nav = Navigator.of(context);
            if (nav.canPop()) return;
            // Guest: no deviceId, the "guest" profile → backend persists nothing.
            // (Full guest UX lands in phase 5; this already routes correctly.)
            nav.push(MaterialPageRoute(
              builder: (_) => const VoiceHome.guest(),
            ));
          },
        ),
      ),
    );
  }
}

class VoiceHome extends StatefulWidget {
  const VoiceHome({super.key, required this.child, this.deviceId = ''});

  /// Guest session: no child profile, no deviceId → backend persists nothing.
  const VoiceHome.guest({super.key})
      : child = null,
        deviceId = '';

  /// The selected child (drives the profile + theme color). Null = guest.
  final Child? child;

  /// This install's deviceId, scoping the child + memory on the backend. Empty
  /// for a guest session.
  final String deviceId;

  bool get isGuest => child == null;

  /// The backend profile id: the child's id, or "guest" for a guest session.
  String get profileId => child?.id ?? 'guest';

  /// Display name + tint, with neutral fallback for guest.
  String get displayName => child?.name ?? 'Khách';
  Color get tint =>
      childTint(child?.gender ?? ChildGender.neutral);

  @override
  State<VoiceHome> createState() => _VoiceHomeState();
}

class _VoiceHomeState extends State<VoiceHome> {
  late final VoiceController _controller;
  bool _showTranscript = false; // dev-only chat view, hidden by default

  @override
  void initState() {
    super.initState();
    _controller = VoiceController(
      profileId: widget.profileId,
      base: AppConfig.wsBase,
      token: AppConfig.token,
      deviceId: widget.deviceId,
    );
    _controller.connect();
  }

  bool _leaving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Close the session (flush the WS) BEFORE leaving so the backend summarizes
  // this child's memory now, then pop back to the picker.
  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    await _controller.shutdown();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Intercept the back gesture/arrow: run shutdown() first, then pop.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        // Transparent so the per-child gradient shows through.
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          // Back returns to the picker → ends the session → backend summarizes.
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _leave,
          ),
          // Long-press the title to toggle the dev transcript — hidden from a
          // child (no visible button), reachable by the grown-up.
          title: GestureDetector(
            onLongPress: () =>
                setState(() => _showTranscript = !_showTranscript),
            child: Text('Bạn của ${widget.displayName}'),
          ),
        ),
        body: Container(
          decoration: childBackground(widget.tint),
          child: SafeArea(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final pad = context.isTablet ? 40.0 : 24.0;
                // Hide the status text on the kid view once we're live (the face
                // conveys idle/listening/speaking). Keep it for connecting (the
                // cold-start "Đang đánh thức bạn nhỏ…" cue) and disconnected (with
                // the reconnect button) + any error.
                final showStatus =
                    _controller.state == VoiceState.connecting ||
                        _controller.state == VoiceState.disconnected ||
                        _controller.error != null;
                return Padding(
                  padding: EdgeInsets.all(pad),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // The robot face is the hero — filling the space, with a
                      // soft glow behind it in the child's color.
                      Expanded(
                        flex: _showTranscript ? 3 : 5,
                        child: Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                                maxWidth: context.isTablet ? 720 : 560),
                            child: _GlowingFace(
                              expression: _expressionFor(_controller),
                              color: widget.tint,
                            ),
                          ),
                        ),
                      ),
                      if (showStatus) ...[
                        const SizedBox(height: 12),
                        _StatusLine(
                          state: _controller.state,
                          error: _controller.error,
                          onReconnect: _controller.reconnect,
                        ),
                      ],
                      if (_showTranscript) ...[
                        const SizedBox(height: 12),
                        Expanded(
                          flex: 2,
                          child: _TranscriptView(turns: _controller.turns),
                        ),
                      ],
                      const SizedBox(height: 20),
                      _TalkButton(controller: _controller),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// The robot face hero: the LED face with a soft radial glow behind it in the
/// child's color, so it reads as the centerpiece rather than floating in space.
class _GlowingFace extends StatelessWidget {
  const _GlowingFace({required this.expression, required this.color});
  final RobotExpression expression;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: [color.withValues(alpha: 0.22), Colors.transparent],
          radius: 0.7,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: RobotFace(expression: expression, litColor: color),
      ),
    );
  }
}

/// A slim status line under the robot face: a short label + (on disconnect) a
/// reconnect button, plus any error text. The face carries the main expression;
/// this is just words for the grown-up.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.state, this.error, this.onReconnect});
  final VoiceState state;
  final String? error;
  final VoidCallback? onReconnect;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      VoiceState.disconnected => ('Mất kết nối', Colors.grey),
      VoiceState.connecting => ('Đang đánh thức bạn nhỏ…', Colors.amberAccent),
      VoiceState.idle => ('Sẵn sàng — chạm để nói', Colors.greenAccent),
      VoiceState.listening => ('Đang nghe bé…', Colors.redAccent),
      VoiceState.speaking => ('Đang trả lời…', Colors.lightBlueAccent),
    };
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.circle, size: 10, color: color),
            const SizedBox(width: 8),
            Flexible(
              child: Text(label,
                  style: TextStyle(color: color, fontWeight: FontWeight.w600)),
            ),
            if (state == VoiceState.disconnected && onReconnect != null) ...[
              const SizedBox(width: 12),
              TextButton(onPressed: onReconnect, child: const Text('Kết nối lại')),
            ],
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: 6),
          Text(error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
        ],
      ],
    );
  }
}

class _TranscriptView extends StatefulWidget {
  const _TranscriptView({required this.turns});
  final List<Turn> turns;

  @override
  State<_TranscriptView> createState() => _TranscriptViewState();
}

class _TranscriptViewState extends State<_TranscriptView> {
  final ScrollController _scroll = ScrollController();

  @override
  void didUpdateWidget(_TranscriptView old) {
    super.didUpdateWidget(old);
    // Keep the newest turn in view as the conversation grows.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.turns.isEmpty) {
      return const Center(
        child: Text('Chạm nút bên dưới để bắt đầu nói chuyện.',
            style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.builder(
      controller: _scroll,
      itemCount: widget.turns.length,
      itemBuilder: (context, i) {
        final turn = widget.turns[i];
        return Column(
          children: [
            if (turn.inText.isNotEmpty)
              _bubble('Bé', turn.inText, Colors.indigo.shade50),
            if (turn.outText.isNotEmpty)
              _bubble('Bạn nhỏ', turn.outText, Colors.green.shade50),
          ],
        );
      },
    );
  }

  Widget _bubble(String who, String text, Color bg) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(who, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 4),
          Text(text, style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
  }
}

class _TalkButton extends StatefulWidget {
  const _TalkButton({required this.controller});
  final VoiceController controller;

  @override
  State<_TalkButton> createState() => _TalkButtonState();
}

class _TalkButtonState extends State<_TalkButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    // A gentle "tap me" breathing pulse while the button is idle-and-ready.
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _onTap() {
    HapticFeedback.lightImpact(); // a satisfying confirmation tap (iOS)
    widget.controller.toggleMic();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final micOpen = c.micOpen;
    // Enabled only once the backend is ready — locked during cold-start
    // (connecting) and when disconnected, so the child can't trigger broken taps.
    final ready = switch (c.state) {
      VoiceState.idle || VoiceState.listening || VoiceState.speaking => true,
      VoiceState.connecting || VoiceState.disconnected => false,
    };
    final color = micOpen ? Colors.red : Colors.indigo;
    final label = !ready
        ? (c.state == VoiceState.connecting ? 'Đợi một chút…' : 'Chưa sẵn sàng')
        : (micOpen ? 'Đang nghe… (chạm để dừng)' : 'Chạm để nói');
    // Pulse only when idle-and-ready; press scales down; otherwise steady.
    final idleReady = ready && !micOpen;

    return GestureDetector(
      onTap: ready ? _onTap : null,
      onTapDown: ready ? (_) => setState(() => _pressed = true) : null,
      onTapUp: ready ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final pulse = idleReady ? 1.0 + _pulse.value * 0.025 : 1.0;
          final scale = _pressed ? 0.96 : pulse;
          return Transform.scale(scale: scale, child: child);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          height: context.isTablet ? 120 : 96,
          decoration: BoxDecoration(
            color: ready ? color : Colors.grey,
            borderRadius: BorderRadius.circular(48),
            boxShadow: [
              BoxShadow(
                color: (ready ? color : Colors.grey)
                    .withValues(alpha: micOpen ? 0.6 : 0.4),
                blurRadius: micOpen ? 28 : 12,
                spreadRadius: micOpen ? 2 : 0,
              ),
            ],
          ),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(micOpen ? Icons.mic : Icons.mic_none,
                    color: Colors.white, size: context.isTablet ? 40 : 34),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
