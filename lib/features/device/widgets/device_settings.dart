import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../app/devices.dart';
import '../../../ui/design/parts.dart';
import '../../../ui/design/route.dart';
import '../../../ui/design/tokens.dart';
import '../../../ui/design/type.dart';

/// Builds what stands in for the web view. Widget tests have no platform
/// views, so they pass one of these instead.
typedef SettingsViewBuilder = Widget Function(BuildContext context, Uri url);

/// WLED's own setup pages (`http://<host>/settings`), inside Glyph: Wi-Fi,
/// LED wiring, 2D layout, time, security and updates.
class DeviceSettingsPage extends StatefulWidget {
  const DeviceSettingsPage({super.key, required this.host, @visibleForTesting this.viewBuilder});

  final String host;

  /// Replaces the web view (tests only).
  final SettingsViewBuilder? viewBuilder;

  Uri get url => Uri.parse('http://$host/settings');

  /// Opens the settings for the selected device. When the page closes, the
  /// device is read again so changes made there (name, size…) show up. A
  /// save in WLED often restarts it, so a failed read is retried a few times.
  static Future<void> open(
    BuildContext context,
    DeviceStore store, {
    SettingsViewBuilder? viewBuilder,
  }) async {
    final host = store.selected?.host;
    if (host == null) return;
    await Navigator.of(context).push(
      lbRoute<void>(
        (_) => DeviceSettingsPage(host: host, viewBuilder: viewBuilder),
      ),
    );
    await store.refresh();
    for (var i = 0; i < 3 && !store.isConnected && store.selected?.host == host; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (store.selected?.host != host) return;
      await store.refresh();
    }
  }

  @override
  State<DeviceSettingsPage> createState() => _DeviceSettingsPageState();
}

class _DeviceSettingsPageState extends State<DeviceSettingsPage> {
  WebViewController? _web;
  int _progress = 0;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (widget.viewBuilder != null) {
      _progress = 100;
      return;
    }
    final c = WebViewController();
    _web = c;
    unawaited(c.setJavaScriptMode(JavaScriptMode.unrestricted));
    unawaited(c.setBackgroundColor(Lb.ink));
    unawaited(c.setNavigationDelegate(NavigationDelegate(
      onPageStarted: (_) => _set(() => _progress = 0),
      onProgress: (p) => _set(() => _progress = p),
      onPageFinished: (_) => _set(() => _progress = 100),
      onWebResourceError: (e) {
        // Missing images and the like don't matter; only the page itself.
        if (e.isForMainFrame ?? true) _set(() => _failed = true);
      },
    )));
    unawaited(c.loadRequest(widget.url));
  }

  void _set(VoidCallback f) {
    if (mounted) setState(f);
  }

  Future<void> _reload() async {
    final c = _web;
    if (c == null) return;
    if (_failed) {
      setState(() {
        _failed = false;
        _progress = 0;
      });
      // After an error the view holds the browser's error page; start over.
      await c.loadRequest(widget.url);
    } else {
      await c.reload();
    }
  }

  /// Back walks the web page's own history first, then leaves.
  Future<void> _back() async {
    final c = _web;
    if (c != null && !_failed && await c.canGoBack()) {
      await c.goBack();
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final loading = _progress < 100 && !_failed;
    final builder = widget.viewBuilder;
    return PopScope(
      canPop: _web == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_back());
      },
      child: Scaffold(
        backgroundColor: Lb.ink,
        appBar: AppBar(
          backgroundColor: Lb.ink,
          title: const Text('WLED firmware settings'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _web == null ? null : _reload,
              icon: const Icon(Icons.refresh_sharp),
            ),
            IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_sharp),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(2),
            child: SizedBox(
              height: 2,
              child: loading
                  ? LinearProgressIndicator(
                      value: _progress <= 0 ? null : _progress / 100,
                      minHeight: 2,
                      backgroundColor: Colors.transparent,
                    )
                  : const ColoredBox(color: Lb.line),
            ),
          ),
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: builder != null ? builder(context, widget.url) : WebViewWidget(controller: _web!),
            ),
            if (_failed)
              Positioned.fill(
                child: ColoredBox(
                  color: Lb.ink,
                  child: _Unreachable(host: widget.host, onRetry: _reload),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Unreachable extends StatelessWidget {
  const _Unreachable({required this.host, required this.onRetry});

  final String host;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(Lb.gutter, 32, Lb.gutter, 32),
    children: [
      LbPanel(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const MonoLabel('Not reachable'),
            const SizedBox(height: 10),
            Text('Can\'t open your device\'s settings', style: LbType.title),
            const SizedBox(height: 10),
            Text(
              'Check it\'s plugged in and on the same Wi-Fi as your phone. If you just saved '
              'something, it may be restarting — give it a few seconds.',
              style: LbType.body.copyWith(color: Lb.text2),
            ),
            const SizedBox(height: 8),
            Text(host, style: LbType.mono),
            const SizedBox(height: 20),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    ],
  );
}
