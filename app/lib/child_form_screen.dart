// Create / edit a child profile, Sticker-Scene styled. One screen for both:
// editing when an existing [Child] is passed, creating otherwise. Fields: name
// (required, <=20), gender (required boy/girl — never neutral), age, interests.
//
// On save it calls ChildService.createChild/updateChild and pops `true` so the
// caller can refetch. A 409 (soft cap) or other error surfaces inline.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'child_model.dart';
import 'child_service.dart';
import 'interests_chips.dart';
import 'scene/flat_art_kit.dart';
import 'scene/scene_spec.dart';
import 'scene/scene_widgets.dart';
import 'scene/scene_worlds.dart';

class ChildFormScreen extends StatefulWidget {
  ChildFormScreen({super.key, required this.service, this.existing, SceneSpec? spec})
      : spec = spec ?? specForId('night');

  final ChildService service;

  /// Non-null = edit mode (prefill + PATCH); null = create mode (POST).
  final Child? existing;

  /// The world to render the form in (defaults to night when opened from a
  /// context without a current world, e.g. the management screen).
  final SceneSpec spec;

  @override
  State<ChildFormScreen> createState() => _ChildFormScreenState();
}

class _ChildFormScreenState extends State<ChildFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  // Gender is required: null until picked (neutral is never a form choice).
  late ChildGender? _gender = (widget.existing?.gender == ChildGender.boy ||
          widget.existing?.gender == ChildGender.girl)
      ? widget.existing!.gender
      : null;
  late int _age = widget.existing?.age ?? 5;
  late final List<String> _interests = [...?widget.existing?.interests];

  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return; // synchronous re-entry guard (5-year-old double-tap)
    if (!_formKey.currentState!.validate()) return;
    if (_gender == null) {
      setState(() => _error = 'Hãy chọn bạn trai hoặc bạn gái');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final draft = Child(
      id: widget.existing?.id ?? '',
      name: _name.text.trim(),
      gender: _gender!,
      age: _age,
      interests: _interests,
    );
    try {
      if (_isEdit) {
        await widget.service.updateChild(draft.id, draft.toProfileJson());
      } else {
        await widget.service.createChild(draft);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ChildServiceException catch (e) {
      setState(() {
        _saving = false;
        _error = e.statusCode == 409
            ? 'Đã đủ 5 bé rồi — xóa bớt một bé để thêm bé mới.'
            : 'Lưu không được, thử lại nhé.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.spec;
    final headInk = s.headingInk;
    return Scaffold(
      body: SceneBackdrop(
        spec: s,
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_rounded, color: headInk),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  FaBlock(
                    color: FlatArt.surface,
                    radius: 14,
                    borderWidth: 2,
                    shadowOffset: const Offset(0, 3),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    child: Text(_isEdit ? 'Sửa thông tin bé' : 'Bé mới',
                        style: faFont(22, w: FontWeight.w800)),
                  ),
                ]),
                const SizedBox(height: 20),
                _label('Tên bé', headInk),
                _NameField(controller: _name),
                const SizedBox(height: 20),
                _label('Bé là', headInk),
                Row(children: [
                  _gTile(ChildGender.girl, 'Bạn gái', Icons.face_3_rounded),
                  const SizedBox(width: 12),
                  _gTile(ChildGender.boy, 'Bạn trai', Icons.face_6_rounded),
                ]),
                const SizedBox(height: 20),
                _label('Tuổi: $_age', headInk),
                SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: s.talkColor,
                    thumbColor: FlatArt.ink,
                    inactiveTrackColor: s.talkColor.withValues(alpha: 0.3),
                    trackHeight: 7,
                  ),
                  child: Slider(
                    value: _age.toDouble(),
                    min: 1,
                    max: 12,
                    divisions: 11,
                    label: '$_age',
                    onChanged: (v) => setState(() => _age = v.round()),
                  ),
                ),
                const SizedBox(height: 8),
                _label('Bé thích', headInk),
                FaBlock(
                  color: FlatArt.surface,
                  radius: 16,
                  shadow: false,
                  padding: const EdgeInsets.all(12),
                  child: InterestsChips(
                    selected: _interests,
                    onChanged: (list) => _interests
                      ..clear()
                      ..addAll(list),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!,
                      style: faFont(15,
                          w: FontWeight.w700, c: FlatArt.magenta)),
                ],
                const SizedBox(height: 28),
                FaPressable(
                  color: s.ctaColor,
                  radius: 22,
                  borderWidth: 3,
                  shadowOffset: const Offset(0, 6),
                  onTap: _saving
                      ? null
                      : () {
                          HapticFeedback.mediumImpact();
                          _save();
                        },
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Center(
                    child: _saving
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: FlatArt.ink))
                        : Text(_isEdit ? 'Lưu' : 'Thêm bé',
                            style: faFont(20, w: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String t, Color ink) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Text(t, style: faFont(16, w: FontWeight.w800, c: ink)),
      );

  Widget _gTile(ChildGender g, String label, IconData icon) {
    final on = _gender == g;
    final tint = paletteFor(g);
    return Expanded(
      child: FaPressable(
        color: on ? tint : FlatArt.surface,
        radius: 16,
        borderWidth: 2.5,
        onTap: () => setState(() {
          _gender = g;
          _error = null;
        }),
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(children: [
          Icon(icon, color: FlatArt.ink, size: 30),
          const SizedBox(height: 6),
          Text(label, style: faFont(14, w: FontWeight.w800)),
        ]),
      ),
    );
  }
}

/// The name field as a flat-art block with inline required validation (≤20).
class _NameField extends StatelessWidget {
  const _NameField({required this.controller});
  final TextEditingController controller;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: FlatArt.surface,
        borderRadius: BorderRadius.circular(16),
        border: inkBorder(2.5),
      ),
      child: TextFormField(
        controller: controller,
        maxLength: 20,
        textCapitalization: TextCapitalization.words,
        style: faFont(18),
        decoration: InputDecoration(
          hintText: 'Ví dụ: Vy',
          hintStyle: faFont(18, w: FontWeight.w500, c: FlatArt.inkSoft),
          border: InputBorder.none,
          counterText: '',
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
        validator: (v) =>
            (v == null || v.trim().isEmpty) ? 'Hãy nhập tên bé' : null,
      ),
    );
  }
}
