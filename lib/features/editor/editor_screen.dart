import 'package:flutter/material.dart';

import '../../app/creations.dart';

// Placeholder until the feature lands.
class EditorScreen extends StatelessWidget {
  const EditorScreen({super.key, this.initial, });

  final Creation? initial;

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: const Text('Pixel editor')));
}
