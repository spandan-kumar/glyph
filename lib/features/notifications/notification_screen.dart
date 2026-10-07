import 'dart:async';

import 'package:flutter/material.dart';

import '../../engine/frame.dart';
import '../../ui/design/toggle.dart';
import '../../ui/design/tokens.dart';
import '../../ui/design/type.dart';
import '../../ui/make/led_loop.dart';
import '../../ui/make/studio_kit.dart';
import '../../ui/scope.dart';
import '../../ui/widgets/led_matrix_view.dart';
import 'notification_controller.dart';
import 'notification_logo.dart';
import 'notification_service.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key, this.controller});
  final NotificationController? controller;
  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen>
    with WidgetsBindingObserver {
  NotificationController? _controller;
  List<NotificationApp> _apps = [];
  String _search = '';
  String? _appsError, _preview;
  bool _loading = true;
  final _demo = NotificationLogoGenerator(NotificationLogo.fallback);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    _controller = widget.controller ?? AppScope.of(context).notifications;
    unawaited(_loadApps());
  }

  Future<void> _loadApps() async {
    final c = _controller;
    if (c == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final apps = await c.service.apps();
      if (!mounted) return;
      setState(() {
        _apps = apps;
        _loading = false;
        _appsError = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _appsError = 'Couldn\'t load your apps.';
          _loading = false;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller?.service.refresh();
      unawaited(_loadApps());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _quietTime(bool start) async {
    final c = _controller!;
    final minute = start ? c.settings.quietStart : c.settings.quietEnd;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
    );
    if (time == null || !mounted) return;
    await c.setQuiet(
      c.settings.quiet,
      start: start ? time.hour * 60 + time.minute : null,
      end: start ? null : time.hour * 60 + time.minute,
    );
  }

  String _time(int minute) =>
      TimeOfDay(hour: minute ~/ 60, minute: minute % 60).format(context);

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null) {
      return const StudioScaffold(title: 'Notifications', body: SizedBox());
    }
    return StudioScaffold(
      title: 'Notifications',
      body: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final supported = c.service.supported;
          final status = !supported
              ? 'Android only for now'
              : c.starting
              ? 'Starting…'
              : !c.monitoring
              ? 'Off — start when you\'re ready'
              : !c.service.connected
              ? 'Waiting for Android to connect'
              : !c.devices.isConnected
              ? 'Waiting for your device'
              : c.devices.isOn == false
              ? 'Device is off'
              : c.settings.isQuiet(DateTime.now())
              ? 'Quiet hours — alerts paused'
              : 'Listening for your selected apps';
          final apps = _apps
              .where(
                (a) =>
                    a.name.toLowerCase().contains(_search) ||
                    a.package.toLowerCase().contains(_search),
              )
              .toList();
          final chosen = _apps
              .where((a) => c.settings.packages.contains(a.package))
              .toList();
          final preview =
              chosen.where((a) => a.package == _preview).firstOrNull ??
              chosen.firstOrNull;
          return ListView(
            padding: const EdgeInsets.fromLTRB(Lb.gutter, 4, Lb.gutter, 32),
            children: [
              Center(
                child: SizedBox(
                  width: 200,
                  child: c.playback.isAlerting
                      ? LedMatrixView(
                          frame: c.playback.frame,
                          repaint: c.playback.frameTick,
                          glow: true,
                          bezel: true,
                          borderRadius: Lb.rControl,
                        )
                      : preview != null
                      ? _LogoPreview(
                          key: ValueKey(preview.package),
                          service: c.service,
                          package: preview.package,
                          width: c.playback.frame.width,
                          height: c.playback.frame.height,
                        )
                      : LedLoop(
                          generator: _demo,
                          width: c.playback.frame.width,
                          height: c.playback.frame.height,
                          glow: true,
                          bezel: true,
                          borderRadius: Lb.rControl,
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Text('A little nudge', style: LbType.heading),
              const SizedBox(height: 6),
              Text(
                'An app logo bounces for four seconds, then your display returns to what was playing. No message text.',
                style: LbType.body,
              ),
              const SizedBox(height: 18),
              StudioGroup(
                label: 'Monitoring',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LbToggleTile(
                      title: 'Notification alerts',
                      subtitle: status,
                      value: c.monitoring || c.starting,
                      onChanged: supported && c.loaded
                          ? (v) => c.setMonitoring(v)
                          : null,
                    ),
                    Text(
                      'Your phone needs to stay on the device\'s Wi-Fi. Closing Glyph from recent apps ends monitoring; start it here again next time.',
                      style: LbType.small,
                    ),
                    if (supported && !c.service.access) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Android notification access is shared with Now Playing. Glyph only uses selected apps\' logos for alerts.',
                        style: LbType.small,
                      ),
                      OutlinedButton(
                        onPressed: () async {
                          try {
                            await c.service.openSettings();
                          } catch (_) {
                            if (context.mounted) {
                              studioToast(
                                context,
                                'Couldn\'t open Android settings.',
                              );
                            }
                          }
                        },
                        child: const Text('Allow notification access'),
                      ),
                    ],
                    if (c.error != null)
                      Text(
                        c.error!,
                        style: LbType.small.copyWith(color: Lb.danger),
                      ),
                  ],
                ),
              ),
              StudioGroup(
                label: 'Quiet hours',
                child: Column(
                  children: [
                    LbToggleTile(
                      title: 'Pause alerts overnight',
                      value: c.settings.quiet,
                      onChanged: supported && c.loaded
                          ? (v) => c.setQuiet(v)
                          : null,
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: c.settings.quiet
                                ? () => _quietTime(true)
                                : null,
                            child: Text('From ${_time(c.settings.quietStart)}'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: c.settings.quiet
                                ? () => _quietTime(false)
                                : null,
                            child: Text('Until ${_time(c.settings.quietEnd)}'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (chosen.isNotEmpty)
                StudioGroup(
                  label: 'Try a logo',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButton<String>(
                        isExpanded: true,
                        value: preview?.package,
                        items: [
                          for (final a in chosen)
                            DropdownMenuItem(
                              value: a.package,
                              child: Text(a.name),
                            ),
                        ],
                        onChanged: (v) => setState(() => _preview = v),
                      ),
                      OutlinedButton.icon(
                        onPressed: c.canShow && preview != null
                            ? () async {
                                try {
                                  await c.preview(preview.package);
                                } catch (_) {
                                  if (context.mounted) {
                                    studioToast(
                                      context,
                                      'Couldn\'t load this app\'s logo.',
                                    );
                                  }
                                }
                              }
                            : null,
                        icon: const Icon(Icons.play_arrow_sharp),
                        label: const Text('Preview on device'),
                      ),
                      if (!c.devices.isConnected)
                        TextButton(
                          onPressed: () => goToMatrix(context),
                          child: const Text('Connect a device'),
                        ),
                    ],
                  ),
                ),
              StudioGroup(
                label: 'Apps · ${c.settings.packages.length} selected',
                child: Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search apps',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (v) =>
                          setState(() => _search = v.trim().toLowerCase()),
                    ),
                    const SizedBox(height: 8),
                    if (_loading)
                      Text('Loading apps…', style: LbType.small)
                    else if (_appsError != null)
                      TextButton(
                        onPressed: _loadApps,
                        child: Text('$_appsError Retry'),
                      )
                    else if (apps.isEmpty)
                      Text(
                        supported ? 'No matching apps.' : 'Other apps\' notifications aren\'t available on iPhone.',
                        style: LbType.small,
                      ),
                    for (final a in apps)
                      LbToggleTile(
                        key: ValueKey(a.package),
                        title: a.name,
                        leading: _AppIcon(
                          service: c.service,
                          package: a.package,
                        ),
                        value: c.settings.packages.contains(a.package),
                        onChanged: c.loaded
                            ? (v) => c.setApp(a.package, v)
                            : null,
                      ),
                  ],
                ),
              ),
              Text(
                'Ongoing activity, music controls and grouped summaries are skipped. Alerts pause while you make, play games or Send. Only the selected device gets the logo.',
                style: LbType.small,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AppIcon extends StatefulWidget {
  const _AppIcon({required this.service, required this.package});
  final NotificationService service;
  final String package;
  @override
  State<_AppIcon> createState() => _AppIconState();
}

class _AppIconState extends State<_AppIcon> {
  late final Future<NotificationLogo> _icon = widget.service.icon(
    widget.package,
  );
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 32,
    child: FutureBuilder<NotificationLogo>(
      future: _icon,
      builder: (context, snapshot) {
        final logo = snapshot.data ?? NotificationLogo.fallback;
        return LedMatrixView(
          frame: Frame(32, 32)..rgb.setAll(0, logo.rgb),
          borderRadius: Lb.rControl,
        );
      },
    ),
  );
}

class _LogoPreview extends StatefulWidget {
  const _LogoPreview({
    super.key,
    required this.service,
    required this.package,
    required this.width,
    required this.height,
  });
  final NotificationService service;
  final String package;
  final int width, height;
  @override
  State<_LogoPreview> createState() => _LogoPreviewState();
}

class _LogoPreviewState extends State<_LogoPreview> {
  late final _icon = widget.service
      .icon(widget.package)
      .catchError((_) => NotificationLogo.fallback);
  @override
  Widget build(BuildContext context) => FutureBuilder<NotificationLogo>(
    future: _icon,
    builder: (context, snapshot) => LedLoop(
      key: ValueKey(snapshot.data),
      generator: NotificationLogoGenerator(
        snapshot.data ?? NotificationLogo.fallback,
      ),
      width: widget.width,
      height: widget.height,
      glow: true,
      bezel: true,
      borderRadius: Lb.rControl,
    ),
  );
}
