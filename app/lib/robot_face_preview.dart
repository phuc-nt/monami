// Dev preview for the robot face (Phase 1). Run standalone, without the voice
// app, to eyeball every expression:
//
//   flutter run -d macos -t lib/robot_face_preview.dart
//
// Not part of the shipped app — main.dart wires the face to voice state in Phase 2.

import 'package:flutter/material.dart';

import 'robot_face.dart';

void main() => runApp(const RobotFacePreviewApp());

class RobotFacePreviewApp extends StatelessWidget {
  const RobotFacePreviewApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'robot face preview',
      theme: ThemeData.dark(useMaterial3: true),
      home: const _PreviewScreen(),
    );
  }
}

class _PreviewScreen extends StatefulWidget {
  const _PreviewScreen();
  @override
  State<_PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<_PreviewScreen> {
  RobotExpression _expr = RobotExpression.calm;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('robot face — ${_expr.name}')),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: RobotFace(expression: _expr),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: RobotExpression.values.map((e) {
                final selected = e == _expr;
                return ChoiceChip(
                  label: Text(e.name),
                  selected: selected,
                  onSelected: (_) => setState(() => _expr = e),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
