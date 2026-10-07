import 'dart:async';

import 'package:flutter/material.dart';

import '../../engine/frame.dart';
import '../../ui/design/parts.dart';
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

/// Apps people most often want a nudge from, offered first so choosing is a
/// couple of taps rather than a scroll through every installed app.
const suggestedAlertApps = [
  'com.whatsapp',
  'com.whatsapp.w4b',
  'com.google.android.apps.messaging',
  'com.samsung.android.messaging',
  'com.google.android.dialer',
  'com.samsung.android.dialer',
  'org.telegram.messenger',
  'org.thoughtcrime.securesms',
  'com.instagram.android',
  'com.facebook.orca',
  'com.snapchat.android',
  'com.discord',
  'com.Slack',
  'com.microsoft.teams',
  'com.google.android.gm',
  'com.google.android.calendar',
  'com.ringapp',
  'com.google.android.apps.chromecast.app',
];

/// Alerts: a chosen app's logo bounces on the device when it sends a
/// notification, then the display goes back to what it was showing.
///
/// The journey runs top to bottom: see what it looks like, pick the apps,
/// turn it on (one button walks through access → apps → on), try it.
class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key, this.controller});
  final NotificationController? controller;
  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> with WidgetsBindingObserver {
  NotificationController? _controller;
  List<NotificationApp> _apps = [];
  String? _appsError, _focus;
  bool _loading = true, _testing = false;
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
    if (c == null) return setState(() => _loading = false);
    try {
      final apps = await c.service.apps();
      if (!mounted) return;
      setState(() {
        _apps = [...apps]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
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
    // Back from Android's settings: access may have just been granted.
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

  Future<void> _toggleApp(String package, bool on) async {
    await _controller!.setApp(package, on);
    if (on && mounted) setState(() => _focus = package);
  }

  Future<void> _openAccess() async {
    try {
      await _controller!.service.openSettings();
    } catch (_) {
      if (mounted) studioToast(context, 'Couldn\'t open Android settings.');
    }
  }

  Future<void> _test(String package) async {
    final c = _controller!;
    if (!c.devices.isConnected) return goToMatrix(context);
    setState(() => _testing = true);
    try {
      await c.preview(package);
    } catch (_) {
      if (mounted) studioToast(context, 'Couldn\'t show it. Is your device on?');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
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

  String _time(int minute) => TimeOfDay(hour: minute ~/ 60, minute: minute % 60).format(context);

  Future<void> _allApps() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _AllAppsSheet(controller: _controller!, apps: _apps, onToggle: _toggleApp),
      );

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null) return const StudioScaffold(title: 'Alerts', body: SizedBox());
    return StudioScaffold(
      title: 'Alerts',
      body: ListenableBuilder(
        listenable: Listenable.merge([c, c.service, c.devices]),
        builder: (context, _) {
          final chosen = [for (final a in _apps) if (c.settings.packages.contains(a.package)) a];
          final focus = chosen.where((a) => a.package == _focus).firstOrNull ?? chosen.firstOrNull;
          final suggested = [
            for (final p in suggestedAlertApps) ..._apps.where((a) => a.package == p),
            // Anything already chosen that isn't in the suggestions stays visible.
            for (final a in chosen) if (!suggestedAlertApps.contains(a.package)) a,
          ];
          return ListView(
            padding: const EdgeInsets.fromLTRB(Lb.gutter, 4, Lb.gutter, 40),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: c.playback.isAlerting
                      ? LedMatrixView(
                          frame: c.playback.frame,
                          repaint: c.playback.frameTick,
                          glow: true,
                          bezel: true,
                          borderRadius: Lb.rControl,
                        )
                      : focus != null
                          ? _LogoPreview(
                              key: ValueKey(focus.package),
                              service: c.service,
                              package: focus.package,
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
              Center(child: _StatusLine(controller: c)),
              const SizedBox(height: 10),
              Text(
                'When a chosen app sends a notification, its logo pops up on your device for a few seconds — never the message — then it goes back to what was showing.',
                textAlign: TextAlign.center,
                style: LbType.small.copyWith(color: Lb.text2),
              ),
              const SizedBox(height: 20),
              _PrimaryAction(
                controller: c,
                chosen: chosen.length,
                onAccess: _openAccess,
              ),
              if (focus != null) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _testing || c.playback.isAlerting || !c.service.supported ? null : () => _test(focus.package),
                  icon: _testing ? const LedSpinner(size: 16) : const Icon(Icons.play_arrow_sharp, size: 18),
                  label: Text(c.devices.isConnected ? 'Test ${focus.name} on your device' : 'Connect a device to test'),
                ),
              ],
              const SizedBox(height: 28),
              Row(children: [
                const Expanded(child: MonoLabel('Which apps?')),
                if (chosen.isNotEmpty) MonoLabel('${chosen.length} chosen'),
              ]),
              const SizedBox(height: 10),
              if (!c.service.supported)
                LbPanel(child: Text('Alerts need Android: iPhones don\'t share other apps\' notifications.', style: LbType.small))
              else if (_loading)
                const Center(child: Padding(padding: EdgeInsets.all(20), child: LedSpinner()))
              else if (_appsError != null)
                LbPanel(
                  onTap: _loadApps,
                  child: Text('$_appsError Tap to try again.', style: LbType.small),
                )
              else ...[
                if (suggested.isNotEmpty)
                  _AppGrid(
                    service: c.service,
                    apps: suggested,
                    chosen: c.settings.packages,
                    focus: focus?.package,
                    enabled: c.loaded,
                    onTap: (a) {
                      final on = c.settings.packages.contains(a.package);
                      if (on && _focus != a.package) return setState(() => _focus = a.package);
                      _toggleApp(a.package, !on);
                    },
                    onLongPress: (a) => _toggleApp(a.package, !c.settings.packages.contains(a.package)),
                  ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _apps.isEmpty ? null : _allApps,
                  icon: const Icon(Icons.apps_sharp, size: 18),
                  label: Text(suggested.isEmpty ? 'Choose apps' : 'All apps (${_apps.length})'),
                ),
              ],
              const SizedBox(height: 28),
              const MonoLabel('Quiet hours'),
              const SizedBox(height: 10),
              LbPanel(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  LbToggleTile(
                    title: 'Pause alerts overnight',
                    subtitle: c.settings.quiet
                        ? '${_time(c.settings.quietStart)} – ${_time(c.settings.quietEnd)}'
                        : 'Alerts any time',
                    value: c.settings.quiet,
                    onChanged: c.service.supported && c.loaded ? (v) => c.setQuiet(v) : null,
                  ),
                  if (c.settings.quiet)
                    Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _quietTime(true),
                          child: Text('From ${_time(c.settings.quietStart)}'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _quietTime(false),
                          child: Text('Until ${_time(c.settings.quietEnd)}'),
                        ),
                      ),
                    ]),
                ]),
              ),
              const SizedBox(height: 20),
              Text(
                'Alerts run from your phone, so it needs to stay on your device\'s Wi-Fi with Glyph open or in the background. '
                'They wait while you draw, play a game or send something.',
                style: LbType.small.copyWith(color: Lb.text3),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// "On · listening" with a live LED, or why it isn't.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.controller});
  final NotificationController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final (text, live) = !c.service.supported
        ? ('Android only', false)
        : c.starting
            ? ('Starting…', false)
            : !c.monitoring
                ? ('Off', false)
                : !c.service.connected
                    ? ('Waiting for Android', false)
                    : !c.devices.isConnected
                        ? ('On · waiting for your device', false)
                        : c.devices.isOn == false
                            ? ('On · device is off', false)
                            : c.settings.isQuiet(DateTime.now())
                                ? ('On · quiet hours', false)
                                : ('On · listening', true);
    if (live) return LivePulse(label: text);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      StatusDot(on: c.monitoring, size: 7),
      const SizedBox(width: 8),
      MonoLabel(text),
    ]);
  }
}

