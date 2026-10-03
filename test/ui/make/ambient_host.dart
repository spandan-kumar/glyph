import 'package:flutter/widgets.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/ui/design/ambient.dart';

/// Provides the room light like GlyphApp does, owning the controller so its
/// sampling timer stops when the test tree is torn down.
class AmbientHost extends StatefulWidget {
  const AmbientHost({super.key, required this.playback, required this.child});

  final PlaybackController playback;
  final Widget child;

  @override
  State<AmbientHost> createState() => _AmbientHostState();
}

class _AmbientHostState extends State<AmbientHost> {
  late final _ambient = AmbientController(widget.playback);

  @override
  void dispose() {
    _ambient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AmbientScope(controller: _ambient, child: widget.child);
}
