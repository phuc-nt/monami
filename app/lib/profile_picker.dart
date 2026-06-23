// First screen: pick which child is playing. Backed by ChildService — the
// children come from the backend (scoped to this device), so a parent can add /
// edit / remove them. Big friendly cards (name + a tinted robot face); a gear on
// each card opens parent-facing management; a "+ Thêm bé" card adds one (up to
// 5); a "Khách" entry starts a no-profile guest session (wired in phase 5).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'child_form_screen.dart';
import 'child_manage_screen.dart';
import 'child_model.dart';
import 'child_service.dart';
import 'responsive.dart';
import 'robot_face.dart';

const int kMaxChildren = 5;

/// The three load states the picker must NEVER conflate (red-team 4b): a fetch
/// error must not look like a real empty list, or a parent re-creates children.
enum _PickerState { loading, error, loaded }

class ProfilePicker extends StatefulWidget {
  const ProfilePicker({
    super.key,
    required this.service,
    required this.onPick,
    required this.onGuest,
  });

  final ChildService service;

  /// Chosen child → open the voice screen.
  final void Function(Child child) onPick;

  /// "Khách" → start a guest session (no profile, no memory).
  final VoidCallback onGuest;

  @override
  State<ProfilePicker> createState() => _ProfilePickerState();
}

class _ProfilePickerState extends State<ProfilePicker> {
  _PickerState _state = _PickerState.loading;
  List<Child> _children = const [];
  // Guards against a fast double-tap (likely with a 5-year-old) pushing two
  // routes — which on the add form would create two children.
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _PickerState.loading);
    try {
      final list = await widget.service.listChildren();
      if (!mounted) return;
      setState(() {
        _children = list;
        _state = _PickerState.loaded; // a real (possibly empty) result
      });
    } on ChildServiceException {
      if (!mounted) return;
      setState(() => _state = _PickerState.error); // NOT empty — show retry
    }
  }

  Future<void> _addChild() async {
    if (_navigating) return;
    _navigating = true;
    try {
      final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => ChildFormScreen(service: widget.service),
      ));
      if (saved == true) _load();
    } finally {
      _navigating = false;
    }
  }

  Future<void> _manage(Child child) async {
    if (_navigating) return;
    _navigating = true;
    try {
      final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => ChildManageScreen(service: widget.service, child: child),
      ));
      if (changed == true) _load();
    } finally {
      _navigating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1016),
      body: SafeArea(child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    switch (_state) {
      case _PickerState.loading:
        return const _Centered(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Đang tải…', style: TextStyle(color: Colors.white70)),
            ],
          ),
        );
      case _PickerState.error:
        return _Centered(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, color: Colors.white54, size: 48),
              const SizedBox(height: 12),
              const Text('Không tải được danh sách bé',
                  style: TextStyle(color: Colors.white)),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Thử lại'),
              ),
            ],
          ),
        );
      case _PickerState.loaded:
        return _loaded(context);
    }
  }

  Widget _loaded(BuildContext context) {
    final isTablet = context.isTablet;
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 560;
      final cardW = (wide
              ? (constraints.maxWidth - 72) / 2
              : constraints.maxWidth * 0.7)
          .clamp(160.0, 320.0);

      final tiles = <Widget>[
        for (final child in _children)
          _ChildCard(
            child: child,
            width: cardW,
            onTap: () => widget.onPick(child),
            onManage: () => _manage(child),
          ),
        if (_children.length < kMaxChildren)
          _AddCard(width: cardW, onTap: _addChild),
      ];

      return SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(height: isTablet ? 48 : 24),
              Text(
                _children.isEmpty ? 'Thêm bé để bắt đầu' : 'Ai đang chơi nào?',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: isTablet ? 40 : 28,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _children.isEmpty
                    ? 'Tạo hồ sơ cho bé, hoặc chơi thử ở chế độ Khách'
                    : 'Chạm vào tên của con',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white70, fontSize: isTablet ? 22 : 16),
              ),
              SizedBox(height: isTablet ? 48 : 32),
              Wrap(
                spacing: 24,
                runSpacing: 24,
                alignment: WrapAlignment.center,
                children: tiles,
              ),
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: widget.onGuest,
                icon: const Icon(Icons.bolt, color: Colors.white70),
                label: const Text('Khách (chơi nhanh)',
                    style: TextStyle(color: Colors.white70)),
              ),
              SizedBox(height: isTablet ? 48 : 24),
            ],
          ),
        ),
      );
    });
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Center(child: child);
}

class _ChildCard extends StatefulWidget {
  const _ChildCard({
    required this.child,
    required this.width,
    required this.onTap,
    required this.onManage,
  });
  final Child child;
  final double width;
  final VoidCallback onTap;
  final VoidCallback onManage;

  @override
  State<_ChildCard> createState() => _ChildCardState();
}

class _ChildCardState extends State<_ChildCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    final color = paletteFor(child.gender);
    final faceH = widget.width * (20 / 32) * 0.85;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          width: widget.width,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: color.withValues(alpha: 0.5), width: 2),
            boxShadow: [
              BoxShadow(
                  color: color.withValues(alpha: 0.25),
                  blurRadius: 24,
                  spreadRadius: -4),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  // A deliberate, non-kid gesture: the gear is for the grown-up.
                  icon: const Icon(Icons.settings, color: Colors.white54),
                  tooltip: 'Quản lý',
                  onPressed: widget.onManage,
                ),
              ),
              SizedBox(
                height: faceH,
                child: RobotFace(
                  expression: RobotExpression.happy,
                  variant: faceVariantFor(child.gender),
                  litColor: color,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                child.name,
                style: TextStyle(
                    color: color,
                    fontSize: context.isTablet ? 32 : 24,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "+ Thêm bé" card, shown until the soft cap of 5 is reached.
class _AddCard extends StatelessWidget {
  const _AddCard({required this.width, required this.onTap});
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        width: width,
        height: width * 0.8,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white24, width: 2),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle_outline, color: Colors.white70, size: 48),
            SizedBox(height: 12),
            Text('Thêm bé', style: TextStyle(color: Colors.white70, fontSize: 20)),
          ],
        ),
      ),
    );
  }
}
