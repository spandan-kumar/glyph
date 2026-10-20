import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

import 'catalog.dart';
import 'imported_collection.dart';

/// The full generated library (tool/build_catalog.dart).
const bundledCatalogAsset = 'assets/catalog/catalog.json';

/// The original hand-written set, kept as a fallback.
const starterCatalogAsset = 'assets/catalog/starter.json';

/// Loads the bundled library, falling back to the starter set if the big
/// catalog is missing or unreadable.
Future<Catalog> loadBundledCatalog([AssetBundle? bundle]) async {
  final b = bundle ?? rootBundle;
  Catalog c;
  try {
    c = Catalog.parse(await b.loadString(bundledCatalogAsset));
  } catch (_) {
    c = Catalog.parse(await b.loadString(starterCatalogAsset));
  }
  final private = await loadPrivateCollection(b);
  if (private != null) c = c.merge(private);
  bundledRevision = c.items.fold(0, (m, i) => i.added > m ? i.added : m);
  return c;
}

/// The private pack's collection, or null when this build has none (public
/// builds) or its index is unreadable. A missing pack is silent.
Future<Catalog?> loadPrivateCollection(AssetBundle bundle) async {
  final String source;
  try {
    source = await bundle.loadString(importedIndexAsset, cache: false);
  } catch (_) {
    return null;
  }
  try {
    return parseImportedCollection(source);
  } catch (e) {
    debugPrint('Private collection ignored: $e');
    return null;
  }
}

/// The newest `added` revision shipped inside the app. Anything newer came
/// from the remote catalog and goes on Display's "Just added" shelf. Zero
/// (unknown, e.g. in tests) shows no such shelf.
int bundledRevision = 0;
