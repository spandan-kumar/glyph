import 'package:flutter/material.dart';

import '../../app/creations.dart';

// Placeholder until the feature lands.
class TextStudioScreen extends StatelessWidget {
  const TextStudioScreen({super.key, this.initial, this.mode = 'text', });

  final Creation? initial;

  /// 'text' | 'clock' | 'countdown'
  final String mode;

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: const Text('Text & clock')));
}
