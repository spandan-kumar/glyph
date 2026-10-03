import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/storage_alerts.dart';

void main() {
  test('storage levels switch at 50% and 90%', () {
    expect(StorageAlerts.levelFor(0.1), StorageLevel.ok);
    expect(StorageAlerts.levelFor(0.49), StorageLevel.ok);
    expect(StorageAlerts.levelFor(0.5), StorageLevel.half);
    expect(StorageAlerts.levelFor(0.89), StorageLevel.half);
    expect(StorageAlerts.levelFor(0.9), StorageLevel.nearlyFull);
  });
}
