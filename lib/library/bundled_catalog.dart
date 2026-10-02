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
  try {
    return Catalog.parse(await b.loadString(bundledCatalogAsset));
  } catch (_) {
    return Catalog.parse(await b.loadString(starterCatalogAsset));
  }
}
