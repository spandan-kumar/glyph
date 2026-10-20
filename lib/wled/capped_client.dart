import 'dart:async';

import 'package:http/http.dart' as http;

/// Stops reading a reply once it passes [maxBytes], so a broken or hostile
/// device can't fill the phone's memory. Replies that announce a larger
/// `Content-Length` are refused before any body is read; the rest are cut
/// off mid-stream, which also closes the connection.
class CappedClient extends http.BaseClient {
  CappedClient(this._inner, this.maxBytes);

  final http.Client _inner;
  final int maxBytes;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final res = await _inner.send(request);
    final length = res.contentLength;
    if (length != null && length > maxBytes) {
      unawaited(res.stream.listen(null).cancel());
      throw _tooLarge(request.url);
    }
    return http.StreamedResponse(
      _capped(res.stream, request.url),
      res.statusCode,
      contentLength: length,
      request: res.request,
      headers: res.headers,
      isRedirect: res.isRedirect,
      persistentConnection: res.persistentConnection,
      reasonPhrase: res.reasonPhrase,
    );
  }

  Stream<List<int>> _capped(Stream<List<int>> body, Uri url) async* {
    var total = 0;
    await for (final chunk in body) {
      total += chunk.length;
      // Throwing inside await-for cancels the underlying subscription.
      if (total > maxBytes) throw _tooLarge(url);
      yield chunk;
    }
  }

  http.ClientException _tooLarge(Uri url) =>
      http.ClientException('reply larger than ${maxBytes ~/ (1024 * 1024)} MB', url);

  @override
  void close() => _inner.close();
}
