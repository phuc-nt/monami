// First screen: pick which child is playing, as a Sticker-Scene world. Backed by
// ChildService — children come from the backend (scoped to this device). Each
// child stands as a robot character on the ground; a gear on each card opens
// parent-facing management; a "+ Thêm bé" character adds one (up to 5); a "Khách"
// entry starts a no-profile guest session. A grown-up gear in the top bar opens
// the theme setting (world rotation).
//
// The three load states (loading / error / loaded) MUST stay distinct — a fetch
// error must never look like a real empty list, or a parent re-creates children.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'child_form_screen.dart';
import 'child_manage_screen.dart';
import 'child_model.dart';
import 'child_service.dart';
import 'responsive.dart';
import 'robot_face.dart';
import 'app_theme.dart';
import 'scene/flat_art_kit.dart';
import 'scene/scene_spec.dart';
import 'scene/scene_widgets.dart';

const int kMaxChildren = 5;

/// The three load states the picker must NEVER conflate: a fetch error must not
/// look like a real empty list, or a parent re-creates children.
enum _PickerState { loading, error, loaded }

class ProfilePicker extends StatefulWidget {
  const ProfilePicker({
    super.key,
    required this.service,
    required this.spec,
    required this.onPick,
    required this.onGuest,
    this.onOpenThemeSetting,
  });

  final ChildService service;

  /// The current world to render this picker in.
  final SceneSpec spec;

  /// Chosen child → open the voice screen.
  final void Function(Child child) onPick;

  /// "Khách" → start a guest session (no profile, no memory).
  final VoidCallback onGuest;

  /// Grown-up gear → open the theme (world rotation) setting. Null hides the gear.
  final VoidCallback? onOpenThemeSetting;

  @override
  State<ProfilePicker> createState() => _ProfilePickerState();
}

class _ProfilePickerState extends State<ProfilePicker> {
  _PickerState _state = _PickerState.loading;
  List<Child> _children = const [];
  // Guards against a fast double-tap (likely with a 5-year-old) pushing two
  // routes — which on the add form would create two children.
  bool _navigating = false;
  // Drives the "more to scroll →" hint on the character row.
  final ScrollController _charScroll = ScrollController();

  @override
  void dispose() {
    _charScroll.dispose();
    super.dispose();
  }

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
        builder: (_) =>
            ChildFormScreen(service: widget.service, spec: widget.spec),
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
      body: SceneBackdrop(
        spec: widget.spec,
        child: SafeArea(child: _body(context)),
      ),
    );
  }

  Widget _body(BuildContext context) {
    switch (_state) {
      case _PickerState.loading:
        return _Centered(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: FlatArt.ink),
              const SizedBox(height: 16),
              FaBlock(
                color: FlatArt.surface,
                radius: 16,
                shadowOffset: const Offset(0, 3),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('Đang tải…', style: faFont(16, w: FontWeight.w800)),
              ),
            ],
          ),
        );
      case _PickerState.error:
        return _Centered(
          child: FaBlock(
            color: FlatArt.surface,
            radius: 22,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_rounded, color: FlatArt.ink, size: 48),
                const SizedBox(height: 12),
                Text('Không tải được danh sách bé',
                    style: faFont(18, w: FontWeight.w800)),
                const SizedBox(height: 16),
                FaPressable(
                  color: FlatArt.yellow,
                  radius: 16,
                  onTap: _load,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.refresh_rounded, color: FlatArt.ink),
                    const SizedBox(width: 8),
                    Text('Thử lại', style: faFont(16, w: FontWeight.w800)),
                  ]),
                ),
              ],
            ),
          ),
        );
      case _PickerState.loaded:
        return _loaded(context);
    }
  }

  Widget _loaded(BuildContext context) {
    final isTablet = context.isTablet;
    final headInk = widget.spec.headingInk;
    final empty = _children.isEmpty;

    // Fixed header (title + gear) and fixed footer (guest button) so neither is
    // EVER clipped, regardless of how many children there are or the screen size
    // / orientation. The characters live in the flexible middle band, standing in
    // a horizontal row that scrolls sideways when there are more than fit — they
    // never wrap into a taller column, so the footer stays put.
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isTablet ? 32 : 16),
      child: Column(
        children: [
          _topBar(headInk),
          const SizedBox(height: 4),
          FaBlock(
            color: FlatArt.surface,
            radius: 20,
            shadowOffset: const Offset(0, 4),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text(
              empty ? 'Thêm bé để bắt đầu' : 'Ai đang chơi nào?',
              textAlign: TextAlign.center,
              style: faFont(isTablet ? 28 : 24, w: FontWeight.w800),
            ),
          ),
          // The character band takes all the space between header and footer; the
          // characters size themselves to THIS height (the real constraint), so
          // they always fit vertically and the footer can't be pushed off-screen.
          Expanded(child: _characterRow(isTablet)),
          SizedBox(height: isTablet ? 16 : 10),
          // Footer actions live OUTSIDE the horizontal scroll band, so they're
          // always reachable: "create profile" + guest, side by side.
          _footerActions(),
          SizedBox(height: isTablet ? 24 : 14),
        ],
      ),
    );
  }

  Widget _footerActions() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_children.length < kMaxChildren) ...[
            _PillButton(
              icon: Icons.add_rounded,
              label: 'Tạo hồ sơ mới',
              color: widget.spec.ctaColor,
              onTap: _addChild,
            ),
            const SizedBox(width: 12),
          ],
          _PillButton(
            icon: Icons.bolt_rounded,
            label: 'Khách',
            color: FlatArt.surface,
            onTap: widget.onGuest,
          ),
        ],
      );

  /// A horizontally-scrolling row of standing characters. Each is sized from the
  /// available band HEIGHT (so it always fits vertically); the row centers when
  /// the characters fit and scrolls sideways when they don't — same on a tall
  /// phone or a wide iPad. A fade + chevron on the right edge signals "more to
  /// scroll" and disappears once scrolled to the end.
  Widget _characterRow(bool isTablet) {
    return LayoutBuilder(builder: (context, c) {
      final bandH = c.maxHeight;
      final charH = bandH.clamp(0.0, isTablet ? 420.0 : 320.0);
      final faceW = (charH / 1.9) * (32 / 20);
      final charW = faceW.clamp(92.0, isTablet ? 220.0 : 150.0);
      final gap = isTablet ? 20.0 : 12.0;

      final row = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < _children.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            _ChildCharacter(
              child: _children[i],
              width: charW,
              onTap: () => widget.onPick(_children[i]),
              onManage: () => _manage(_children[i]),
            ),
          ],
        ],
      );

      return Align(
        alignment: Alignment.bottomCenter,
        child: _ScrollHint(
          child: SingleChildScrollView(
            controller: _charScroll,
            scrollDirection: Axis.horizontal,
            // ConstrainedBox + centered Row centers when the content is narrower
            // than the viewport, and scrolls when it's wider — one widget, both.
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: c.maxWidth),
              child: row,
            ),
          ),
        ),
      );
    });
  }

  Widget _topBar(Color headInk) => Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (widget.onOpenThemeSetting != null)
            IconButton(
              // A deliberate, non-kid gesture: the gear is for the grown-up.
              icon: Icon(Icons.settings_rounded, color: headInk),
              tooltip: 'Cài đặt',
              onPressed: () {
                HapticFeedback.lightImpact();
                widget.onOpenThemeSetting!();
              },
            ),
        ],
      );
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Center(child: child);
}

