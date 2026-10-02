import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/theme.dart';
import '../../ui/widgets/led_matrix_view.dart';
import 'editor_model.dart';
import 'templates.dart';

/// "New drawing" picker: matrix size plus blank or example starts.
class EditorStartView extends StatefulWidget {
  const EditorStartView({super.key, this.deviceSize, required this.onStart});

  /// The connected matrix's size, offered first when known.
  final (int, int)? deviceSize;
  final ValueChanged<EditorModel> onStart;

  @override
  State<EditorStartView> createState() => _EditorStartViewState();
}

class _EditorStartViewState extends State<EditorStartView> {
  late (int, int) _size = widget.deviceSize ?? (16, 16);

  bool get _isCustom => _size != widget.deviceSize && !matrixSizes.contains(_size);

  Future<void> _custom() async {
    final w = TextEditingController(text: '${_size.$1}');
    final h = TextEditingController(text: '${_size.$2}');
    final result = await showDialog<(int, int)>(
      context: context,
      builder: (ctx) {
        Widget field(TextEditingController c, String label) => Expanded(
              child: TextField(
                controller: c,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(labelText: label),
              ),
            );
        return AlertDialog(
          title: const Text('Custom size'),
          content: Row(children: [
            field(w, 'Width'),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('×')),
            field(h, 'Height'),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final x = int.tryParse(w.text) ?? 0, y = int.tryParse(h.text) ?? 0;
                if (x < 1 || y < 1) return;
                Navigator.pop(ctx, (x.clamp(1, 128), y.clamp(1, 128)));
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
    w.dispose();
    h.dispose();
    if (result != null) setState(() => _size = result);
  }

  @override
  Widget build(BuildContext context) {
    final (w, h) = _size;
    final dev = widget.deviceSize;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        const Text('New drawing', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('Pick a size, then start blank or from an example.',
            style: TextStyle(color: GlyphColors.textMuted)),
        const SizedBox(height: 20),
        const _Label('SIZE'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (dev != null)
            ChoiceChip(
              avatar: const Icon(Icons.grid_view, size: 16),
              label: Text('My matrix · ${dev.$1}×${dev.$2}'),
              selected: _size == dev,
              onSelected: (_) => setState(() => _size = dev),
            ),
          for (final s in matrixSizes)
            if (s != dev)
              ChoiceChip(
                label: Text('${s.$1}×${s.$2}'),
                selected: _size == s,
                onSelected: (_) => setState(() => _size = s),
              ),
          ChoiceChip(
            label: Text(_isCustom ? 'Custom · $w×$h' : 'Custom…'),
            selected: _isCustom,
            onSelected: (_) => _custom(),
          ),
        ]),
        const SizedBox(height: 24),
        const _Label('START FROM'),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.82,
          children: [
            _Tile(
              label: 'Blank',
              onTap: () => widget.onStart(EditorModel(width: w, height: h)),
              child: const Icon(Icons.add, size: 32, color: GlyphColors.primary),
            ),
            for (final t in editorTemplates)
              _Tile(
                label: t.name,
                onTap: () => widget.onStart(EditorModel.fromClip(t.build(w, h), fps: t.fps)),
                child: LedMatrixView(frame: t.build(w, h).frames.first, borderRadius: 8),
              ),
          ],
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
                color: GlyphColors.textMuted)),
      );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.onTap, required this.child});

  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
        color: GlyphColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: GlyphColors.outline),
            ),
            child: Column(children: [
              Expanded(child: Center(child: child)),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );
}