/// One button that always says the next step: allow access, pick an app,
/// turn on, or turn off.
class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({required this.controller, required this.chosen, required this.onAccess});
  final NotificationController controller;
  final int chosen;
  final VoidCallback onAccess;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    const tall = Size.fromHeight(52);
    if (!c.service.supported) {
      return const FilledButton(onPressed: null, child: Text('Android only for now'));
    }
    if (!c.service.access) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: tall),
          onPressed: onAccess,
          child: const Text('Allow notification access'),
        ),
        const SizedBox(height: 6),
        Text(
          'Android asks once. Glyph only sees which app sent something, never what it says.',
          textAlign: TextAlign.center,
          style: LbType.small.copyWith(color: Lb.text3),
        ),
      ]);
    }
    if (c.monitoring || c.starting) {
      return OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: tall),
        onPressed: c.loaded && !c.starting ? () => c.setMonitoring(false) : null,
        icon: const Icon(Icons.stop_sharp, size: 18),
        label: const Text('Turn off alerts'),
      );
    }
    return FilledButton(
      style: FilledButton.styleFrom(minimumSize: tall),
      onPressed: chosen == 0 || !c.loaded ? null : () => c.setMonitoring(true),
      child: Text(chosen == 0 ? 'Pick an app below first' : 'Turn on alerts'),
    );
  }
}