/// One child as a standing character: a name plaque, a tinted body with the LED
/// face, and legs. The whole thing presses on tap; a small gear (grown-up) sits
/// above for management.
class _ChildCharacter extends StatefulWidget {
  const _ChildCharacter({
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
  State<_ChildCharacter> createState() => _ChildCharacterState();
}

class _ChildCharacterState extends State<_ChildCharacter> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    final tint = paletteFor(child.gender);
    final faceVariant = faceVariantFor(child.gender);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Manage gear (grown-up) above the character.
        SizedBox(
          height: 32,
          child: IconButton(
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.settings_rounded,
                color: FlatArt.inkSoft, size: 20),
            tooltip: 'Quản lý',
            onPressed: widget.onManage,
          ),
        ),
        GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            widget.onTap();
          },
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedScale(
            scale: _pressed ? 0.95 : 1.0,
            duration: const Duration(milliseconds: 120),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FaBlock(
                  color: tint,
                  radius: 14,
                  borderWidth: 2,
                  shadowOffset: const Offset(0, 3),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  child: Text(child.name,
                      style: faFont(18, w: FontWeight.w800)),
                ),
                const SizedBox(height: 8),
                FaBlock(
                  color: tint,
                  radius: 22,
                  borderWidth: 2.5,
                  shadow: false,
                  padding: const EdgeInsets.all(8),
                  child: FaBlock(
                    color: FlatArt.screen,
                    radius: 12,
                    borderWidth: 2,
                    shadow: false,
                    padding: const EdgeInsets.all(6),
                    width: widget.width,
                    child: RobotFace(
                      expression: RobotExpression.happy,
                      variant: faceVariant,
                      litColor: Colors.white,
                      screenColor: FlatArt.screen,
                      bloom: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _leg(),
                  const SizedBox(width: 14),
                  _leg(),
                ]),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _leg() => Container(
        width: 10,
        height: 16,
        decoration: const BoxDecoration(
          color: FlatArt.ink,
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(5)),
        ),
      );
}

/// A compact flat-art pill button for the footer actions (create profile / guest).
class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FaPressable(
      color: color,
      radius: 18,
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: FlatArt.ink, size: 20),
        const SizedBox(width: 6),
        Text(label, style: faFont(15, w: FontWeight.w800)),
      ]),
    );
  }
}

/// Wraps a horizontal scrollable and overlays a right-edge fade + chevron when
/// there's more content to scroll to. The hint disappears once scrolled to the
/// end, and never shows when everything already fits — so the user always knows
/// whether more profiles are off-screen without any layout guesswork.
class _ScrollHint extends StatefulWidget {
  const _ScrollHint({required this.child});
  final Widget child;
  @override
  State<_ScrollHint> createState() => _ScrollHintState();
}

class _ScrollHintState extends State<_ScrollHint> {
  bool _showRight = false;

  bool _update(ScrollMetrics m) {
    final show = m.hasContentDimensions && m.extentAfter > 1.0;
    if (show != _showRight) {
      // Defer the setState out of the layout/scroll-notification phase.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _showRight = show);
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) => _update(n.metrics),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) => _update(n.metrics),
        child: Stack(
          children: [
            widget.child,
            // Right-edge fade + chevron — only when more is scrollable.
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _showRight ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Container(
                    width: 56,
                    alignment: Alignment.centerRight,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          FlatArt.ink.withValues(alpha: 0),
                          FlatArt.ink.withValues(alpha: 0.16),
                        ],
                      ),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(Icons.chevron_right_rounded,
                          color: FlatArt.ink, size: 32),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
