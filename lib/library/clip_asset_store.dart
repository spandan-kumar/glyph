import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../engine/clip.dart';
import '../engine/clip_asset.dart';
import 'remote_catalog.dart';

/// Fetches only requested clips, verifies their bundled hashes and caches them.
class ClipAssetStore {
  ClipAssetStore({
    required this.cacheDir,
    Uri? baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
    this.maxDiskBytes = 96 * 1024 * 1024,
  }) : baseUrl = baseUrl ?? Uri.parse(RemoteCatalog.defaultUrl),
       _client = client ?? http.Client();

  static ClipAssetStore shared = ClipAssetStore(
    cacheDir: getApplicationSupportDirectory,
  );
  final Future<Directory> Function() cacheDir;
  final Uri baseUrl;
  final http.Client _client;
  final Duration timeout;
  final int maxDiskBytes;
  final _pending = <String, Future<FrameClip>>{};
  final _waiters = <Completer<void>>[];
  int _active = 0;
  bool _closed = false;

  Future<FrameClip> load(ClipAsset asset) {
    if (_closed) return Future.error(StateError('Animation downloads stopped'));
    final cached = ClipAssetLibrary.cached(asset.sha256);
    if (cached != null) return Future.value(cached);
    return _pending.putIfAbsent(
      asset.sha256,
      () => _load(asset).whenComplete(() {
        _pending.remove(asset.sha256);
      }),
    );
  }

  Future<void> _take() async {
    if (_active < 4) {
      _active++;
      return;
    }
    final waiter = Completer<void>();
    _waiters.add(waiter);
    await waiter.future;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
    } else {
      _active--;
    }
  }

  Future<FrameClip> _load(ClipAsset asset) async {
    await _take();
    try {
      if (_closed) throw StateError('Animation downloads stopped');
      final root = await cacheDir();
      final dir = Directory('${root.path}/animation-clips');
      await dir.create(recursive: true);
      final file = File('${dir.path}/${asset.sha256}.clip.gz');
      Uint8List? bytes;
      if (await file.exists()) {
        if (await file.length() == asset.bytes) {
          final stored = await file.readAsBytes();
          if (_matches(stored, asset)) bytes = stored;
        }
        if (bytes == null) await file.delete();
      }
      if (bytes == null) {
        bytes = await _download(baseUrl.resolve(asset.path), asset.bytes);
        if (!_matches(bytes, asset)) {
          throw const FormatException('Animation verification failed');
        }
      }
      final clip = await _decodeInIsolate(bytes, asset);
      if (_closed) throw StateError('Animation downloads stopped');
      if (!await file.exists()) {
        final temporary = File('${file.path}.tmp');
        try {
          await temporary.writeAsBytes(bytes, flush: true);
          await temporary.rename(file.path);
        } finally {
          if (await temporary.exists()) await temporary.delete();
        }
      }
      await file.setLastModified(DateTime.now());
      await _trim(dir, keep: file.path);
      ClipAssetLibrary.retain(asset.sha256, clip);
      return clip;
    } finally {
      _release();
    }
  }

  bool _matches(Uint8List bytes, ClipAsset asset) =>
      bytes.length == asset.bytes &&
      sha256.convert(bytes).toString() == asset.sha256;

  Future<Uint8List> _download(Uri uri, int expected) async {
    for (var redirects = 0; redirects <= 3; redirects++) {
      if (_closed ||
          uri.scheme != 'https' ||
          uri.origin != baseUrl.origin ||
          uri.userInfo.isNotEmpty) {
        throw const FormatException('Invalid animation host');
      }
      final request = http.Request('GET', uri)..followRedirects = false;
      final response = await _client.send(request).timeout(timeout);
      if (const {301, 302, 303, 307, 308}.contains(response.statusCode)) {
        final next = response.headers['location'];
        await response.stream.listen(null).cancel();
        if (next == null) {
          throw const FormatException('Missing animation redirect');
        }
        uri = uri.resolve(next);
        continue;
      }
      if (response.statusCode != 200) {
        await response.stream.listen(null).cancel();
        throw HttpException(
          'Animation download failed (${response.statusCode})',
        );
      }
      final output = BytesBuilder(copy: false);
      await for (final chunk in response.stream.timeout(timeout)) {
        if (_closed || output.length + chunk.length > expected) {
          throw const FormatException(
            'Animation download exceeds its verified size',
          );
        }
        output.add(chunk);
      }
      return output.takeBytes();
    }
    throw const FormatException('Too many animation redirects');
  }

  Future<void> _trim(Directory dir, {required String keep}) async {
    final files = <(File, FileStat)>[];
    await for (final entity in dir.list()) {
      if (entity is File &&
          RegExp(r'/[0-9a-f]{64}\.clip\.gz$').hasMatch(entity.path)) {
        files.add((entity, await entity.stat()));
      }
    }
    var size = files.fold(0, (n, f) => n + f.$2.size);
    files.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    for (final (file, stat) in files) {
      if (size <= maxDiskBytes) break;
      if (file.path == keep) continue;
      try {
        await file.delete();
        size -= stat.size;
      } on FileSystemException {
        /* Another load removed it. */
      }
    }
  }

  void close() {
    _closed = true;
    _client.close();
  }
}

Future<FrameClip> _decodeInIsolate(Uint8List bytes, ClipAsset asset) =>
    Isolate.run(() => inflateClipAsset(bytes, asset));

FrameClip inflateClipAsset(Uint8List bytes, ClipAsset asset) {
  final limit = 12 + asset.frames * (4 + asset.width * asset.height * 3);
  final sink = _LimitedSink(limit);
  final decoder = gzip.decoder.startChunkedConversion(sink);
  for (var at = 0; at < bytes.length; at += 16384) {
    decoder.add(
      Uint8List.sublistView(bytes, at, (at + 16384).clamp(0, bytes.length)),
    );
  }
  decoder.close();
  return decodeClipAsset(sink.bytes.takeBytes(), asset);
}

class _LimitedSink implements Sink<List<int>> {
  _LimitedSink(this.limit);
  final int limit;
  final bytes = BytesBuilder(copy: false);
  @override
  void add(List<int> data) {
    if (bytes.length + data.length > limit) {
      throw const FormatException('Animation expands beyond its declared size');
    }
    bytes.add(data);
  }

  @override
  void close() {}
}
