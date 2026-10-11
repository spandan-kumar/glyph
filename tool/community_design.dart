// GitHub community submissions. Inputs are data, never commands.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:glyph/engine/bake_limits.dart';
import 'package:glyph/engine/gif_encoder.dart';
import 'package:glyph/library/community_design.dart';

const communityMarker = '<!-- glyph-community-check -->';
const shareAgain =
    'Open the drawing in Glyph and tap Share with the community again.';
const _json = JsonEncoder.withIndent('  ');

String designSlug(String title) {
  var slug = title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  slug = slug.replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.length > 30) {
    slug = slug.substring(0, 30).replaceAll(RegExp(r'-+$'), '');
  }
  return slug.isEmpty ? 'drawing' : slug;
}

String cleanCredit(String text) {
  var clean = text
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAllMapped(RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!)
      .replaceAll(RegExp(r'[\x00-\x1f\x7f<>`*_~\[\]\\#]'), ' ')
      .replaceAll("'''", '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  clean = String.fromCharCodes(clean.runes.take(40)).trim();
  return clean;
}

/// GitHub issue-form headings, stopping at the next section. Code fences are
/// ignored so a heading embedded in the design field cannot become a credit.
String creditFromBody(String body) {
  var fenced = false, reading = false;
  final lines = <String>[];
  for (final line in const LineSplitter().convert(body)) {
    if (line.trimLeft().startsWith('```')) {
      fenced = !fenced;
      continue;
    }
    if (fenced) continue;
    if (line.startsWith('### ')) {
      if (reading) break;
      reading = line.trim() == '### How should we credit you?';
      continue;
    }
    if (reading) lines.add(line);
  }
  final text = lines.join('\n').trim();
  return text == '_No response_' ? '' : cleanCredit(text);
}

String markdownText(String text) => text.replaceAllMapped(
  RegExp(r'[\\`*_{}\[\]<>()#+.!|~@&]'),
  (m) => '&#${m[0]!.codeUnitAt(0)};',
);

CommunityDesign decodeSubmission(String body) {
  final CommunityDesign design;
  try {
    design = CommunityDesign.decode(body);
  } on FormatException {
    throw const CommunityDesignException('The design text is damaged.');
  }
  // The existing sprite compiler stores JSON in triple-quoted Dart strings.
  if (design.title.contains("'''")) {
    throw const CommunityDesignException(
      'Rename the drawing without three consecutive apostrophes.',
    );
  }
  final used = design.frames.expand((f) => f).join().split('').toSet();
  final visible = design.colors.entries.any(
    (e) =>
        used.contains(e.key) &&
        [
          1,
          3,
          5,
        ].any((i) => int.parse(e.value.substring(i, i + 2), radix: 16) > 8),
  );
  if (!visible) {
    throw const CommunityDesignException(
      'The drawing is blank or too dark. Add some brighter pixels.',
    );
  }
  return design;
}

Uint8List previewGif(CommunityDesign design) {
  final clip = design.toClip();
  // Keep even a maximum-size submission within the engine's memory budget.
  final scale = math.min(
    8,
    math
        .sqrt(
          maxBakePixels / (design.width * design.height * design.frames.length),
        )
        .floor(),
  );
  final enlarged = clip.fitTo(design.width * scale, design.height * scale);
  return encodeGif(enlarged.frames, [
    for (final ms in clip.delaysMs) (ms / 10).round(),
  ]);
}

/// Writes a report on both paths; removes old artifacts before a failed recheck.
int checkSubmission(String body, Directory out) {
  out.createSync(recursive: true);
  for (final name in ['preview.gif', 'design.json']) {
    final file = File('${out.path}/$name');
    if (file.existsSync()) file.deleteSync();
  }
  String report;
  var status = 0;
  try {
    final design = decodeSubmission(body);
    File('${out.path}/preview.gif').writeAsBytesSync(previewGif(design));
    File('${out.path}/design.json')
        .writeAsStringSync('${_json.convert(design.toJson())}\n');
    report =
        '$communityMarker\n\nThanks for sharing **${markdownText(design.title)}**!\n\n'
        '${design.width} × ${design.height} pixels · ${design.frames.length} frame(s) · '
        '${design.colors.length} colour(s).\n\nReady for a maintainer to review.';
  } on CommunityDesignException catch (e) {
    status = 1;
    report =
        '$communityMarker\n\nWe couldn’t read this drawing: ${markdownText(e.message)}\n\n$shareAgain';
  }
  File('${out.path}/report.md').writeAsStringSync('$report\n');
  return status;
}

/// Pure construction, shared with tests. Never mutates the supplied pack.
Map<String, dynamic> appendDesign({
  required CommunityDesign design,
  required int issue,
  required String author,
  required String url,
  required int added,
  String credit = '',
  Map<String, dynamic>? pack,
  Set<String> catalogTitles = const {},
  Set<String> spriteIds = const {},
}) {
  if (issue < 1 ||
      !RegExp(r'^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,38})(?:\[bot\])?$')
          .hasMatch(author) ||
      url != 'https://github.com/spandan-kumar/glyph/issues/$issue') {
    throw const CommunityDesignException(
      'Invalid issue number, GitHub username or issue URL.',
    );
  }
  final original =
      pack ??
      {
        'pack': 'community',
        'category': 'Community',
        'colors': <String, String>{},
        'sprites': <dynamic>[],
      };
  if (original['pack'] != 'community' ||
      original['category'] != 'Community' ||
      original['sprites'] is! List) {
    throw const CommunityDesignException('The community pack is invalid.');
  }
  final sprites = List<dynamic>.of(original['sprites'] as List);
  final id = 'community-${designSlug(design.title)}-$issue';
  if (spriteIds.contains(id) || sprites.any((s) => (s as Map)['id'] == id)) {
    throw CommunityDesignException('The design $id is already in the catalog.');
  }
  final cleaned = cleanCredit(credit);
  final creator = cleaned.isEmpty ? '@$author' : cleaned;
  final titles = {
    ...catalogTitles.map((t) => t.toLowerCase()),
    for (final s in sprites) (s as Map)['title'].toString().toLowerCase(),
  };
  var title = design.title;
  if (titles.contains(title.toLowerCase())) title = '$title by $creator';
  final base = title;
  var suffix = 2;
  while (titles.contains(title.toLowerCase())) {
    title = '$base ($issue-${suffix++})';
  }
  final sprite = design.toSprite(id: id, creator: creator, url: url)
    ..['title'] = title;
  // The catalog revision this drawing arrives in, so it lands on Just added.
  // A string: published apps reject non-string source values other than year.
  (sprite['source'] as Map)['added'] = '$added';
  return {
    ...original,
    'sprites': [...sprites, sprite],
  };
}

void addSubmission(String body, Map<String, String> options) {
  final design = decodeSubmission(body);
  final catalog =
      jsonDecode(File('assets/catalog/catalog.json').readAsStringSync()) as Map;
  final ids = <String>{};
  final titles = <String>{
    for (final i in catalog['items'] as List) (i as Map)['title'] as String,
  };
  for (final file in Directory(
    'assets/catalog/sprites',
  ).listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
    final pack = jsonDecode(file.readAsStringSync()) as Map;
    for (final s in pack['sprites'] as List) {
      ids.add((s as Map)['id'] as String);
      titles.add(s['title'] as String);
    }
  }
  final file = File('assets/catalog/sprites/community.json');
  // New content must publish under a higher revision; bump it here so the
  // drawing and the revision it arrives in stay together.
  final revisionFile = File('assets/catalog/content_revision.json');
  final revision = jsonDecode(revisionFile.readAsStringSync()) as Map<String, dynamic>;
  final added = (revision['revision'] as int) + 1;
  final result = appendDesign(
    design: design,
    issue: int.parse(options['issue']!),
    author: options['author']!,
    url: options['url']!,
    added: added,
    credit: options['credit'] ?? creditFromBody(body),
    pack: file.existsSync()
        ? jsonDecode(file.readAsStringSync()) as Map<String, dynamic>
        : null,
    catalogTitles: titles,
    spriteIds: ids,
  );
  file.writeAsStringSync('${_json.convert(result)}\n');
  revisionFile.writeAsStringSync('${jsonEncode({...revision, 'revision': added})}\n');
  stdout.writeln((result['sprites'] as List).last['id']);
}

void main(List<String> args) {
  try {
    if (args.isEmpty || !['check', 'add'].contains(args.first)) {
      throw const FormatException('Expected check or add.');
    }
    final allowed = args.first == 'check'
        ? {'body', 'out'}
        : {'body', 'issue', 'author', 'url', 'credit'};
    final required = {...allowed}..remove('credit');
    final options = <String, String>{};
    for (var i = 1; i < args.length; i += 2) {
      if (!args[i].startsWith('--') || i + 1 >= args.length) {
        throw const FormatException('Expected --option value.');
      }
      final key = args[i].substring(2);
      if (!allowed.contains(key) || options.containsKey(key)) {
        throw const FormatException('Unknown or repeated option.');
      }
      options[key] = args[i + 1];
    }
    if (!required.every(options.containsKey)) {
      throw const FormatException('Missing required options.');
    }
    final body = File(options['body']!).readAsStringSync();
    if (args.first == 'check') {
      exitCode = checkSubmission(body, Directory(options['out']!));
    } else {
      addSubmission(body, options);
    }
  } on CommunityDesignException catch (e) {
    stderr.writeln(e.message);
    exitCode = 1;
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    exitCode = 1;
  } on FileSystemException {
    stderr.writeln(
      'Could not read or write the submission files. Check the paths and permissions.',
    );
    exitCode = 1;
  }
}
