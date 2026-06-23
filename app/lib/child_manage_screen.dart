// Manage one child (parent-facing): edit the profile, view/edit/clear the
// memory the companion keeps, or delete the child. Reached from a gear on the
// picker card (a deliberate, non-kid gesture). Pops `true` if anything changed
// so the picker refetches.

import 'package:flutter/material.dart';

import 'child_form_screen.dart';
import 'child_model.dart';
import 'child_service.dart';

class ChildManageScreen extends StatefulWidget {
  const ChildManageScreen({super.key, required this.service, required this.child});

  final ChildService service;
  final Child child;

  @override
  State<ChildManageScreen> createState() => _ChildManageScreenState();
}

class _ChildManageScreenState extends State<ChildManageScreen> {
  late Child _child = widget.child;
  bool _changed = false;
  bool _busy = false;
  bool _navigating = false; // guards a double-tap pushing two form screens
  String? _error;

  Future<void> _refresh() async {
    // After a profile/memory mutation, refetch this child so the screen matches
    // the server (the list endpoint is the source of truth).
    try {
      final list = await widget.service.listChildren();
      final fresh = list.where((c) => c.id == _child.id).firstOrNull;
      if (fresh != null && mounted) setState(() => _child = fresh);
    } on ChildServiceException {
      // Keep the last-known child; the next action will surface any real error.
    }
  }

  Future<void> _editProfile() async {
    if (_navigating) return;
    _navigating = true;
    try {
      final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) =>
            ChildFormScreen(service: widget.service, existing: _child),
      ));
      if (saved == true) {
        _changed = true;
        await _refresh();
      }
    } finally {
      _navigating = false;
    }
  }

  Future<void> _editMemory() async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _MemoryEditDialog(initial: _child.memorySummary),
    );
    if (text == null) return; // cancelled
    // An empty edit is NOT a silent clear — clearing goes through its own
    // confirm. Treat a blanked field as a no-op so memory can't be wiped here.
    if (text.trim().isEmpty) return;
    await _run(() async {
      await widget.service.setMemory(_child.id, text);
    });
  }

  Future<void> _clearMemory() async {
    final ok = await _confirm(
      title: 'Xóa trí nhớ?',
      body: 'Bé vẫn còn, chỉ xóa những gì bạn nhỏ đang nhớ về bé.',
      danger: 'Xóa trí nhớ',
    );
    if (!ok) return;
    await _run(() async {
      await widget.service.clearMemory(_child.id);
    });
  }

  Future<void> _deleteChild() async {
    final ok = await _confirm(
      title: 'Xóa bé ${_child.name}?',
      body: 'Xóa hẳn bé này cùng mọi điều bạn nhỏ nhớ về bé. Không thể hoàn tác.',
      danger: 'Xóa bé',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await widget.service.deleteChild(_child.id);
      if (mounted) Navigator.of(context).pop(true); // list must refetch
    } on ChildServiceException {
      setState(() {
        _busy = false;
        _error = 'Xóa không được, thử lại nhé.';
      });
    }
  }

  /// Run a memory mutation with busy + error handling, then refetch + mark dirty.
  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      _changed = true;
      await _refresh();
    } on ChildServiceException {
      _error = 'Thao tác không được, thử lại nhé.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(
      {required String title, required String body, required String danger}) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(danger),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final hasMemory = _child.memorySummary.isNotEmpty;
    return PopScope(
      // Intercept ALL pops (AppBar back, swipe-back, system back) so the
      // "changed" flag always rides back to the picker — else a swipe-back after
      // a memory edit wouldn't trigger a refetch.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_child.name),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _busy ? null : () => Navigator.of(context).pop(_changed),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Sửa thông tin bé'),
                subtitle: Text('${_child.name} · ${_child.age} tuổi'),
                onTap: _busy ? null : _editProfile,
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Bạn nhỏ đang nhớ về bé'),
                    const SizedBox(height: 8),
                    Text(
                      hasMemory ? _child.memorySummary : '(chưa nhớ gì)',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: _busy ? null : _editMemory,
                          icon: const Icon(Icons.edit_note),
                          label: const Text('Sửa'),
                        ),
                        TextButton.icon(
                          onPressed: (_busy || !hasMemory) ? null : _clearMemory,
                          icon: const Icon(Icons.cleaning_services),
                          label: const Text('Xóa trí nhớ'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(),
              ListTile(
                leading: Icon(Icons.delete_forever,
                    color: Theme.of(context).colorScheme.error),
                title: Text('Xóa bé',
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
                onTap: _busy ? null : _deleteChild,
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A simple dialog to edit the memory summary text.
class _MemoryEditDialog extends StatefulWidget {
  const _MemoryEditDialog({required this.initial});
  final String initial;
  @override
  State<_MemoryEditDialog> createState() => _MemoryEditDialogState();
}

class _MemoryEditDialogState extends State<_MemoryEditDialog> {
  late final _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sửa trí nhớ'),
      content: TextField(
        controller: _ctrl,
        maxLines: 5,
        maxLength: 4000,
        decoration: const InputDecoration(
          hintText: 'Những điều bạn nhỏ nhớ về bé…',
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
          child: const Text('Lưu'),
        ),
      ],
    );
  }
}
