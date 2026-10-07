import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../app/background.dart';
import '../../app/creations.dart';
import '../../app/devices.dart';
import '../../app/playback.dart';
import '../../engine/clip.dart';
import '../../engine/generator.dart';
import '../../engine/palette.dart';
import '../../engine/registry.dart';
import '../../library/catalog.dart';
import 'glance_generator.dart';
import 'glance_model.dart';
import 'glance_store.dart';
import 'weather_service.dart';

/// Owns feed/background lifetimes, never render-loop network work.
class GlanceSession extends ChangeNotifier with WidgetsBindingObserver {
  GlanceSession({
    required this.devices,
    required this.playback,
    required this.catalog,
    required this.creations,
    GlanceStore? store,
    WeatherService? weather,
  }) : store = store ?? GlanceStore(),
       weather = weather ?? WeatherService() {
    playback.addListener(_changed);
    devices.addListener(_deviceChanged);
    this.store.addListener(_storeChanged);
    WidgetsBinding.instance.addObserver(this);
  }
  final DeviceStore devices;
  final PlaybackController playback;
  Catalog catalog;
  final CreationsStore creations;
  final GlanceStore store;
  final WeatherService weather;
  Generator? _active;
  int? _selection;
  int _request = 0;
  Object? _backgroundOwner;
  bool _background = false, _disposed = false, _foreground = true;
  String _feedKey = '';
  bool get ownsPlayback =>
      _active != null && identical(playback.generator, _active);
  bool get playing => ownsPlayback && playback.isPlaying;
  bool get background =>
      _background && _backgroundOwner != null && BackgroundStreaming.isRunning;
  bool startingBackground = false;

  Future<void> load() => Future.wait([store.load(), weather.load()]);
  GlanceCardGenerator cardGenerator(GlanceCard card) =>
      GlanceCardGenerator(card, weather);
  PhoneShowGenerator showGenerator(PhoneShow show) =>
      PhoneShowGenerator(show, resolve);
  ShowLook? resolve(PhoneShowEntry entry) {
    switch (entry.kind) {
      case ShowEntryKind.card:
        final card = store.card(entry.id);
        if (card == null) return null;
        final g = cardGenerator(card);
        return ShowLook(
          g,
          available: () => identical(store.card(entry.id), card) && g.available,
        );
      case ShowEntryKind.creation:
        final c = creations.items.where((c) => c.id == entry.id).firstOrNull;
        if (c == null) return null;
        return ShowLook(
          ClipGenerator(c.clip, title: c.title),
          available: () => creations.items.any((v) => v.id == entry.id),
        );
      case ShowEntryKind.library:
        final item = catalog.byId(entry.id);
        final g = item == null ? null : findGenerator(item.generatorId);
        if (g == null || g.liveOnly) return null;
        return ShowLook(
          g,
          params: Params.defaultsFor(g, item!.params),
          palette: paletteById(item.paletteId),
          speed: item.speed ?? 1,
        );
    }
  }

  String entryTitle(PhoneShowEntry e) =>
      switch (e.kind) {
        ShowEntryKind.card => store.card(e.id)?.title,
        ShowEntryKind.library => catalog.byId(e.id)?.title,
        ShowEntryKind.creation =>
          creations.items.where((c) => c.id == e.id).firstOrNull?.title,
      } ??
      'Unavailable';

  Future<bool> start(Generator generator) async {
    if (_disposed ||
        !_foreground ||
        !devices.isConnected ||
        devices.isOn == false) {
      return false;
    }
    final request = ++_request, revision = playback.revision;
    final client = devices.client!,
        selection = devices.selectionGeneration,
        control = devices.controlGeneration,
        target = devices.selected!,
        caps = devices.caps!;
    if (playback.isStreaming &&
        !playback.streamingHosts.contains(target.host)) {
      await playback.stopStreaming();
    }
    if (_disposed ||
        request != _request ||
        playback.revision != revision ||
        !devices.isCurrent(client, selection) ||
        control != devices.controlGeneration ||
        !devices.isConnected ||
        devices.isOn == false) {
      return false;
    }
    await setBackground(false);
    if (_disposed ||
        request != _request ||
        playback.revision != revision ||
        !devices.isCurrent(client, selection) ||
        control != devices.controlGeneration ||
        !devices.isConnected ||
        devices.isOn == false) {
      return false;
    }
    playback.resize(caps.width, caps.height);
    _active = generator;
    _selection = selection;
    _feedKey = '';
    playback.playGenerator(generator);
    bool current() =>
        !_disposed &&
        request == _request &&
        identical(playback.generator, generator) &&
        ownsPlayback &&
        playback.isPlaying &&
        devices.isCurrent(client, selection) &&
        devices.controlGeneration == control &&
        devices.isOn != false;
    try {
      if (!playback.isStreaming) {
        await client.prepareStream();
        if (!current()) {
          if (request == _request && identical(playback.generator, generator)) {
            await stop();
          }
          return false;
        }
        await playback.startStreaming(target.host, target.layout);
        if (!current()) {
          // A newer request owns its stream; only stop if this generator still owns it.
          if (request == _request && identical(playback.generator, generator)) {
            await stop();
          }
          return false;
        }
      }
      return current();
    } catch (_) {
      if (request == _request && identical(playback.generator, generator)) {
        await stop();
      }
      return false;
    }
  }

