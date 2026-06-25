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
    return LayoutBuilder(builder: (context, constraints) {
      final contentMax = constraints.maxWidth.clamp(0.0, 760.0);
      // Character width scales down as more children share the row.
      final count = _children.length + 1; // + the add character
      final charW = (contentMax / count - 16).clamp(96.0, 168.0);

      return SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentMax),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: isTablet ? 32 : 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _topBar(headInk),
                    const SizedBox(height: 8),
                    FaBlock(
                      color: FlatArt.surface,
                      radius: 20,
                      shadowOffset: const Offset(0, 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      child: Text(
                        empty ? 'Thêm bé để bắt đầu' : 'Ai đang chơi nào?',
                        textAlign: TextAlign.center,
                        style: faFont(isTablet ? 28 : 24, w: FontWeight.w800),
                      ),
                    ),
                    SizedBox(height: isTablet ? 40 : 24),
                    // Characters stand on the ground, side by side (wraps if many).
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.end,
                      spacing: 12,
                      runSpacing: 16,
                      children: [
                        for (final child in _children)
                          _ChildCharacter(
                            child: child,
                            width: charW,
                            onTap: () => widget.onPick(child),
                            onManage: () => _manage(child),
                          ),
                        if (_children.length < kMaxChildren)
                          _AddCharacter(width: charW, onTap: _addChild),
                      ],
                    ),
                    SizedBox(height: isTablet ? 32 : 20),
                    _GuestButton(onTap: widget.onGuest),
                    SizedBox(height: isTablet ? 32 : 20),
                  ],
                ),
              ),
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

/// A prominent "Khách (chơi nhanh)" pill — a clear call-to-action so a parent can
/// jump into a no-setup session at a glance.
class _GuestButton extends StatelessWidget {
  const _GuestButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FaPressable(
      color: FlatArt.surface,
      radius: 22,
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.bolt_rounded, color: FlatArt.ink),
        const SizedBox(width: 8),
        Text('Khách (chơi nhanh)', style: faFont(16, w: FontWeight.w800)),
      ]),
    );
  }
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

/// The "+ Thêm bé" character, shown until the soft cap of 5 is reached.
class _AddCharacter extends StatelessWidget {
  const _AddCharacter({required this.width, required this.onTap});
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 32), // align with character bodies
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaBlock(
              color: FlatArt.surface,
              radius: 14,
              borderWidth: 2,
              shadowOffset: const Offset(0, 3),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              child: Text('Thêm bé', style: faFont(16, w: FontWeight.w800)),
            ),
            const SizedBox(height: 8),
            FaBlock(
              color: FlatArt.surface,
              radius: 22,
              padding: const EdgeInsets.all(8),
              child: SizedBox(
                width: width,
                height: width * (20 / 32),
                child: const Center(
                  child: Icon(Icons.add_rounded, color: FlatArt.ink, size: 44),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
