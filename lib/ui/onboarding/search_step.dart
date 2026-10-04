import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../features/device/widgets/common.dart';
import '../../wled/discovery.dart';
import '../design/parts.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../scope.dart';

typedef DeviceSource = Stream<DiscoveredDevice> Function();
typedef HostProbe = Future<DiscoveredDevice?> Function(String host);

/// How the search step finds devices. Swappable in tests.
class SetupServices {
  const SetupServices({
    this.discover = mdnsDevices,
    this.scan = subnetDevices,
    this.probe = probeHost,
    this.scanAfter = const Duration(seconds: 4),
    this.helpAfter = const Duration(seconds: 6),
  });

  /// Devices announcing themselves on the network (mDNS).
  final DeviceSource discover;

  /// Fallback that knocks on every address of the local network.
  final DeviceSource scan;

  /// Checks one typed-in address.
  final HostProbe probe;

  final Duration scanAfter, helpAfter;
}

/// mDNS discovery as a stream that stops when cancelled.
Stream<DiscoveredDevice> mdnsDevices() {
  final d = WledDiscovery();
  StreamSubscription<DiscoveredDevice>? sub;
  late final StreamController<DiscoveredDevice> c;
  c = StreamController<DiscoveredDevice>(
    onListen: () {
      sub = d.devices.listen(c.add);
      d.start().catchError((Object _) {});
    },
    onCancel: () async {
      await sub?.cancel();
      try {
        await d.dispose();
      } catch (_) {}
    },
  );
  return c.stream;
}

/// Probes the phone's own /24 for WLED devices.
Stream<DiscoveredDevice> subnetDevices() async* {
  String? ip;
  try {
    final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    for (final i in ifaces) {
      for (final a in i.addresses) {
        if (!a.isLoopback) ip ??= a.address;
      }
    }
  } catch (_) {}
  if (ip != null) yield* scanSubnet(ip);
}

/// Step 2: a radar sweep while we look; found devices glow as tiles.
class SearchStep extends StatefulWidget {
  const SearchStep({
    super.key,
    required this.services,
    required this.onConnect,
    this.onBack,
    this.title = 'Looking for your device',
  });

  final SetupServices services;

  /// Connects; returns an error message, or null when it worked.
  final Future<String?> Function(DiscoveredDevice d) onConnect;
  final VoidCallback? onBack;
  final String title;

  @override
  State<SearchStep> createState() => _SearchStepState();
}

enum _Phase { listening, scanning, done }

class _SearchStepState extends State<SearchStep> with SingleTickerProviderStateMixin {
  late final _sweep = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))
    ..repeat();
  final _found = <String, DiscoveredDevice>{};
  final _subs = <StreamSubscription<DiscoveredDevice>>[];
  Timer? _scanTimer, _helpTimer;
  _Phase _phase = _Phase.listening;
  bool _help = false;
  String? _connecting;
  String? _error;

  @override
  void initState() {
    super.initState();
    _listen(widget.services.discover());
    _scanTimer = Timer(widget.services.scanAfter, _startScan);
    _helpTimer = Timer(widget.services.helpAfter, () {
      if (mounted) setState(() => _help = true);
    });
  }

  void _listen(Stream<DiscoveredDevice> s, {VoidCallback? onDone}) {
    _subs.add(s.listen(_add, onError: (Object _) {}, onDone: onDone));
  }

  void _startScan() {
    if (!mounted) return;
    setState(() => _phase = _Phase.scanning);
    _listen(widget.services.scan(), onDone: () {
      if (mounted) setState(() => _phase = _Phase.done);
    });
  }

  void _add(DiscoveredDevice d) {
    if (!mounted || _found.containsKey(d.host)) return;
    setState(() => _found[d.host] = d);
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _helpTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _sweep.dispose();
    super.dispose();
  }

  Future<void> _connect(DiscoveredDevice d) async {
    if (_connecting != null) return;
    setState(() {
      _connecting = d.host;
      _error = null;
    });
    final err = await widget.onConnect(d);
    if (!mounted) return;
    setState(() {
      _connecting = null;
      _error = err;
    });
  }

  Future<void> _manual() async {
    final d = await showModalBottomSheet<DiscoveredDevice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddressSheet(probe: widget.services.probe),
    );
    if (d == null || !mounted) return;
    _add(d);
    await _connect(d);
  }

  @override
  Widget build(BuildContext context) {
    final saved = {for (final d in AppScope.of(context).devices.saved) d.host};
    final status = switch (_phase) {
      _Phase.listening => 'Listening on your Wi-Fi',
      _Phase.scanning => 'Checking every address on your Wi-Fi',
      _Phase.done => _found.isEmpty ? 'Nothing answered yet' : 'Search finished',
    };
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: widget.onBack == null
              ? const SizedBox(height: 48)
              : IconButton(
                  tooltip: 'Back',
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back_sharp),
                ),
        ),
        const SizedBox(height: 8),
        Text(widget.title, style: LbType.title),
        const SizedBox(height: 8),
        Text('Plug it in and keep your phone on the same Wi-Fi.', style: LbType.small),
        const SizedBox(height: 28),
        Center(
          child: SizedBox.square(
            dimension: 200,
            child: RepaintBoundary(
              child: CustomPaint(painter: RadarPainter(_sweep, blips: _found.keys.toList())),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            StatusDot(on: _phase != _Phase.done, color: Lb.phosphor),
            const SizedBox(width: 8),
            Flexible(child: MonoLabel(status)),
          ],
        ),
        const SizedBox(height: 24),
        for (final d in _found.values)
          Padding(
            key: ValueKey(d.host),
            padding: const EdgeInsets.only(bottom: 10),
            child: FoundTile(
              device: d,
              added: saved.contains(d.host),
              busy: _connecting == d.host,
              onTap: () => _connect(d),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(_error!, style: LbType.small.copyWith(color: Lb.danger)),
          ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: Lb.medium,
          child: _help && _found.isEmpty
              ? _HelpPanel(key: const ValueKey('help'), onAddress: _manual)
              : Center(
                  key: const ValueKey('link'),
                  child: TextButton(onPressed: _manual, child: const Text('Can\'t see it?')),
                ),
        ),
      ],
    );
  }
}

