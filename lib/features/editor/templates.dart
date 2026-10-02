import '../../engine/clip.dart';
import '../../engine/frame.dart';

/// A starter drawing authored at 16×16; [build] fits it to the chosen size.
class EditorTemplate {
  const EditorTemplate(this.name, this._frames, {this.fps = 4});

  final String name;
  final List<Frame> Function() _frames;
  final int fps;

  FrameClip build(int width, int height) =>
      FrameClip.uniform(_frames(), fps: fps).fitTo(width, height);
}

const matrixSizes = <(int, int)>[(8, 8), (16, 16), (32, 8), (32, 32)];

final editorTemplates = <EditorTemplate>[
  EditorTemplate('Heart', _heart, fps: 3),
  EditorTemplate('Smiley', _smiley, fps: 4),
  EditorTemplate('Star', _star, fps: 3),
  EditorTemplate('Rain', _rain, fps: 6),
];

Frame _art(List<String> rows, Map<String, int> colors) {
  final f = Frame(rows.first.length, rows.length);
  for (var y = 0; y < rows.length; y++) {
    for (var x = 0; x < rows[y].length; x++) {
      final c = colors[rows[y][x]];
      if (c != null) f.set(x, y, c);
    }
  }
  return f;
}

const _red = {'R': 0xFF0030, 'W': 0xFFB0C0};

List<Frame> _heart() => [
      _art(const [
        '................',
        '................',
        '...RRR....RRR...',
        '..RRRRR..RRRRR..',
        '.RRWRRRRRRRRRRR.',
        '.RWRRRRRRRRRRRR.',
        '.RRRRRRRRRRRRRR.',
        '.RRRRRRRRRRRRRR.',
        '..RRRRRRRRRRRR..',
        '...RRRRRRRRRR...',
        '....RRRRRRRR....',
        '.....RRRRRR.....',
        '......RRRR......',
        '.......RR.......',
        '................',
        '................',
      ], _red),
      _art(const [
        '................',
        '................',
        '................',
        '................',
        '....RR....RR....',
        '...RRRR..RRRR...',
        '...RWRRRRRRRR...',
        '...RRRRRRRRRR...',
        '....RRRRRRRR....',
        '.....RRRRRR.....',
        '......RRRR......',
        '.......RR.......',
        '................',
        '................',
        '................',
        '................',
      ], _red),
    ];

List<Frame> _smiley() {
  const face = [
    '................',
    '.....YYYYYY.....',
    '...YYYYYYYYYY...',
    '..YYYYYYYYYYYY..',
    '.YYYYYYYYYYYYYY.',
    '.YYYKKYYYYKKYYY.',
    '.YYYKKYYYYKKYYY.',
    '.YYYYYYYYYYYYYY.',
    '.YYYYYYYYYYYYYY.',
    '.YYKYYYYYYYYKYY.',
    '.YYYKYYYYYYKYYY.',
    '..YYYKKKKKKYYY..',
    '..YYYYYYYYYYYY..',
    '...YYYYYYYYYY...',
    '.....YYYYYY.....',
    '................',
  ];
  const colors = {'Y': 0xFFC000, 'K': 0x301000};
  final open = _art(face, colors);
  final blink = _art([...face]..[5] = '.YYYYYYYYYYYYYY.', colors);
  return [open, open.copy(), open.copy(), blink];
}

List<Frame> _star() {
  const star = [
    '................',
    '.......YY.......',
    '.......YY.......',
    '......YYYY......',
    '......YYYY......',
    '.YYYYYYYYYYYYYY.',
    '..YYYYYYYYYYYY..',
    '...YYYOOOOYYY...',
    '....YYOOOOYY....',
    '....YYYYYYYY....',
    '...YYYYYYYYYY...',
    '...YYYY..YYYY...',
    '..YYY......YYY..',
    '..YY........YY..',
    '................',
    '................',
  ];
  const colors = {'Y': 0xFFD000, 'O': 0xFF8000};
  Frame sparkle(List<(int, int)> at) {
    final f = _art(star, colors);
    for (final (x, y) in at) {
      f.set(x, y, 0xFFFFFF);
    }
    return f;
  }

  return [
    sparkle([(1, 1), (14, 10), (3, 15)]),
    sparkle([(14, 1), (0, 9), (12, 15)]),
  ];
}

List<Frame> _rain() {
  const cloud = [
    '................',
    '......GGG.......',
    '....GGWWWGG.....',
    '...GWWWWWWWGGG..',
    '..GWWWWWWWWWWWG.',
    '.GWWWWWWWWWWWWG.',
    '.GGWWWWWWWWWWGG.',
    '..GGGGGGGGGGGG..',
  ];
  const colors = {'G': 0x606078, 'W': 0xD0D8FF};
  const drops = [(3, 0), (6, 5), (9, 2), (12, 6)];
  // Each drop falls two rows per frame over an 8-row loop, so 4 frames wrap.
  return [
    for (var f = 0; f < 4; f++) _rainFrame(cloud, colors, drops, f),
  ];
}

Frame _rainFrame(List<String> cloud, Map<String, int> colors, List<(int, int)> drops, int f) {
  final frame = _art([...cloud, for (var i = 0; i < 8; i++) '................'], colors);
  for (final (x, phase) in drops) {
    final y = 8 + (f * 2 + phase) % 8;
    frame.set(x, y, 0x2080FF);
    frame.set(x, y + 1, 0x0030C0);
  }
  return frame;
}
