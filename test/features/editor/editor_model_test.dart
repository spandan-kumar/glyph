import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/engine/clip.dart';
import 'package:glyph/engine/frame.dart';
import 'package:glyph/engine/generator.dart';
import 'package:glyph/engine/palette.dart';
import 'package:glyph/features/editor/editor_model.dart';
import 'package:glyph/features/editor/live_mirror.dart';
import 'package:glyph/features/editor/pixel_ops.dart';
import 'package:glyph/features/editor/templates.dart';

const red = 0xFF0000, blue = 0x0000FF;

int lit(Frame f) {
  var n = 0;
  for (var y = 0; y < f.height; y++) {
    for (var x = 0; x < f.width; x++) {
      if (f.get(x, y) != 0) n++;
    }
  }
  return n;
}

void main() {
  group('pixel ops', () {
    test('line covers every step with no gaps, in both directions', () {
      final pts = linePoints(0, 0, 7, 3);
      expect(pts.first, (0, 0));
      expect(pts.last, (7, 3));
      expect(pts.length, 8);
      for (var i = 1; i < pts.length; i++) {
        final (ax, ay) = pts[i - 1];
        final (bx, by) = pts[i];
        expect((ax - bx).abs() <= 1 && (ay - by).abs() <= 1, isTrue);
      }
      expect(linePoints(3, 5, 3, 1).length, 5);
      expect(linePoints(2, 2, 2, 2), [(2, 2)]);
      expect(linePoints(5, 0, 0, 5).toSet().length, 6);
    });

    test('rectangle outline has each cell once', () {
      final pts = rectPoints(4, 3, 1, 1);
      expect(pts.length, pts.toSet().length);
      expect(pts.length, 10); // 4×3 box perimeter
      expect(rectPoints(2, 2, 2, 2), [(2, 2)]);
      expect(rectPoints(0, 0, 3, 0).length, 4);
    });

    test('flood fill stays inside a closed outline', () {
      final f = Frame(8, 8);
      for (final (x, y) in rectPoints(1, 1, 5, 5)) {
        f.set(x, y, red);
      }
      expect(floodFill(f, 3, 3, blue), 9);
      expect(f.get(3, 3), blue);
      expect(f.get(0, 0), 0);
      expect(f.get(1, 1), red);
      expect(floodFill(f, 3, 3, blue), 0);
      expect(floodFill(f, 0, 0, blue), 64 - 25);
      expect(floodFill(f, -1, 0, red), 0);
    });

    test('mirrored points', () {
      expect(mirrored(1, 2, 8, 8), [(1, 2)]);
      expect(mirrored(1, 2, 8, 8, mx: true).toSet(), {(1, 2), (6, 2)});
      expect(mirrored(1, 2, 8, 8, mx: true, my: true).toSet(),
          {(1, 2), (6, 2), (1, 5), (6, 5)});
      // Centre column of an odd width maps onto itself.
      expect(mirrored(2, 0, 5, 1, mx: true), [(2, 0)]);
    });

    test('shift wraps around', () {
      final f = Frame(4, 2)..set(3, 1, red);
      final s = shifted(f, 1, 1);
      expect(s.get(0, 0), red);
      expect(lit(s), 1);
      expect(shifted(f, -4, -2).get(3, 1), red);
    });
  });

  group('EditorModel', () {
    test('fast pencil swipe is interpolated', () {
      final m = EditorModel(width: 16, height: 16)..color = red;
      m.strokeStart(0, 0);
      m.strokeMove(15, 0);
      m.strokeEnd();
      for (var x = 0; x < 16; x++) {
        expect(m.frame.get(x, 0), red, reason: 'x=$x');
      }
      expect(m.recent.first, red);
    });

    test('symmetry applies to pencil and fill', () {
      final m = EditorModel(width: 8, height: 8)
        ..color = red
        ..mirrorX = true
        ..mirrorY = true;
      m.strokeStart(1, 1);
      m.strokeEnd();
      expect([m.frame.get(1, 1), m.frame.get(6, 1), m.frame.get(1, 6), m.frame.get(6, 6)],
          everyElement(red));
      expect(lit(m.frame), 4);

      m
        ..mirrorY = false
        ..tool = EditorTool.fill
        ..color = blue;
      m.strokeStart(0, 0);
      expect(m.frame.get(0, 0), blue);
      expect(m.frame.get(1, 1), red);
    });

    test('line and rect preview from the stroke start, committing once', () {
      final m = EditorModel(width: 10, height: 10)
        ..color = red
        ..tool = EditorTool.line;
      m.strokeStart(0, 0);
      m.strokeMove(9, 9);
      m.strokeMove(9, 0); // the diagonal preview must be replaced
      m.strokeEnd();
      expect(lit(m.frame), 10);
      expect(m.frame.get(5, 5), 0);
      m.undo();
      expect(lit(m.frame), 0);
      expect(m.canUndo, isFalse);

      m.tool = EditorTool.rect;
      m.strokeStart(2, 2);
      m.strokeMove(5, 4);
      m.strokeEnd();
      expect(lit(m.frame), 10);
      expect(m.frame.get(3, 3), 0);
    });

    test('eraser, picker and move', () {
      final m = EditorModel(width: 4, height: 4)..color = red;
      m.strokeStart(0, 0);
      m.strokeMove(3, 0);
      m.strokeEnd();
      m.tool = EditorTool.eraser;
      m.strokeStart(1, 0);
      m.strokeEnd();
      expect(m.frame.get(1, 0), 0);

      m.color = blue;
      m.tool = EditorTool.picker;
      m.strokeStart(2, 0);
      expect(m.color, red);
      expect(m.tool, EditorTool.pencil, reason: 'picker hands back to the previous tool');

      m.tool = EditorTool.move;
      m.strokeStart(0, 0);
      m.strokeMove(0, 2);
      m.strokeEnd();
      expect(m.frame.get(0, 2), red);
      expect(m.frame.get(0, 0), 0);
    });

    test('undo/redo per stroke, redo cleared by a new stroke, bounded', () {
      final m = EditorModel(width: 4, height: 4)..color = red;
      expect(m.canUndo, isFalse);
      m.strokeStart(0, 0);
      m.strokeMove(1, 0);
      m.strokeMove(2, 0);
      m.strokeEnd();
      m.strokeStart(0, 3);
      m.strokeEnd();
      expect(lit(m.frame), 4);

      m.undo();
      expect(lit(m.frame), 3);
      m.undo();
      expect(lit(m.frame), 0);
      expect(m.canUndo, isFalse);
      m.redo();
      expect(lit(m.frame), 3);
      m.strokeStart(3, 3);
      m.strokeEnd();
      expect(m.canRedo, isFalse);

      // A stroke that changes nothing doesn't create an undo step.
      final before = m.canUndo;
      m.strokeStart(3, 3);
      m.strokeEnd();
      m.undo();
      expect(m.frame.get(3, 3), 0, reason: 'no-op stroke was skipped, so undo reverts (3,3)');
      expect(before, isTrue);

      for (var i = 0; i < EditorModel.maxHistory + 20; i++) {
        m.color = i.isEven ? red : blue;
        m.strokeStart(0, 0);
        m.strokeEnd();
      }
      var steps = 0;
      while (m.canUndo) {
        m.undo();
        steps++;
      }
      expect(steps, EditorModel.maxHistory);
    });

    test('cancelled stroke leaves no trace', () {
      final m = EditorModel(width: 4, height: 4)..color = red;
      m.strokeStart(0, 0);
      m.strokeMove(3, 3);
      m.strokeCancel();
      expect(lit(m.frame), 0);
      expect(m.canUndo, isFalse);
    });

    test('frame ops are undoable', () {
      final m = EditorModel(width: 4, height: 4)..color = red;
      m.strokeStart(0, 0);
      m.strokeEnd();
      m.duplicateFrame();
      expect(m.frameCount, 2);
      expect(m.index, 1);
      expect(m.frame.get(0, 0), red);
      m.addFrame();
      expect(m.frameCount, 3);
      expect(lit(m.frame), 0);
      expect(m.previous!.get(0, 0), red);

      m.strokeStart(3, 3);
      m.strokeEnd();
      m.moveFrame(2, 0);
      expect(m.index, 0);
      expect(m.frame.get(3, 3), red);
      expect(m.frames[1].get(0, 0), red);

      m.deleteFrame();
      expect(m.frameCount, 2);
      expect(m.frame.get(0, 0), red);
      m.undo();
      expect(m.frameCount, 3);
      expect(m.frames[0].get(3, 3), red);

      m.selectFrame(1);
      m.clearFrame();
      expect(lit(m.frame), 0);
      m.undo();
      expect(m.frame.get(0, 0), red);

      final one = EditorModel(width: 2, height: 2)..color = red;
      one.strokeStart(0, 0);
      one.strokeEnd();
      one.deleteFrame();
      expect(one.frameCount, 1);
      expect(lit(one.frame), 0);
    });

    test('fps is clamped and survives a JSON round trip through FrameClip', () {
      final m = EditorModel(width: 5, height: 3, fps: 99)..color = red;
      expect(m.fps, EditorModel.maxFps);
      m.fps = 12;
      m.strokeStart(0, 0);
      m.strokeMove(4, 2);
      m.strokeEnd();
      m.duplicateFrame();
      m.tool = EditorTool.fill;
      m.color = blue;
      m.strokeStart(4, 0);

      final json = jsonDecode(jsonEncode(m.toClip().toJson())) as Map<String, dynamic>;
      final clip = FrameClip.fromJson(json);
      expect(clip.width, 5);
      expect(clip.height, 3);
      expect(clip.frames.length, 2);

      for (final restored in [
        EditorModel.fromClip(clip, fps: m.meta['fps'] as int),
        EditorModel.fromClip(clip),
      ]) {
        expect(restored.fps, 12);
        expect(restored.frameCount, 2);
        for (var i = 0; i < 2; i++) {
          expect(sameFrame(restored.frames[i], m.frames[i]), isTrue);
        }
      }
      // The clip is a snapshot, not a live view of the document.
      m.clearFrame();
      expect(lit(clip.frames[1]), greaterThan(0));
    });

    test('dirty flag', () {
      final m = EditorModel(width: 2, height: 2);
      expect(m.isDirty, isFalse);
      m.strokeStart(0, 0);
      m.strokeEnd();
      expect(m.isDirty, isTrue);
      m.markSaved();
      expect(m.isDirty, isFalse);
    });
  });

  test('templates fit any size and are not empty', () {
    for (final t in editorTemplates) {
      for (final (w, h) in [...matrixSizes, (24, 12)]) {
        final c = t.build(w, h);
        expect((c.width, c.height), (w, h));
        expect(c.frames.every((f) => lit(f) > 0), isTrue, reason: '${t.name} $w×$h');
      }
      final frames = t.build(16, 16).frames;
      expect(frames.length, greaterThan(1), reason: '${t.name} should animate');
    }
  });

  test('live mirror follows the source and fits the output size', () {
    var src = Frame(4, 4)..set(0, 0, red);
    var rev = 0;
    final g = LiveMirrorGenerator(source: () => src, revision: () => rev);
    final out = Frame(8, 8);
    final inst = g.create(8, 8, 0);
    final p = Params.defaultsFor(g);
    inst.render(out, 0, 0.02, p, palettes.first);
    expect(out.get(0, 0), red);
    expect(out.get(1, 1), red);
    expect(out.get(2, 2), 0);

    src.set(3, 3, blue);
    rev++;
    inst.render(out, 0, 0.02, p, palettes.first);
    expect(out.get(7, 7), blue);

    src = Frame(4, 4);
    inst.render(out, 0, 0.02, p, palettes.first);
    expect(lit(out), 0);
  });
}
