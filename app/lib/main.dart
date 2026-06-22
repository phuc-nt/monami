// Minimal push-to-talk voice client (Phase 2). Hold the button to talk; release
// to hear the companion reply. No character/polish yet — just enough to talk,
// listen, and see the transcripts (dev visibility). Replaces the audio spike.

import 'package:flutter/material.dart';

import 'voice_controller.dart';

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
      appBar: AppBar(title: const Text('Người bạn nhỏ')),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StatusBanner(
                  state: _controller.state,
                  error: _controller.error,
                  onReconnect: _controller.reconnect,
                ),
                const SizedBox(height: 24),
                Expanded(child: _TranscriptView(turns: _controller.turns)),
                const SizedBox(height: 24),
                _TalkButton(controller: _controller),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.state, this.error, this.onReconnect});
  final VoiceState state;
  final String? error;
  final VoidCallback? onReconnect;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      VoiceState.disconnected => ('Mất kết nối', Colors.grey),
      VoiceState.idle => ('Sẵn sàng — chạm để nói', Colors.green),
      VoiceState.listening => ('Đang nghe bé…', Colors.red),
      VoiceState.speaking => ('Đang trả lời…', Colors.blue),
    };
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.circle, size: 12, color: color),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
              if (state == VoiceState.disconnected && onReconnect != null) ...[
                const SizedBox(width: 12),
                TextButton(onPressed: onReconnect, child: const Text('Kết nối lại')),
              ],
            ],
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
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
