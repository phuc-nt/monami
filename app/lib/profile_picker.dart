// First screen: the child taps who they are. Two big, friendly cards (name + a
// tinted robot face). Tapping opens the voice screen for that child, which passes
// the profile id to the backend so the right profile + memory is loaded.

import 'package:flutter/material.dart';

import 'robot_face.dart';

/// A selectable child. `id` must match the backend profile ids (vy, phong).
class ChildOption {
  const ChildOption({required this.id, required this.name, required this.color});
  final String id;
  final String name;
  final Color color;
}

const List<ChildOption> kChildren = [
  ChildOption(id: 'vy', name: 'Vy', color: Color(0xFFE8A0D8)), // pink-ish
  ChildOption(id: 'phong', name: 'Phong', color: Color(0xFF7CC4F6)), // blue-ish
];

class ProfilePicker extends StatelessWidget {
  const ProfilePicker({super.key, required this.onPick});

  /// Called with the chosen child's profile id.
  final void Function(ChildOption child) onPick;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1016),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 32),
            const Text(
              'Ai đang chơi nào?',
              style: TextStyle(
                  color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('Chạm vào tên của con',
                style: TextStyle(color: Colors.white70, fontSize: 16)),
            Expanded(
              child: Center(
                child: Wrap(
                  spacing: 24,
                  runSpacing: 24,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final child in kChildren)
                      _ChildCard(child: child, onTap: () => onPick(child)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChildCard extends StatelessWidget {
  const _ChildCard({required this.child, required this.onTap});
  final ChildOption child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: child.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: child.color.withValues(alpha: 0.5), width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A happy tinted robot face as the avatar.
            SizedBox(
              height: 130,
              child: RobotFace(
                expression: RobotExpression.happy,
                litColor: child.color,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              child.name,
              style: TextStyle(
                  color: child.color,
                  fontSize: 24,
                  fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
