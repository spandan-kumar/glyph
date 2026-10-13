import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:glyph/engine/clip_asset.dart';

(ClipAsset, Uint8List) clipFixture({
  int id = 42,
  int width = 2,
  int height = 1,
  List<int> colours = const [0xff0000, 0x0000ff],
  List<int>? delays,
}) {
  final bytes = Uint8List(12 + colours.length * (4 + width * height * 3));
  bytes.setAll(0, 'GLC1'.codeUnits);
  final data = ByteData.sublistView(bytes);
  data.setUint16(4, width, Endian.little);
  data.setUint16(6, height, Endian.little);
  data.setUint32(8, colours.length, Endian.little);
  var at = 12;
  for (var i = 0; i < colours.length; i++) {
    data.setUint32(at, delays?[i] ?? 100, Endian.little);
    at += 4;
    for (var pixel = 0; pixel < width * height; pixel++) {
      bytes[at++] = colours[i] >> 16;
      bytes[at++] = (colours[i] >> 8) & 255;
      bytes[at++] = colours[i] & 255;
    }
  }
  final packed = Uint8List.fromList(gzip.encode(bytes));
  final asset = ClipAsset(
    id: 'clip:pipplee-$id',
    title: 'Pipplee $id',
    sha256: sha256.convert(packed).toString(),
    bytes: packed.length,
    width: width,
    height: height,
    frames: colours.length,
  );
  return (asset, packed);
}
