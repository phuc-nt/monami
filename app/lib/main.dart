// Voice companion home: a cute LED robot face the child talks to. Tap the button
// to talk; the face reacts to the live voice state (listening / talking / happy /
// sleepy). The transcript chat is hidden by default behind a small dev toggle.

import 'package:flutter/material.dart';

import 'app_config.dart';
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

void main() {
  runApp(const MonamiApp());
}

class MonamiApp extends StatelessWidget {
  const MonamiApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'monami',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: Builder(
        builder: (context) => ProfilePicker(
          onPick: (child) {
            final nav = Navigator.of(context);
            // Guard a fast double-tap (likely with a 5-year-old): if we've
            // already pushed VoiceHome, ignore the extra tap so we don't open a
            // second session/socket/mic.
            if (nav.canPop()) return;
            nav.push(
              MaterialPageRoute(builder: (_) => VoiceHome(child: child)),
            );
          },
        ),
      ),
    );
  }
}

class VoiceHome extends StatefulWidget {
  const VoiceHome({super.key, required this.child});

  /// The selected child (drives the profile + theme color).
  final ChildOption child;

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
      profileId: widget.child.id,
      base: AppConfig.wsBase,
      token: AppConfig.token,
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
        backgroundColor: const Color(0xFF0B1016),
        appBar: AppBar(
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
            child: Text('Bạn của ${widget.child.name}'),
          ),
        ),
        body: SafeArea(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final pad = context.isTablet ? 40.0 : 24.0;
              return Padding(
                padding: EdgeInsets.all(pad),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The robot face is the hero (bigger cap on a tablet).
                    Expanded(
                      flex: _showTranscript ? 3 : 5,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                              maxWidth: context.isTablet ? 720 : 560),
                          child: RobotFace(
                            expression: _expressionFor(_controller),
                            litColor: widget.child.color,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _StatusLine(
                      state: _controller.state,
                      error: _controller.error,
                      onReconnect: _controller.reconnect,
                    ),
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
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
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

class _TalkButton extends StatelessWidget {
  const _TalkButton({required this.controller});
  final VoiceController controller;

  @override
  Widget build(BuildContext context) {
    final micOpen = controller.micOpen;
    // Enabled only once the backend is ready — locked during cold-start
    // (connecting) and when disconnected, so the child can't trigger broken taps.
    final ready = switch (controller.state) {
      VoiceState.idle || VoiceState.listening || VoiceState.speaking => true,
      VoiceState.connecting || VoiceState.disconnected => false,
    };
    final color = micOpen ? Colors.red : Colors.indigo;
    final label = !ready
        ? (controller.state == VoiceState.connecting ? 'Đợi một chút…' : 'Chưa sẵn sàng')
        : (micOpen ? 'Đang nghe… (chạm để dừng)' : 'Chạm để nói');
    return GestureDetector(
      onTap: ready ? () => controller.toggleMic() : null,
      child: Container(
        height: context.isTablet ? 120 : 96,
        decoration: BoxDecoration(
          color: ready ? color : Colors.grey,
          borderRadius: BorderRadius.circular(48),
          boxShadow: [
            BoxShadow(
              color: (ready ? color : Colors.grey).withValues(alpha: 0.4),
              blurRadius: micOpen ? 24 : 8,
            ),
          ],
        ),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(micOpen ? Icons.mic : Icons.mic_none,
                  color: Colors.white, size: 32),
              const SizedBox(width: 12),
              Text(
                label,
                style: const TextStyle(
                    color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
