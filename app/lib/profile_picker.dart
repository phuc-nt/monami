// First screen: the child taps who they are. Two big, friendly cards (name + a
// tinted robot face). Tapping opens the voice screen for that child, which passes
// the profile id to the backend so the right profile + memory is loaded.

import 'package:flutter/material.dart';

import 'responsive.dart';
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
        child: LayoutBuilder(
            builder: (context, constraints) {
              final isTablet = context.isTablet;
              // Cards sit side-by-side on a wide screen (tablet/landscape), and
              // stack vertically on a narrow phone. Width is derived from the
              // available space so they never overflow.
              final wide = constraints.maxWidth >= 560;
              final cardW = wide
                  ? (constraints.maxWidth - 72) / 2
                  : constraints.maxWidth * 0.7;
              final cards = [
                for (final child in kChildren)
                  _ChildCard(
                    child: child,
                    width: cardW.clamp(160.0, 320.0),
                    onTap: () => onPick(child),
                  ),
              ];
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(height: isTablet ? 48 : 24),
                      Text(
                        'Ai đang chơi nào?',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: isTablet ? 40 : 28,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text('Chạm vào tên của con',
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: isTablet ? 22 : 16)),
                      SizedBox(height: isTablet ? 48 : 32),
                      if (wide)
                        Wrap(
                          spacing: 24,
                          runSpacing: 24,
                          alignment: WrapAlignment.center,
                          children: cards,
                        )
                      else
                        Column(
                          children: [
                            for (var i = 0; i < cards.length; i++) ...[
                              cards[i],
                              if (i < cards.length - 1)
                                const SizedBox(height: 24),
                            ],
                          ],
                        ),
                      SizedBox(height: isTablet ? 48 : 24),
                    ],
                  ),
                ),
              );
            },
        ),
      ),
    );
  }
}

class _ChildCard extends StatelessWidget {
  const _ChildCard({required this.child, required this.width, required this.onTap});
  final ChildOption child;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // The robot face keeps its 32:20 ratio; size it to the card width.
    final faceH = width * (20 / 32) * 0.85;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
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
              height: faceH,
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
                  fontSize: context.isTablet ? 32 : 24,
                  fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
