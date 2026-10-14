import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'named index is reproducible from its complete frozen descriptions',
    () async {
      final result = await Process.run('python3', [
        '-c',
        '''
import json,sys
sys.path.insert(0, 'tool')
from build_pipplee_names import name_rows
index = json.load(open('assets/catalog/pipplee.json'))
descriptions = json.load(open('catalog_assets/pipplee/descriptions.json'))['clips']
existing = json.load(open('assets/catalog/catalog.json'))['items']
assert index['version'] == 3
assert len(descriptions) == len({r[1] for r in index['rows']})
assert index['rows'] == name_rows(index['rows'], descriptions, [i['title'] for i in existing]), 'Run tool/build_pipplee_names.py'
assert all(not r[7].startswith('Pipplee ') for r in index['rows'])
assert set(index['categories']) == {r[11] for r in index['rows']}
assert all(r[11] != 'Pipplee' for r in index['rows'])
''',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
  );

  test('metadata builder requires full coverage and keeps variant names deterministic', () async {
    final result = await Process.run('python3', [
      '-c',
      '''
import sys
sys.path.insert(0, 'tool')
from build_pipplee_names import name_rows
rows = [[i, sha, 100, 16, 16, 2, ['red']] for i, sha in [(1,'a'),(2,'b'),(3,'c'),(4,'a')]]
descriptions = {sha: {'title': title, 'subjects': ['cat'], 'aliases': [], 'tags': ['red']}
                for sha, title in [('a','Cat'),('b','Cat'),('c','Cat 2')]}
named = name_rows(rows, descriptions, ['Cat'])
assert [r[7] for r in named] == ['Cat 3','Cat 4','Cat 2','Cat 5']
assert all(r[:7] == old for r, old in zip(named, rows))
assert 'Cat' in named[0][9]
assert named == name_rows(named, descriptions, ['Cat'])
for bad in [
    {k:v for k,v in descriptions.items() if k != 'c'},
    {**descriptions, 'unknown': descriptions['a']},
    {**descriptions, 'a': {**descriptions['a'], 'title': 'Pipplee 1'}},
    {**descriptions, 'a': {**descriptions['a'], 'subjects': []}},
    {**descriptions, 'a': {**descriptions['a'], 'aliases': [False]}},
]:
    try: name_rows(rows, bad)
    except ValueError: pass
    else: raise AssertionError('Invalid metadata accepted')
print('Validated complete coverage, stable identities, alias retention and collisions')
''',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('browsing groups follow concrete subjects and preserve explicit context', () async {
    final result = await Process.run('python3', ['-c', '''
import sys
sys.path.insert(0, 'tool')
from pipplee_categories import category_for
def category(title, subjects, tags=(), **extra):
    return category_for(dict(title=title, subjects=subjects, tags=list(tags), aliases=[], **extra))
assert category('White Cat', ['cat', 'face']) == 'Animals'
assert category('Yellow Smiley', ['face']) == 'Emoji'
assert category('Pink Heart', ['heart']) == 'Love'
assert category('Christmas Cat', ['cat'], ['christmas']) == 'Holidays'
assert category('Blue Rocket', ['rocket']) == 'Space'
assert category('Rocking Sailboat', ['sailboat', 'water']) == 'Water'
assert category('Cyan Abstract Waves', ['wave'], ['abstract']) == 'Abstract'
assert category('Orange Waves', ['wave'], ['orange']) == 'Abstract'
assert category('Green Invader', ['alien'], ['game']) == 'Gaming'
assert category('Pink Music Note', ['music note']) == 'Music'
assert category('Happy Birthday', ['text']) == 'Holidays'
assert category('Hello', ['text']) == 'Words'
assert category('Portrait', ['person']) == 'People'
assert category('Gray Car', ['car']) == 'Transport'
assert category('Pink Donut', ['donut']) == 'Food & Drink'
assert category('Rainbow Grid', ['grid'], ['cute']) == 'Abstract'
assert category('Orange Unclear Form', ['unclear']) == 'Other'
assert category('Reviewed Override', ['person'], category='Characters') == 'Characters'
try: category('Invalid Override', ['person'], category='Pipplee')
except ValueError: pass
else: raise AssertionError('Unknown category accepted')
''']);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });
}