  Future<void> stop() async {
    if (_disposed) return;
    ++_request;
    if (!ownsPlayback) return;
    final sameSelection = _selection == devices.selectionGeneration;
    final client = devices.client,
        selection = devices.selectionGeneration,
        control = devices.controlGeneration;
    final closed = playback.stopStreaming();
    playback.pause();
    final revision = playback.revision;
    await closed;
    // New playback/control may have taken over during socket/service cleanup.
    if (!_disposed &&
        sameSelection &&
        client != null &&
        devices.isCurrent(client, selection) &&
        control == devices.controlGeneration &&
        revision == playback.revision &&
        !playback.isStreaming) {
      try {
        await client.exitLive();
        if (!_disposed &&
            devices.isCurrent(client, selection) &&
            control == devices.controlGeneration &&
            revision == playback.revision &&
            !playback.isStreaming) {
          await devices.exitLiveMirrors();
        }
      } catch (_) {}
    }
  }

  Future<bool> setBackground(bool value) async {
    if (!value) {
      _background = false;
      final owner = _backgroundOwner;
      _backgroundOwner = null;
      if (owner != null) {
        await BackgroundStreaming.release(owner).catchError((Object _) {});
      }
      if (!_foreground && playing) await stop();
      if (!_disposed) notifyListeners();
      return true;
    }
    if (!playing ||
        !playback.isStreaming ||
        startingBackground ||
        !BackgroundStreaming.supported) {
      return false;
    }
    final owner = Object();
    _backgroundOwner = owner;
    _background = true;
    startingBackground = true;
    notifyListeners();
    var ok = false;
    try {
      ok = await BackgroundStreaming.retain(
        owner,
        () {
          unawaited(stop());
        },
        title: 'Glyph · ${_active!.name}',
        text: 'Live cards and rotation · tap to open',
      );
    } catch (_) {
      // A refused foreground service must not leave a hidden live session.
    }
    startingBackground = false;
    if (_disposed ||
        !identical(_backgroundOwner, owner) ||
        !playing ||
        !playback.isStreaming ||
        !ok) {
      await BackgroundStreaming.release(owner).catchError((Object _) {});
      if (identical(_backgroundOwner, owner)) {
        _backgroundOwner = null;
        _background = false;
      }
      if (!_disposed && !_foreground && playing) await stop();
      if (!_disposed) notifyListeners();
      return false;
    }
    if (!_disposed) notifyListeners();
    return true;
  }

  void _changed() {
    if (_disposed) return;
    if (!playing) {
      weather.release(this);
      _feedKey = '';
      final owner = _backgroundOwner;
      _backgroundOwner = null;
      _background = false;
      if (owner != null) {
        unawaited(BackgroundStreaming.release(owner).catchError((Object _) {}));
      }
      if (!ownsPlayback) {
        _active = null;
        _selection = null;
      }
    } else {
      _watchFeeds();
    }
    notifyListeners();
  }

  void _watchFeeds() {
    final g = _active;
    final cards = g is GlanceCardGenerator
        ? [g.card]
        : g is PhoneShowGenerator
        ? [
            for (final e in g.show.entries)
              if (e.kind == ShowEntryKind.card && store.card(e.id) != null)
                store.card(e.id)!,
          ]
        : <GlanceCard>[];
    final places = [
      for (final c in cards)
        if (c.kind == GlanceKind.weather) c.place!,
    ];
    final key = places.map((p) => p.key).join('|');
    if (key == _feedKey) return;
    _feedKey = key;
    weather.watch(this, places);
  }

  void _storeChanged() {
    if (playing) _watchFeeds();
    if (!_disposed) notifyListeners();
  }

  void _deviceChanged() {
    if (!playing) return;
    if (_selection != devices.selectionGeneration ||
        !devices.isConnected ||
        devices.isOn == false) {
      unawaited(stop());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _foreground = true;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _foreground = false;
    }
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden ||
            state == AppLifecycleState.detached) &&
        !background &&
        !startingBackground &&
        playing) {
      unawaited(stop());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    playback.removeListener(_changed);
    devices.removeListener(_deviceChanged);
    store.removeListener(_storeChanged);
    weather.release(this);
    final owner = _backgroundOwner;
    if (owner != null) {
      unawaited(BackgroundStreaming.release(owner).catchError((Object _) {}));
    }
    if (ownsPlayback) {
      unawaited(playback.stopStreaming());
      playback.pause();
    }
    store.dispose();
    weather.dispose();
    super.dispose();
  }
}
