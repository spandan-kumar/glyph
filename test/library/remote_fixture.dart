import 'dart:convert';

Map<String, dynamic> remoteDocument({
  int revision = 4,
  String spriteId = 'remote-dot',
  String color = '#FF0000',
}) => {
  'version': 1,
  'revision': revision,
  'categories': ['Remote Picks', 'Empty Category'],
  'sprites': <dynamic>[
    {
      'pack': 'remote',
      'category': 'Remote Picks',
      'colors': {'R': color},
      'sprites': <dynamic>[
        {
          'id': spriteId,
          'title': 'Remote Dot',
          'tags': ['dot'],
          'source': {
            'year': 2026,
            'creator': 'Glyph contributors',
            'notice': 'Original artwork.',
          },
          'frames': [
            ['.R.', 'RRR', '.R.'],
          ],
        },
      ],
    },
  ],
  'items': <dynamic>[
    {
      'id': 'remote-plasma',
      'title': 'Remote Plasma',
      'category': 'Remote Picks',
      'tags': ['new'],
      'generator': 'plasma',
      'palette': 'ocean',
      'params': {'speed': 7, 'scale': 0.2, 'bogus': 1},
      'speed': 9,
      'notice': 'Credit retained.',
    },
    {
      'id': 'remote-dot-item',
      'title': 'Dot',
      'category': 'Remote Picks',
      'generator': 'sprite:$spriteId',
      'palette': 'neon',
    },
    {
      'id': 'ocean-plasma',
      'title': 'Ocean Plasma Remastered',
      'category': 'Chill',
      'generator': 'plasma',
      'palette': 'deepsea',
    },
  ],
};

Map<String, dynamic> cloneDocument(Map<String, dynamic> doc) =>
    jsonDecode(jsonEncode(doc)) as Map<String, dynamic>;
