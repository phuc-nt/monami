// Voice companion home: an LED robot character the child talks to, standing in
// an illustrated Sticker-Scene world with a comic speech bubble. Tap the button
// to talk; the face + bubble react to the live voice state (listening / talking /
// happy / sleepy). The transcript chat is hidden behind a dev long-press.

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_config.dart';
import 'app_theme.dart';
import 'child_model.dart';
import 'child_service.dart';
import 'device_identity.dart';
import 'learning_mode.dart';
import 'profile_picker.dart';
import 'responsive.dart';
import 'robot_face.dart';
import 'scene/flat_art_kit.dart';
import 'scene/scene_spec.dart';
import 'scene/scene_widgets.dart';
import 'scene/scene_worlds.dart';
import 'scene/theme_rotation.dart';
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
  // need the binding initialized before we resolve identity + theme.
  WidgetsFlutterBinding.ensureInitialized();
  final deviceId = await DeviceIdentity().ensure();
  final themeRotation = ThemeRotation();
  await themeRotation.load(); // load the persisted world before the first frame
  runApp(MonamiApp(deviceId: deviceId, themeRotation: themeRotation));
}

class MonamiApp extends StatefulWidget {
  const MonamiApp({
    super.key,
    required this.deviceId,
    required this.themeRotation,
  });

  /// This install's anonymous id; scopes children + memory on the backend.
  final String deviceId;

  /// The device-wide active world + its rotation policy.
  final ThemeRotation themeRotation;

  @override
  State<MonamiApp> createState() => _MonamiAppState();
}

class _MonamiAppState extends State<MonamiApp> {
  // One service for the app lifetime (its http client is closed on dispose),
  // instead of a fresh one per build.
  late final ChildService _service = ChildService(
    restBase: AppConfig.restBase,
    deviceId: widget.deviceId,
    token: AppConfig.token,
  );

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Monami',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: Builder(
        builder: (context) => AnimatedBuilder(
          // Rebuild the picker when the world rotates (after a long session) so
          // the new world shows on return.
          animation: widget.themeRotation,
          builder: (context, _) => ProfilePicker(
            service: _service,
            spec: widget.themeRotation.spec,
            onOpenThemeSetting: () => _openThemeSetting(context),
            onPick: (child) {
              final nav = Navigator.of(context);
              // Guard a fast double-tap (likely with a 5-year-old): if we've
              // already pushed VoiceHome, ignore the extra tap so we don't open a
              // second session/socket/mic.
              if (nav.canPop()) return;
              nav.push(MaterialPageRoute(
                builder: (_) => VoiceHome(
                  child: child,
                  deviceId: widget.deviceId,
                  spec: widget.themeRotation.spec,
                  themeRotation: widget.themeRotation,
                ),
              ));
            },
            onGuest: () {
              final nav = Navigator.of(context);
              if (nav.canPop()) return;
              // Guest: no deviceId, the "guest" profile → backend persists nothing.
              nav.push(MaterialPageRoute(
                builder: (_) => VoiceHome.guest(
                  spec: widget.themeRotation.spec,
                  themeRotation: widget.themeRotation,
                ),
              ));
            },
          ),
        ),
      ),
    );
  }

  void _openThemeSetting(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: FlatArt.cream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ThemeSettingSheet(themeRotation: widget.themeRotation),
    );
  }
}

/// Grown-up theme setting: choose Fixed (lock one world) or Random per session.
class _ThemeSettingSheet extends StatelessWidget {
  const _ThemeSettingSheet({required this.themeRotation});
  final ThemeRotation themeRotation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeRotation,
      builder: (context, _) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Khung cảnh', style: faFont(20, w: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Chọn cố định một khung cảnh, hoặc đổi mới mỗi lần chơi.',
                  style: faFont(14, w: FontWeight.w500, c: FlatArt.inkSoft)),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: FlatArt.magenta,
                title: Text('Đổi mỗi lần chơi',
                    style: faFont(16, w: FontWeight.w700)),
                subtitle: Text('Sau mỗi buổi chơi dài, khung cảnh sẽ đổi mới.',
                    style: faFont(13, w: FontWeight.w500, c: FlatArt.inkSoft)),
                value: themeRotation.randomPerSession,
                onChanged: (on) =>
                    on ? themeRotation.setRandom() : themeRotation.setFixed(themeRotation.currentWorldId),
              ),
              const SizedBox(height: 8),
              Text('Hoặc chọn một khung cảnh cố định:',
                  style: faFont(14, w: FontWeight.w700)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final s in allScenes)
                    _WorldChip(
                      spec: s,
                      selected: !themeRotation.randomPerSession &&
                          themeRotation.currentWorldId == s.id,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        themeRotation.setFixed(s.id);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorldChip extends StatelessWidget {
  const _WorldChip(
      {required this.spec, required this.selected, required this.onTap});
  final SceneSpec spec;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return FaPressable(
      color: selected ? FlatArt.ink : FlatArt.surface,
      radius: 14,
      borderWidth: 2,
      shadowOffset: const Offset(0, 3),
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Text(spec.title,
          style: faFont(14,
              w: FontWeight.w800,
              c: selected ? Colors.white : FlatArt.ink)),
    );
  }
}

