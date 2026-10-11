import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/features/device/boot_intro.dart';
import 'package:glyph/wled/wled_client.dart';

import 'fake_wled.dart';

void main() {
  late FakeWled wled;
  late WledClient first, second;

  setUp(() async {
    wled = FakeWled();
    first = wled.client('queue-test');
    second = wled.client('queue-test');
    BootIntro.resetForTest();
    BootIntro.bake = (w, h) async => Uint8List(20);
    await BootIntro.ensure(first, await first.capabilities());
    wled.posts.clear();
  });
  tearDown(() {
    first.close();
    second.close();
    BootIntro.resetForTest();
  });

  test('boot rewrite and a second client save cannot overlap', () async {
    final entered = Completer<void>(), release = Completer<void>();
    wled.beforeRequest = (r) async {
      if (r.url.path == '/presets.json') {
        if (!entered.isCompleted) entered.complete();
        await release.future;
      }
    };
    final boot = BootIntro.setPowerOnLook(first, 1);
    await entered.future;
    final save = second.saveCurrentAsPreset('New user look', id: 42);
    await Future<void>.delayed(Duration.zero);
    expect(wled.posts.any((p) => p.$2.containsKey('psave')), isFalse);
    release.complete();
    await Future.wait([boot, save]);
    expect(wled.presets['42']['n'], 'New user look');
    expect(wled.presets['1']['n'], 'Ocean Plasma');
    expect(wled.presets['249']['playlist']['end'], 1);
  });

  test('boot reads wait for the asynchronous firmware preset write', () async {
    wled.presetWriteDelay = const Duration(milliseconds: 400);
    final save = first.saveCurrentAsPreset('New user look', id: 42);
    final boot = BootIntro.setPowerOnLook(second, 1);
    await Future.wait([save, boot]);
    expect(wled.presets['42']['n'], 'New user look');
    expect(wled.presets['249']['playlist']['end'], 1);
  });

  test(
    'a failed operation releases the host queue and nested calls work',
    () async {
      final failed = expectLater(
        first.withPresetMutation<void>(() async {
          throw WledException('failed');
        }),
        throwsA(isA<WledException>()),
      );
      final next = first.withPresetMutation(
        () => second.saveCurrentAsPreset('Next', id: 42),
      );
      await failed;
      expect(await next.timeout(const Duration(seconds: 3)), 42);
      expect(wled.presets['42']['n'], 'Next');
    },
  );

  test('different hosts do not block each other', () async {
    final entered = Completer<void>(), release = Completer<void>();
    final held = first.withPresetMutation(() async {
      entered.complete();
      await release.future;
    });
    await entered.future;
    final other = wled.client('another-host');
    addTearDown(other.close);
    expect(
      await other
          .withPresetMutation(() async => 7)
          .timeout(const Duration(seconds: 1)),
      7,
    );
    release.complete();
    await held;
  });
}
