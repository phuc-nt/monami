// A small chips editor for a child's interests: tap preset suggestions to
// toggle them, or type a custom one and add it. Returns the selected list via
// [onChanged]. Used by the create/edit child form (phase 3).

import 'package:flutter/material.dart';

/// Preset suggestions a parent can tap (bilingual, matching the companion's
/// tone). Free-add covers anything not listed.
const List<String> kInterestSuggestions = [
  'khủng long',
  'công chúa',
  'ô tô',
  'động vật',
  'bóng đá',
  'vẽ tranh',
  'âm nhạc',
  'kể chuyện',
];

class InterestsChips extends StatefulWidget {
  const InterestsChips({
    super.key,
    required this.selected,
    required this.onChanged,
    this.maxInterests = 10,
    this.maxLen = 30,
  });

  /// Currently selected interests (preset + custom).
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;
  final int maxInterests;
  final int maxLen;

  @override
  State<InterestsChips> createState() => _InterestsChipsState();
}

class _InterestsChipsState extends State<InterestsChips> {
  late final List<String> _selected = [...widget.selected];
  final _customCtrl = TextEditingController();

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  bool get _atCap => _selected.length >= widget.maxInterests;

  void _toggle(String value) {
    setState(() {
      if (_selected.contains(value)) {
        _selected.remove(value);
      } else if (!_atCap) {
        _selected.add(value);
      }
    });
    widget.onChanged([..._selected]); // hand over an owned copy, not our list
  }

  void _addCustom() {
    final v = _customCtrl.text.trim();
    if (v.isEmpty || v.length > widget.maxLen || _selected.contains(v) || _atCap) {
      return;
    }
    setState(() {
      _selected.add(v);
      _customCtrl.clear();
    });
    widget.onChanged([..._selected]); // hand over an owned copy, not our list
  }

  @override
  Widget build(BuildContext context) {
    // Show the presets plus any custom-added values not in the preset list.
    final all = <String>{...kInterestSuggestions, ..._selected}.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in all)
              FilterChip(
                label: Text(s),
                selected: _selected.contains(s),
                onSelected: (_) => _toggle(s),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _customCtrl,
                maxLength: widget.maxLen,
                decoration: const InputDecoration(
                  hintText: 'Thêm sở thích khác…',
                  counterText: '', // hide the per-field counter (noisy)
                  isDense: true,
                ),
                onSubmitted: (_) => _addCustom(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              onPressed: _atCap ? null : _addCustom,
              icon: const Icon(Icons.add),
              tooltip: 'Thêm',
            ),
          ],
        ),
        if (_atCap)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Tối đa ${widget.maxInterests} sở thích',
                style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    );
  }
}
