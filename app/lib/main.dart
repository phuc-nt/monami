// Voice companion home: a cute LED robot face the child talks to. Tap the button
// to talk; the face reacts to the live voice state (listening / talking / happy /
// sleepy). The transcript chat is hidden by default behind a small dev toggle.

import 'package:flutter/material.dart';

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
      home: const VoiceHome(),
    );
  }
}

class VoiceHome extends StatefulWidget {
  const VoiceHome({super.key});
  @override
  State<VoiceHome> createState() => _VoiceHomeState();
}

class _VoiceHomeState extends State<VoiceHome> {
  final VoiceController _controller = VoiceController();
  bool _showTranscript = false; // dev-only chat view, hidden by default

  @override
  void initState() {
    super.initState();
    _controller.connect();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1016),
      appBar: AppBar(
        title: const Text('Người bạn nhỏ'),
        actions: [
          // Dev toggle: show/hide the transcript chat.
          IconButton(
            tooltip: 'Hiện/ẩn transcript (dev)',
            icon: Icon(_showTranscript ? Icons.subtitles : Icons.subtitles_off),
            onPressed: () => setState(() => _showTranscript = !_showTranscript),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The robot face is the hero.
                Expanded(
                  flex: _showTranscript ? 3 : 5,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: RobotFace(expression: _expressionFor(_controller)),
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
    final connected = controller.state != VoiceState.disconnected;
    final color = micOpen ? Colors.red : Colors.indigo;
    return GestureDetector(
      onTap: connected ? () => controller.toggleMic() : null,
      child: Container(
        height: 96,
        decoration: BoxDecoration(
          color: connected ? color : Colors.grey,
          borderRadius: BorderRadius.circular(48),
          boxShadow: [
            BoxShadow(
              color: (connected ? color : Colors.grey).withValues(alpha: 0.4),
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
                micOpen ? 'Đang nghe… (chạm để dừng)' : 'Chạm để nói',
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
