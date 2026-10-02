import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:http/http.dart' as http;

class DiscoveredDevice {
  const DiscoveredDevice(
      {required this.name, required this.host, this.port = 80, this.mac});

  final String name;
  final String host;
  final int port;
  final String? mac;

  @override
  String toString() => '$name ($host:$port)';
}

/// mDNS discovery of `_wled._tcp` (WLED advertises it with a "mac" TXT
/// record, wled00/wled.cpp). Written against bonsoir 7.x, where resolved
/// services expose `hostAddresses`.
class WledDiscovery {
  static const serviceType = '_wled._tcp';

  final _controller = StreamController<DiscoveredDevice>.broadcast();
  final _seen = <String>{};
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _sub;

  /// Each device once per [start], de-duplicated by host.
  Stream<DiscoveredDevice> get devices => _controller.stream;

  Future<void> start() async {
    await stop();
    _seen.clear();
    final d = BonsoirDiscovery(type: serviceType);
    await d.initialize();
    _sub = d.eventStream?.listen((event) {
      switch (event) {
        case BonsoirDiscoveryServiceFoundEvent(:final service):
          service.resolve(d.serviceResolver);
        case BonsoirDiscoveryServiceResolvedEvent(:final service):
        case BonsoirDiscoveryServiceUpdatedEvent(:final service):
          _emit(service);
        default:
          break;
      }
    }, onError: (Object _) {});
    _discovery = d;
    await d.start();
  }

  void _emit(BonsoirService s) {
    final addrs = s.hostAddresses;
    if (addrs.isEmpty) return;
    // Prefer IPv4: IPv6 link-local addresses need a zone id to be usable.
    final host = addrs.firstWhere((a) => !a.contains(':'),
        orElse: () => addrs.first);
    if (!_seen.add(host) || _controller.isClosed) return;
    _controller.add(DiscoveredDevice(
        name: s.name, host: host, port: s.port, mac: s.attributes['mac']));
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    final d = _discovery;
    _discovery = null;
    if (d != null && !d.isStopped) await d.stop();
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}

/// Confirms [host] is a WLED via /json/info, for manual IP entry.
Future<DiscoveredDevice?> probeHost(String host,
    {Duration timeout = const Duration(seconds: 4), http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final res = await c
        .get(Uri.parse('http://${_authority(host)}/json/info'))
        .timeout(timeout);
    if (res.statusCode != 200) return null;
    final j = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
    if (j is! Map || j['brand'] != 'WLED') return null;
    final mac = j['mac'];
    return DiscoveredDevice(
      name: j['name'] is String ? j['name'] as String : 'WLED',
      host: host,
      mac: mac is String ? mac : null,
    );
  } catch (_) {
    return null;
  } finally {
    if (client == null) c.close();
  }
}

/// Fallback when mDNS is blocked: probes x.x.x.1–254 of [ownIp]'s /24.
/// A cheap TCP connect to port 80 filters hosts before the HTTP probe.
Stream<DiscoveredDevice> scanSubnet(String ownIp,
    {int concurrency = 24,
    Duration timeout = const Duration(milliseconds: 1500)}) {
  final parts = ownIp.split('.');
  if (parts.length != 4) return const Stream.empty();
  final prefix = parts.take(3).join('.');
  final controller = StreamController<DiscoveredDevice>();
  final client = http.Client();
  var next = 1;
  var cancelled = false;

  Future<void> worker() async {
    while (!cancelled && next <= 254) {
      final host = '$prefix.${next++}';
      if (host == ownIp) continue;
      try {
        final s = await Socket.connect(host, 80, timeout: timeout);
        s.destroy();
      } catch (_) {
        continue;
      }
      final d = await probeHost(host, timeout: timeout * 2, client: client);
      if (d != null && !cancelled) controller.add(d);
    }
  }

  controller
    ..onListen = () {
      Future.wait([for (var i = 0; i < concurrency; i++) worker()])
          .whenComplete(() {
        client.close();
        controller.close();
      });
    }
    ..onCancel = () {
      cancelled = true;
    };
  return controller.stream;
}

String _authority(String host) =>
    ':'.allMatches(host).length > 1 && !host.startsWith('[') ? '[$host]' : host;
