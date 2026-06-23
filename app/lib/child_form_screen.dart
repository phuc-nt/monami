// Create / edit a child profile. One screen for both: editing when an existing
// [Child] is passed, creating otherwise. Fields: name (required, <=20),
// gender (required boy/girl — never neutral), age, interests (chips + free-add).
//
// On save it calls ChildService.createChild/updateChild and pops `true` so the
// caller can refetch. A 409 (soft cap) or other error surfaces inline.

import 'package:flutter/material.dart';

import 'child_model.dart';
import 'child_service.dart';
import 'interests_chips.dart';

class ChildFormScreen extends StatefulWidget {
  const ChildFormScreen({super.key, required this.service, this.existing});

  final ChildService service;

  /// Non-null = edit mode (prefill + PATCH); null = create mode (POST).
  final Child? existing;

  @override
  State<ChildFormScreen> createState() => _ChildFormScreenState();
}

class _ChildFormScreenState extends State<ChildFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  // Gender is required: null until picked (neutral is never a form choice).
  late ChildGender? _gender =
      (widget.existing?.gender == ChildGender.boy ||
              widget.existing?.gender == ChildGender.girl)
          ? widget.existing!.gender
          : null;
  late int _age = widget.existing?.age ?? 5;
  late List<String> _interests = [...?widget.existing?.interests];

  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
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
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Sửa thông tin bé' : 'Thêm bé')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextFormField(
                controller: _name,
                maxLength: 20,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Tên bé',
                  hintText: 'Ví dụ: Vy',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Hãy nhập tên bé' : null,
              ),
              const SizedBox(height: 16),
              const Text('Bé là'),
              const SizedBox(height: 8),
              _GenderToggle(
                value: _gender,
                onChanged: (g) => setState(() {
                  _gender = g;
                  _error = null;
                }),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Text('Tuổi'),
                  Expanded(
                    child: Slider(
                      value: _age.toDouble(),
                      min: 1,
                      max: 12,
                      divisions: 11,
                      label: '$_age',
                      onChanged: (v) => setState(() => _age = v.round()),
                    ),
                  ),
                  Text('$_age', style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 12),
              const Text('Bé thích'),
              const SizedBox(height: 8),
              InterestsChips(
                selected: _interests,
                onChanged: (list) => _interests = list,
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_isEdit ? 'Lưu' : 'Thêm bé'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A two-option boy/girl toggle. Required — there is no neutral choice (neutral
/// is display-only for guests, never a stored profile).
class _GenderToggle extends StatelessWidget {
  const _GenderToggle({required this.value, required this.onChanged});
  final ChildGender? value;
  final ValueChanged<ChildGender> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ChildGender>(
      segments: const [
        ButtonSegment(
          value: ChildGender.girl,
          label: Text('Bạn gái'),
          icon: Icon(Icons.face_3),
        ),
        ButtonSegment(
          value: ChildGender.boy,
          label: Text('Bạn trai'),
          icon: Icon(Icons.face_6),
        ),
      ],
      selected: value == null ? <ChildGender>{} : {value!},
      emptySelectionAllowed: true,
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}
