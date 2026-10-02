import 'package:flutter/material.dart';

import '../theme.dart';

class CreateScreen extends StatelessWidget {
  const CreateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const tools = [
      (Icons.brush_outlined, 'Pixel editor', 'Draw frame-by-frame animations'),
      (Icons.text_fields, 'Scrolling text', 'Messages, fonts and colours'),
      (Icons.schedule, 'Clock', 'Time, date and countdowns'),
      (Icons.gif_box_outlined, 'Import GIF', 'Crop and fit any GIF or image'),
    ];
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          const Text('Create',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          for (final (icon, title, subtitle) in tools)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                  leading: Icon(icon, color: GlyphColors.primary),
                  title: Text(title),
                  subtitle: Text(subtitle),
                  trailing: const Text('Soon',
                      style: TextStyle(color: GlyphColors.textMuted, fontSize: 12)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