const _tips = [
  'Your phone and device need to be on the same Wi-Fi.',
  'Your device needs WLED 0.14 or newer.',
  'Its address is on your router\'s list of devices, or in the WLED app.',
];

class _HelpPanel extends StatelessWidget {
  const _HelpPanel({super.key, required this.onAddress});

  final VoidCallback onAddress;

  @override
  Widget build(BuildContext context) => LbPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Can\'t see it?', style: LbType.heading),
        const SizedBox(height: 10),
        for (final t in _tips) Note(text: t),
        const SizedBox(height: 4),
        OutlinedButton(onPressed: onAddress, child: const Text('Type its address')),
      ],
    ),
  );
}

/// A device that answered: a small glowing panel, its name and address.
class FoundTile extends StatelessWidget {
  const FoundTile({
    super.key,
    required this.device,
    required this.onTap,
    this.busy = false,
    this.added = false,
  });

  final DiscoveredDevice device;
  final VoidCallback onTap;
  final bool busy;
  final bool added;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: Lb.medium,
    curve: Lb.ease,
    builder: (context, k, child) => Opacity(
      opacity: k,
      child: Transform.translate(offset: Offset(0, 12 * (1 - k)), child: child),
    ),
    child: LbPanel(
      onTap: busy ? null : onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 48,
            child: LedBezel(
              active: true,
              child: DotGlyph(color: Lb.phosphor, seed: device.host.hashCode),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: LbType.heading),
                const SizedBox(height: 2),
                Text(added ? '${device.host} · added' : device.host, style: LbType.mono),
              ],
            ),
          ),
          if (busy)
            const LedSpinner()
          else
            Text('Connect', style: LbType.bodyStrong),
          const SizedBox(width: 4),
        ],
      ),
    ),
  );
}

/// Typing an address by hand, checked before we connect.
class AddressSheet extends StatefulWidget {
  const AddressSheet({super.key, required this.probe});

  final HostProbe probe;

  @override
  State<AddressSheet> createState() => _AddressSheetState();
}

class _AddressSheetState extends State<AddressSheet> {
  final _c = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final host = _c.text.trim().replaceFirst(RegExp(r'^https?://'), '').replaceAll(RegExp(r'/+$'), '');
    if (host.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final d = await widget.probe(host);
    if (!mounted) return;
    if (d == null) {
      setState(() {
        _busy = false;
        _error = 'Nothing answered at $host. Check the number and that it\'s switched on.';
      });
      return;
    }
    Navigator.pop(context, d);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Lb.gutter, 0, Lb.gutter, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetTitle('Type its address', subtitle: 'Four numbers with dots, like 192.168.1.50.'),
            TextField(
              controller: _c,
              autofocus: true,
              keyboardType: TextInputType.url,
              style: LbType.body,
              decoration: const InputDecoration(hintText: '192.168.1.50'),
              onSubmitted: (_) => _go(),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: LbType.small.copyWith(color: Lb.danger)),
              ),
            const SizedBox(height: 14),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _busy ? null : _go,
              child: Text(_busy ? 'Checking…' : 'Connect'),
            ),
            const SizedBox(height: 18),
            for (final t in _tips) Note(text: t),
          ],
        ),
      ),
    ),
  );
}

/// A slow radar sweep drawn as LED dots; found devices show as blips.
class RadarPainter extends CustomPainter {
  RadarPainter(this.t, {this.blips = const []}) : super(repaint: t);

  final Animation<double> t;
  final List<String> blips;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    const n = 19;
    final cell = size.shortestSide / n;
    final r = cell * 0.34;
    final sweep = t.value * 2 * pi;
    final p = Paint();
    final blipCells = <(int, int)>{
      for (final b in blips) _blipCell(b, n),
    };
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final o = Offset((x + 0.5) * cell, (y + 0.5) * cell);
        final v = o - c;
        final d = v.distance / radius;
        if (d > 1.0) continue;
        var a = atan2(v.dy, v.dx);
        if (a < 0) a += 2 * pi;
        final behind = (sweep - a) % (2 * pi);
        var k = exp(-behind * 2.4) * (1 - d * 0.35);
        final ring = (d * 3 - (d * 3).roundToDouble()).abs();
        if (ring < 0.12 && d > 0.2) k = max(k, 0.12);
        if (d < 0.06) k = 0.9;
        if (blipCells.contains((x, y))) {
          p.color = Lb.ok;
          canvas.drawCircle(o, r * 1.25, p..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
          p.maskFilter = null;
          canvas.drawCircle(o, r, p);
          continue;
        }
        p.color = k < 0.06 ? Lb.ledOff : Color.lerp(Lb.ledOff, Lb.phosphor, k.clamp(0, 1))!;
        canvas.drawCircle(o, r, p);
      }
    }
  }

  static (int, int) _blipCell(String host, int n) {
    final h = host.codeUnits.fold<int>(7, (a, b) => (a * 31 + b) & 0x7fffffff);
    final a = (h % 360) * pi / 180;
    final d = 0.35 + (h ~/ 360 % 50) / 100;
    final mid = (n - 1) / 2;
    return ((mid + cos(a) * d * mid).round(), (mid + sin(a) * d * mid).round());
  }

  @override
  bool shouldRepaint(RadarPainter old) => !listEquals(old.blips, blips);
}