class VoiceHome extends StatefulWidget {
  const VoiceHome({
    super.key,
    required this.child,
    required this.spec,
    required this.themeRotation,
    this.deviceId = '',
  });

  /// Guest session: no child profile, no deviceId → backend persists nothing.
  const VoiceHome.guest({
    super.key,
    required this.spec,
    required this.themeRotation,
  })  : child = null,
        deviceId = '';

  /// The selected child (drives the profile + tint + face variant). Null = guest.
  final Child? child;

  /// This install's deviceId, scoping the child + memory on the backend. Empty
  /// for a guest session.
  final String deviceId;

  /// The world to render the voice screen in.
  final SceneSpec spec;

  /// The rotation service — told how long this session lasted on the way out.
  final ThemeRotation themeRotation;

  bool get isGuest => child == null;

  /// The backend profile id: the child's id, or "guest" for a guest session.
  String get profileId => child?.id ?? 'guest';

  /// Display name + tint + face variant, with neutral fallback for guest.
  String get displayName => child?.name ?? 'Khách';
  ChildGender get _gender => child?.gender ?? ChildGender.neutral;
  Color get tint => paletteFor(_gender);
  FaceVariant get faceVariant => faceVariantFor(_gender);

  @override
  State<VoiceHome> createState() => _VoiceHomeState();
}

class _VoiceHomeState extends State<VoiceHome> {
  late final VoiceController _controller;
  late final ConfettiController _confetti;
  bool _showTranscript = false; // dev-only chat view, hidden by default
  bool _lastHappyPulse = false; // tracks the pulse edge so confetti fires once
  // When the child entered this screen — used to measure session dwell so the
  // world can rotate after a long session.
  late final DateTime _enteredAt;

  @override
  void initState() {
    super.initState();
    _enteredAt = DateTime.now();
    _controller = VoiceController(
      profileId: widget.profileId,
      base: AppConfig.wsBase,
      token: AppConfig.token,
      deviceId: widget.deviceId,
    );
    _confetti = ConfettiController(duration: const Duration(milliseconds: 1200));
    _controller.addListener(_onState);
    _controller.connect();
  }

  void _onState() {
    // Fire the celebrate burst once, on the RISING edge of the happy pulse (a
    // turn just finished happily). The pulse stays true ~900ms and the controller
    // notifies for other reasons in that window (transcript deltas, state flips),
    // so edge-detect to avoid re-triggering the same burst.
    final pulse = _controller.happyPulse;
    if (pulse && !_lastHappyPulse) _confetti.play();
    _lastHappyPulse = pulse;
  }

  bool _leaving = false;

  @override
  void dispose() {
    _controller.removeListener(_onState);
    _controller.dispose();
    _confetti.dispose();
    super.dispose();
  }