/// Square tiles showing each app's logo the way the LEDs will draw it.
/// Tap chooses (and previews); tap a chosen one again to preview it; hold
/// to toggle.
class _AppGrid extends StatelessWidget {
  const _AppGrid({
    required this.service,
    required this.apps,
    required this.chosen,
    required this.focus,
    required this.enabled,
    required this.onTap,
    required this.onLongPress,
  });
  final NotificationService service;
  final List<NotificationApp> apps;
  final Set<String> chosen;
  final String? focus;
  final bool enabled;
  final void Function(NotificationApp) onTap, onLongPress;

  @override
  Widget build(BuildContext context) {
    final accent = readAccent(context);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 92,
        mainAxisSpacing: 12,
        crossAxisSpacing: 10,
        childAspectRatio: 0.78,
      ),
      itemCount: apps.length,
      itemBuilder: (context, i) {
        final a = apps[i];
        final on = chosen.contains(a.package);
        return Semantics(
          button: true,
          selected: on,
          label: '${a.name}${on ? ', chosen' : ''}',
          excludeSemantics: true,
          child: GestureDetector(
            onTap: enabled ? () => onTap(a) : null,
            onLongPress: enabled ? () => onLongPress(a) : null,
            child: Column(children: [
              Expanded(
                child: AnimatedContainer(
                  duration: Lb.fast,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: on ? accent.withValues(alpha: 0.10) : Lb.panel,
                    borderRadius: BorderRadius.circular(Lb.rControl),
                    border: Border.all(color: on ? accent : Lb.line, width: on && focus == a.package ? 2 : 1),
                  ),
                  child: Stack(fit: StackFit.expand, children: [
                    Opacity(opacity: on ? 1 : 0.55, child: _AppIcon(service: service, package: a.package)),
                    if (on)
                      Positioned(
                        right: 2,
                        top: 2,
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
                        ),
                      ),
                  ]),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                a.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: LbType.small.copyWith(color: on ? Lb.text : Lb.text2),
              ),
            ]),
          ),
        );
      },
    );
  }
}

class _AllAppsSheet extends StatefulWidget {
  const _AllAppsSheet({required this.controller, required this.apps, required this.onToggle});
  final NotificationController controller;
  final List<NotificationApp> apps;
  final Future<void> Function(String, bool) onToggle;
  @override
  State<_AllAppsSheet> createState() => _AllAppsSheetState();
}

class _AllAppsSheetState extends State<_AllAppsSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final chosen = c.settings.packages;
          final q = _query.toLowerCase();
          final apps = [
            for (final a in widget.apps)
              if (q.isEmpty || a.name.toLowerCase().contains(q) || a.package.toLowerCase().contains(q)) a,
          ]..sort((a, b) {
              final ca = chosen.contains(a.package), cb = chosen.contains(b.package);
              return ca == cb ? 0 : (ca ? -1 : 1);
            });
          return ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(Lb.gutter, 0, Lb.gutter, 24),
            children: [
              Text('All apps', style: LbType.title),
              const SizedBox(height: 12),
              TextField(
                autofocus: false,
                decoration: const InputDecoration(hintText: 'Search apps', prefixIcon: Icon(Icons.search_sharp)),
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
              const SizedBox(height: 8),
              if (apps.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text('No apps match.', style: LbType.small)),
              for (final a in apps)
                LbToggleTile(
                  key: ValueKey(a.package),
                  title: a.name,
                  leading: SizedBox.square(dimension: 36, child: _AppIcon(service: c.service, package: a.package)),
                  value: chosen.contains(a.package),
                  onChanged: c.loaded ? (v) => widget.onToggle(a.package, v) : null,
                ),
            ],
          );
        },
      ),
    );
  }
}

/// An app's logo as LED dots — what the device will actually show.
class _AppIcon extends StatefulWidget {
  const _AppIcon({required this.service, required this.package});
  final NotificationService service;
  final String package;
  @override
  State<_AppIcon> createState() => _AppIconState();
}

class _AppIconState extends State<_AppIcon> {
  late final Future<NotificationLogo> _icon =
      widget.service.icon(widget.package).catchError((_) => NotificationLogo.fallback);

  @override
  Widget build(BuildContext context) => FutureBuilder<NotificationLogo>(
        future: _icon,
        builder: (context, snapshot) {
          final logo = snapshot.data ?? NotificationLogo.fallback;
          return LedMatrixView(
            frame: Frame(32, 32)..rgb.setAll(0, logo.rgb),
            borderRadius: Lb.rTile,
          );
        },
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
  late final _icon = widget.service.icon(widget.package).catchError((_) => NotificationLogo.fallback);
  @override
  Widget build(BuildContext context) => FutureBuilder<NotificationLogo>(
        future: _icon,
        builder: (context, snapshot) => LedLoop(
          key: ValueKey(snapshot.data),
          generator: NotificationLogoGenerator(snapshot.data ?? NotificationLogo.fallback),
          width: widget.width,
          height: widget.height,
          glow: true,
          bezel: true,
          borderRadius: Lb.rControl,
        ),
      );
}
