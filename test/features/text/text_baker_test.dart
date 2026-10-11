import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/engine/bake_limits.dart';
import 'package:glyph/features/text/text_baker.dart';
import 'package:glyph/features/text/text_generators.dart';
import 'package:glyph/features/text/text_settings.dart';

void main() {
  test('worker bake retains the full scrolling message past 12 seconds', () {
    final settings = TextSettings(text: List.filled(12, 'Complete message').join(' '));
    final seconds = (ScrollingText(settings).create(16, 16, 1) as TextInstance).loopSeconds!;
    final clip = bakeTextClip((settings, 'text', 16, 16));
    expect(seconds, greaterThan(12));
    expect(clip.totalMs, closeTo(seconds * 1000, 125));
  });

  test('extremely long messages fail explicitly without a truncated clip', () {
    final settings = TextSettings(text: List.filled(3000, 'Very long message').join(' '), speed: 0);
    expect(() => bakeTextClip((settings, 'text', 16, 16)),
        throwsA(isA<BakeLimitException>()));
  });
}