  // Close the session (flush the WS) BEFORE leaving so the backend summarizes
  // this child's memory now, then tell the rotation service how long the session
  // lasted (so the world can change), then pop back to the picker.
  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    await _controller.shutdown();
    await widget.themeRotation.onSessionEnd(DateTime.now().difference(_enteredAt));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.spec;
    final headInk = s.headingInk;
    return PopScope(
      // Intercept the back gesture/arrow: run shutdown() first, then pop.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        body: SceneBackdrop(
          spec: s,
          child: Stack(
            children: [
              SafeArea(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    final pad = context.isTablet ? 40.0 : 20.0;
                    // Show the status line only when there's something a grown-up
                    // needs (cold-start, disconnected, error); the face + bubble
                    // carry idle/listening/speaking for the kid.
                    final showStatus =
                        _controller.state == VoiceState.connecting ||
                            _controller.state == VoiceState.disconnected ||
                            _controller.error != null;
                    return Padding(
                      padding: EdgeInsets.all(pad),
                      child: Column(
                        children: [
                          _topBar(context, headInk),
                          const Spacer(),
                          _bubble(s),
                          const SizedBox(height: 8),
                          StandingRobot(
                            expression: _expressionFor(_controller),
                            variant: widget.faceVariant,
                            bodyColor: widget.tint,
                            width: context.isTablet ? 360 : 290,
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
                              child: _TranscriptView(turns: _controller.turns),
                            ),
                          ] else
                            const Spacer(),
                          _ModeSelector(controller: _controller),
                          const SizedBox(height: 16),
                          _TalkButton(controller: _controller, color: s.talkColor),
                          const SizedBox(height: 8),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Align(
                alignment: Alignment.topCenter,
                child: ConfettiWidget(
                  confettiController: _confetti,
                  blastDirectionality: BlastDirectionality.explosive,
                  emissionFrequency: 0.06,
                  numberOfParticles: 16,
                  gravity: 0.25,
                  colors: const [
                    FlatArt.magenta,
                    FlatArt.cyan,
                    FlatArt.yellow,
                    FlatArt.mint,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context, Color headInk) => Row(children: [
        IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: headInk),
          onPressed: _leave,
        ),
        const Spacer(),
        // Long-press the name plaque to toggle the dev transcript — hidden from a
        // child (no visible button), reachable by the grown-up.
        GestureDetector(
          onLongPress: () => setState(() => _showTranscript = !_showTranscript),
          child: FaBlock(
            color: FlatArt.surface,
            radius: 14,
            borderWidth: 2,
            shadowOffset: const Offset(0, 3),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            child: Text('Bạn của ${widget.displayName}',
                style: faFont(16, w: FontWeight.w800)),
          ),
        ),
        const Spacer(),
        const SizedBox(width: 48), // balance the back button
      ]);

  Widget _bubble(SceneSpec s) {
    // Map the REAL voice state to the kid-facing bubble copy + color.
    final (label, color, ink) = switch (_controller.state) {
      VoiceState.connecting => ('Mình đang thức dậy…', FlatArt.yellow, FlatArt.ink),
      VoiceState.idle => ('Chạm để nói với mình nhé!', s.bubbleColor, s.bubbleInk),
      VoiceState.listening => ('Mình đang nghe nè…', FlatArt.magenta, FlatArt.ink),
      VoiceState.speaking => ('Để mình kể cho nghe…', FlatArt.cyan, FlatArt.ink),
      VoiceState.disconnected => ('Ơ, mất kết nối rồi', FlatArt.inkSoft, Colors.white),
    };
    return SpeechBubble(text: label, color: color, ink: ink);
  }
}

/// A horizontal row of mode chips: free chat (default) + the learning modes.
/// Tapping one switches the session's mode (which reconnects). Listens to the
/// controller so the active chip stays highlighted.
class _ModeSelector extends StatefulWidget {
  const _ModeSelector({required this.controller});
  final VoiceController controller;

  @override
  State<_ModeSelector> createState() => _ModeSelectorState();
}

class _ModeSelectorState extends State<_ModeSelector> {
  // Debounce rapid taps (a 5-year-old mashing) — instance-scoped, so it dies
  // with the widget (matches VoiceController._lastToggle's pattern).
  DateTime? _lastTap;
  static const _debounce = Duration(milliseconds: 700);

  void _pick(LearningMode m) {
    if (m == widget.controller.mode) return;
    final now = DateTime.now();
    if (_lastTap != null && now.difference(_lastTap!) < _debounce) return;
    _lastTap = now;
    widget.controller.setMode(m);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            children: [
              for (final m in LearningMode.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _ModeChip(
                    mode: m,
                    selected: widget.controller.mode == m,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _pick(m);
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.mode,
    required this.selected,
    required this.onTap,
  });
  final LearningMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? FlatArt.ink : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: inkBorder(2),
          boxShadow: hardShadow(offset: const Offset(0, 3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(mode.icon, size: 17, color: selected ? Colors.white : FlatArt.ink),
          const SizedBox(width: 6),
          Text(mode.label,
              style: faFont(13,
                  w: FontWeight.w700,
                  c: selected ? Colors.white : FlatArt.ink)),
        ]),
      ),
    );
  }
}

/// A slim status line under the robot: a short label + (on disconnect) a
/// reconnect button, plus any error text. Shown only for connecting/disconnected/
/// error (the face + bubble carry the rest).
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.state, this.error, this.onReconnect});
  final VoiceState state;
  final String? error;
  final VoidCallback? onReconnect;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      VoiceState.disconnected => ('Mất kết nối', FlatArt.inkSoft),
      VoiceState.connecting => ('Đang đánh thức bạn nhỏ…', FlatArt.ink),
      VoiceState.idle => ('Sẵn sàng — chạm để nói', FlatArt.ink),
      VoiceState.listening => ('Đang nghe bé…', FlatArt.magenta),
      VoiceState.speaking => ('Đang trả lời…', FlatArt.cyan),
    };
    return FaBlock(
      color: FlatArt.surface,
      radius: 14,
      shadowOffset: const Offset(0, 3),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.circle, size: 10, color: color),
              const SizedBox(width: 8),
              Flexible(
                child: Text(label, style: faFont(14, w: FontWeight.w700, c: color)),
              ),
              if (state == VoiceState.disconnected && onReconnect != null) ...[
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: onReconnect,
                  child: Text('Kết nối lại',
                      style: faFont(14, w: FontWeight.w800, c: FlatArt.cyan)),
                ),
              ],
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 6),
            Text(error!, style: faFont(12, w: FontWeight.w600, c: FlatArt.magenta)),
          ],
        ],
      ),
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
      return Center(
        child: Text('Chạm nút bên dưới để bắt đầu nói chuyện.',
            style: faFont(13, w: FontWeight.w500, c: FlatArt.inkSoft)),
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
              _bubble('Bé', turn.inText, FlatArt.cyan.withValues(alpha: 0.18)),
            if (turn.outText.isNotEmpty)
              _bubble('Bạn nhỏ', turn.outText,
                  FlatArt.magenta.withValues(alpha: 0.18)),
          ],
        );
      },
    );
  }

  Widget _bubble(String who, String text, Color bg) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(who, style: faFont(12, w: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(text, style: faFont(15, w: FontWeight.w500)),
        ],
      ),
    );
  }
}

