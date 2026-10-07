import 'package:flutter/services.dart';

import 'catalog.dart';

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
  bundledRevision = c.items.fold(0, (m, i) => i.added > m ? i.added : m);
  return c;
}

/// The newest `added` revision shipped inside the app. Anything newer came
/// from the remote catalog and goes on Display's "Just added" shelf. Zero
/// (unknown, e.g. in tests) shows no such shelf.
int bundledRevision = 0;
