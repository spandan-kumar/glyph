// Prefix used by 1.4.5–1.4.7 for imported items; remove after users have migrated.
const legacyCollectionPrefix = 'pipp' 'lee';

/// Canonicalize only collection identities, leaving unrelated/user IDs intact.
String importedCollectionId(String id) {
  final match = RegExp('^(clip:)?$legacyCollectionPrefix-([0-9]+)\$').firstMatch(id);
  return match == null ? id : '${match[1] ?? ''}imported-${match[2]}';
}

/// The old device identity, including any revision suffix handled by WLED.
String? legacyCollectionFileName(String fileName) {
  final match = RegExp(r'^imported-([0-9]+)\.gif$').firstMatch(fileName);
  return match == null ? null : '$legacyCollectionPrefix-${match[1]}.gif';
}

/// References in extensible creation metadata; never rewrite titles or pixels.
dynamic migrateCollectionReferences(dynamic value) {
  const keys = {'itemId', 'item_id', 'generator', 'generatorId', 'generator_id',
    'libraryId', 'sourceItemId', 'sourceGeneratorId'};
  if (value is List) return value.map(migrateCollectionReferences).toList();
  if (value is Map) {
    return <String, dynamic>{
      for (final e in value.entries)
        e.key as String: keys.contains(e.key) && e.value is String
            ? importedCollectionId(e.value as String)
            : migrateCollectionReferences(e.value),
    };
  }
  return value;
}