/// The talk button: a big flat-art pill that presses down onto its shadow. Locked
/// during cold-start (connecting) and disconnected so the child can't trigger
/// broken taps; magenta while the mic is open.
class _TalkButton extends StatefulWidget {
  const _TalkButton({required this.controller, required this.color});
  final VoiceController controller;
  final Color color;

  @override
  State<_TalkButton> createState() => _TalkButtonState();
}

class _TalkButtonState extends State<_TalkButton> {
  bool _pressed = false;

  void _onTap() {
    HapticFeedback.mediumImpact();
    widget.controller.toggleMic();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final micOpen = c.micOpen;
    // Enabled only once the backend is ready — locked during cold-start
    // (connecting) and when disconnected.
    final ready = switch (c.state) {
      VoiceState.idle || VoiceState.listening || VoiceState.speaking => true,
      VoiceState.connecting || VoiceState.disconnected => false,
    };
    final color = !ready
        ? const Color(0xFFC9CFD8)
        : (micOpen ? FlatArt.magenta : widget.color);
    final label = !ready
        ? (c.state == VoiceState.connecting ? 'Đợi một chút…' : 'Chưa sẵn sàng')
        : (micOpen ? 'Chạm để dừng' : 'Chạm để nói');
    final h = context.isTablet ? 92.0 : 76.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: GestureDetector(
        onTap: ready ? _onTap : null,
        onTapDown: ready ? (_) => setState(() => _pressed = true) : null,
        onTapUp: ready ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          transform: Matrix4.translationValues(0, _pressed ? 6 : 0, 0),
          height: h,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(h / 2),
            border: inkBorder(3.5),
            boxShadow: _pressed ? null : hardShadow(offset: const Offset(0, 6)),
          ),
          child: Center(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(micOpen ? Icons.mic_rounded : Icons.mic_none_rounded,
                  color: FlatArt.ink, size: context.isTablet ? 36 : 30),
              const SizedBox(width: 10),
              Flexible(
                child: Text(label,
                    textAlign: TextAlign.center,
                    style: faFont(context.isTablet ? 22 : 20,
                        w: FontWeight.w800)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
