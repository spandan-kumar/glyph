import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../app/devices.dart';
import '../../../app/playback.dart';
import '../../../engine/frame.dart';
import '../../../engine/setup_frames.dart';
import '../../../ui/onboarding/search_step.dart' show SetupServices;
import '../../../wled/discovery.dart';
import '../../../wled/layout.dart';
import '../../../wled/panel_grid.dart';
import '../../../wled/panel_setup.dart';
import '../../../wled/device.dart' show WledInfo;
import '../../../wled/wled_client.dart';
import '../../../wled/timezone.dart';
import '../device_time.dart';
import 'setup_session.dart';
import 'setup_store.dart';
import 'setup_wifi.dart';

/// Where the wizard starts: a device that isn't on the Wi-Fi yet or isn't
/// known to Glyph, or the selected device (Device, Set up display).
enum SetupEntry { newDevice, existing }

enum SetupStep {
  connect,
  search,
  join,
  wifi,
  joining,
  joinFailed,
  check,
  pin,
  unsupported,
  panelsChoice,
  size,
  grid,
  orderQ1,
  orderQ2,
  orderQ3,
  orderResult,
  orderManual,
  wiringQ1,
  wiringQ2,
  wiringQ3,
  wiringResult,
  wiringManual,
  orientation,
  review,
  applying,
  applyFailed,
  look,
  done,
}

/// What the Joining screen is doing.
enum JoinPhase { sending, searching }

/// The rows of the Applying screen, in order.
enum ApplyPhase { backup, leds, layout, verify }

typedef SetupClientFactory = WledClient Function(String host);

/// The sizes drawn as tiles on the Size screen.
const commonSizes = <(int, int)>[(8, 8), (16, 16), (32, 8), (8, 32), (32, 32), (16, 32)];

const _maxSide = 128;

bool _isTest(SetupStep s) => switch (s) {
  SetupStep.wiringQ1 ||
  SetupStep.wiringQ2 ||
  SetupStep.wiringQ3 ||
  SetupStep.orderQ1 ||
  SetupStep.orderQ2 ||
  SetupStep.orderQ3 ||
  SetupStep.orientation => true,
  _ => false,
};

/// The panel presets of the grid screen: the common ones, then "Other".
const panelSizes = <(int, int)>[(8, 8), (16, 16), (32, 8), (8, 32)];

/// Most panels across or down.
const maxGridSide = 8;

String _normMac(String? m) => (m ?? '').toLowerCase().replaceAll(RegExp(r'[^0-9a-f]'), '');

/// The flow state machine of the device setup wizard.
///
/// Every write to a device happens here. Async work is guarded by
/// generations: a result that arrives after the person went Back or closed
/// the wizard is dropped. The device is never left in a test state: the test
/// session and the realtime-map override are undone on every way out (Back
/// out of a test step, Close, dispose, the app going to the background).
class SetupController extends ChangeNotifier with WidgetsBindingObserver {
  SetupController({
    required this.devices,
    required this.playback,
    required this.wifi,
    required this.store,
    this.entry = SetupEntry.newDevice,
    this.services = const SetupServices(),
    SetupClientFactory? clientFactory,
    this._senderFactory,
    Future<void> Function(Duration)? delay,
    this.findTimeout = const Duration(seconds: 75),
    this.findScanAfter = const Duration(seconds: 8),
    this.findRescanGap = const Duration(seconds: 3),
    this.chaseEvery = const Duration(milliseconds: 300),
    this.guidedPoll = const Duration(seconds: 2),
    this.settle = SetupStore.busSettle,
    this.setupHost = '4.3.2.1',
  }) : _factory = clientFactory ?? ((h) => WledClient(h)),
       _delay = delay ?? Future<void>.delayed {
    _step = entry == SetupEntry.existing ? SetupStep.check : SetupStep.connect;
    WidgetsBinding.instance.addObserver(this);
  }

  final DeviceStore devices;
  final PlaybackController playback;
  final SetupWifi wifi;
  final SetupStore store;
  final SetupEntry entry;
  final SetupServices services;
  final Duration findTimeout, findScanAfter, findRescanGap, chaseEvery, guidedPoll, settle;
  final String setupHost;
  final SetupClientFactory _factory;
  final SetupSenderFactory? _senderFactory;
  final Future<void> Function(Duration) _delay;

  // --- Flow ---------------------------------------------------------------

  late SetupStep _step;
  int _dir = 1;
  int _gen = 0;
  bool _disposed = false, _cleaned = false, _resumed = true;

  SetupStep get step => _step;

  /// +1 moving forward, -1 going back (the direction steps slide).
  int get direction => _dir;
  bool get isNewDevice => entry == SetupEntry.newDevice;

  /// Set by the host from the system's reduced-motion setting.
  bool reduceMotion = false;

  /// The Check step's chapter and Close button start here.
  bool get canClose => _step.index >= SetupStep.check.index && _step != SetupStep.applying && _step != SetupStep.done;

  /// Something on the device changed and the person hasn't confirmed it yet.
  bool get needsDecision => wrote && !confirmed;

  /// A hardware write happened in this run.
  bool wrote = false;

  /// "It matches" was tapped.
  bool confirmed = false;

  /// The device was already set up and went straight to the Look step.
  bool fastPath = false;

  void begin() {
    if (_step == SetupStep.check) {
      host = devices.selected?.host;
      unawaited(_runCheck());
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _go(SetupStep s, {int dir = 1}) {
    final from = _step;
    _gen++;
    _dir = dir;
    _step = s;
    _leave(from, s);
    _enter(s);
    _notify();
  }

  void _leave(SetupStep from, SetupStep to) {
    _stopGuided();
    _cancelFind?.call();
    _cancelFind = null;
    if ((_isTest(from) && !_isTest(to)) || (from == SetupStep.look && to != SetupStep.look)) {
      unawaited(_endTest());
    }
    if (from == SetupStep.wiringQ1 || from == SetupStep.orderQ1) wiringNote = null;
  }

  void _enter(SetupStep s) {
    switch (s) {
      case SetupStep.connect || SetupStep.search:
        // Back from the device's own network: the phone goes back to normal.
        unawaited(wifi.release().catchError((Object _) {}));
      case SetupStep.join:
        if (showGuided) _startGuided();
      case SetupStep.wifi:
        unawaited(scan());
      case SetupStep.check:
        unawaited(_runCheck());
      case SetupStep.wiringQ1 ||
          SetupStep.wiringQ2 ||
          SetupStep.wiringQ3 ||
          SetupStep.orderQ1 ||
          SetupStep.orderQ2 ||
          SetupStep.orderQ3 ||
          SetupStep.orientation:
        unawaited(_prepareTest());
      case SetupStep.look:
        unawaited(_startLook());
      default:
        break;
    }
  }

  /// Back one step. False means there is nothing earlier: the host should
  /// leave the wizard (asking first when [needsDecision]).
  bool back() {
    final root = entry == SetupEntry.existing ? null : SetupStep.connect;
    final to = switch (_step) {
      SetupStep.connect => null,
      SetupStep.search || SetupStep.join => SetupStep.connect,
      SetupStep.wifi || SetupStep.joining || SetupStep.joinFailed => SetupStep.join,
      SetupStep.check || SetupStep.pin || SetupStep.unsupported || SetupStep.panelsChoice => root,
      SetupStep.size || SetupStep.grid => _fromChoice ? SetupStep.panelsChoice : root,
      SetupStep.orderQ1 => SetupStep.grid,
      SetupStep.orderQ2 => SetupStep.orderQ1,
      SetupStep.orderQ3 => SetupStep.orderQ2,
      SetupStep.orderResult => _lastOrderQuestion,
      SetupStep.orderManual => SetupStep.orderResult,
      SetupStep.wiringQ1 => isGrid ? SetupStep.orderResult : SetupStep.size,
      SetupStep.wiringQ2 => SetupStep.wiringQ1,
      SetupStep.wiringQ3 => SetupStep.wiringQ2,
      SetupStep.wiringResult => _lastQuestion,
      SetupStep.wiringManual => SetupStep.wiringResult,
      SetupStep.orientation => SetupStep.wiringResult,
      SetupStep.review => isGrid ? SetupStep.orientation : SetupStep.wiringResult,
      SetupStep.applying || SetupStep.done => _step,
      SetupStep.applyFailed => SetupStep.review,
      SetupStep.look => fastPath ? root : SetupStep.review,
    };
    if (to == null) return false;
    if (to == _step) return true;
    if (_step == SetupStep.joining) {
      joinBusy = false;
      joinError = null;
    }
    _go(to, dir: -1);
    return true;
  }

  SetupStep get _lastOrderQuestion {
    if (_askedOrderJump) return SetupStep.orderQ3;
    if (_askedOrderRun) return SetupStep.orderQ2;
    return SetupStep.orderQ1;
  }

  SetupStep get _lastQuestion {
    if (_askedJump) return SetupStep.wiringQ3;
    if (_askedRun) return SetupStep.wiringQ2;
    return SetupStep.wiringQ1;
  }

  // --- The device ---------------------------------------------------------

  String? host;
  WledClient? _client;
  String? _clientHost;
  DeviceSetupState? state;

  WledClient get client {
    if (_client == null || _clientHost != host) {
      _client?.close();
      _clientHost = host;
      _client = _factory(host!);
    }
    return _client!;
  }

  Future<void> _target(String next) async {
    if (host == next) return;
    await _endTest();
    await _snapshotting;
    if (!wrote && !(_snapshot?.needsRestore ?? false)) await _forgetSnapshot();
    _client?.close();
    _client = null;
    _clientHost = null;
    host = next;
    state = null;
    _snapshot = _prior = null;
    _snapshotting = null;
    draftWidth = draftHeight = null;
    draftWiring = null;
    draftChain = null;
    draftCols = draftRows = 1;
    severalPanels = _fromChoice = false;
    _resetAnswers();
    supplyAmps = null;
    wrote = confirmed = fastPath = rollbackFailed = false;
    testNeedsMoreLeds = checkUnreachable = pinBusy = false;
    testError = pinError = wiringNote = null;
    unsupportedReason = SetupSupport.supported;
    _rlmOverridden = _suspended = false;
    _rlmClient = null;
  }

  WledClient? _setupClientCache;
  WledClient get _setupClient => _setupClientCache ??= _factory(setupHost);

  // --- Connect: search ------------------------------------------------------

  void chooseOnWifi() => _go(SetupStep.search);
  void chooseNew() => _go(SetupStep.join);

  /// A device found by the search: save it, select it and read it.
  /// Returns an error message, or null when it worked.
  Future<String?> connectFound(DiscoveredDevice d) async {
    final g = _gen;
    try {
      await devices.addAndSelect(d.host, d.name);
    } catch (_) {}
    if (_disposed || g != _gen) return null;
    if (!devices.isConnected) {
      return 'Couldn\'t reach ${d.name}. Is it switched on and on the same Wi-Fi?';
    }
    HapticFeedback.mediumImpact();
    await _target(d.host);
    if (_disposed || g != _gen) return null;
    _go(SetupStep.check);
    return null;
  }

  // --- Join: the device's own network ---------------------------------------

  bool joinGuided = false;
  bool joinBusy = false;
  String? joinError;

  /// The system dialog couldn't connect: Wi-Fi settings becomes the main way.
  bool assistedFailed = false;
  bool advancedOpen = false;
  String setupSsid = '';
  String setupPassword = 'wled1234';

  /// The name and MAC the device reported on its own network.
  String setupName = '';
  String setupMac = '';
  Timer? _guidedTimer;
  bool _polling = false;

  bool get assisted => wifi.assisted;

  /// The assisted system dialog is available and not set aside.
  bool get showGuided => joinGuided || !wifi.assisted;

  String get networkName => setupSsid.trim().isEmpty ? 'WLED-AP' : setupSsid.trim();
  String get networkPassword => setupSsid.trim().isEmpty && setupPassword.isEmpty ? 'wled1234' : setupPassword;

  void refreshWifi() => _notify();

  void setAdvancedOpen(bool v) {
    advancedOpen = v;
    _notify();
  }

  void setSetupNetwork({String? ssid, String? password}) {
    if (ssid != null) setupSsid = ssid;
    if (password != null) setupPassword = password;
    _notify();
  }

  Future<void> connectAssisted() async {
    if (joinBusy) return;
    joinBusy = true;
    joinError = null;
    assistedFailed = false;
    _notify();
    final g = _gen;
    final custom = setupSsid.trim();
    final r = await wifi.connect(
      ssid: custom.isEmpty ? null : custom,
      password: custom.isEmpty ? 'wled1234' : setupPassword,
    );
    if (_disposed || g != _gen) {
      if (r is SetupWifiConnected) unawaited(wifi.release());
      return;
    }
    switch (r) {
      case SetupWifiConnected():
        await _reachSetupDevice(g, tries: 4);
        return;
      case SetupWifiCancelled():
        break;
      case SetupWifiUnavailable():
        // A device that was set up before keeps retrying its old Wi-Fi and
        // only shows its own network for a few seconds at a time; Android's
        // Wi-Fi settings keep retrying, the one-shot system dialog doesn't.
        assistedFailed = true;
        joinError =
            'Couldn\'t connect to its Wi-Fi network. If it was set up before, its network only '
            'appears every few seconds. Wi-Fi settings keeps trying, so use that instead.';
      case SetupWifiDenied():
        joinGuided = true;
        joinError = 'Glyph needs to see nearby Wi-Fi to do this. You can join it in Wi-Fi settings instead.';
        _startGuided();
      case SetupWifiUnsupported():
        joinGuided = true;
        _startGuided();
      case SetupWifiFailed():
        joinError = 'Couldn\'t join its Wi-Fi network. You can join it in Wi-Fi settings instead.';
    }
    joinBusy = false;
    _notify();
  }

  /// "Use Wi-Fi settings instead".
  void useGuided() {
    joinGuided = true;
    joinError = null;
    _startGuided();
    _notify();
  }

  Future<void> openWifiSettings() => wifi.openSettings();

  void _startGuided() {
    _guidedTimer?.cancel();
    final g = _gen;
    _guidedTimer = Timer.periodic(guidedPoll, (_) async {
      if (_polling || !_resumed || g != _gen || _step != SetupStep.join) return;
      _polling = true;
      try {
        await wifi.bindCurrentWifi();
        await _reachSetupDevice(g, tries: 1, quiet: true);
      } finally {
        _polling = false;
      }
    });
  }

  void _stopGuided() {
    _guidedTimer?.cancel();
    _guidedTimer = null;
  }

  Future<void> _reachSetupDevice(int g, {required int tries, bool quiet = false}) async {
    WledInfo? info;
    for (var i = 0; i < tries && info == null; i++) {
      if (i > 0) await _delay(const Duration(seconds: 1));
      if (_disposed || g != _gen) return;
      try {
        info = await _setupClient.info();
      } catch (_) {}
    }
    if (_disposed || g != _gen) return;
    if (info == null) {
      if (!quiet) {
        joinBusy = false;
        joinError = 'Connected, but your device didn\'t answer. Give it a moment and try again.';
        _notify();
      }
      return;
    }
    setupName = info.name;
    setupMac = info.mac;
    joinBusy = false;
    joinError = null;
    _go(SetupStep.wifi);
  }

  // --- Home Wi-Fi -------------------------------------------------------------

  List<WifiNetwork> networks = const [];
  bool scanning = false;
  String? wifiError;
  String? selectedSsid;
  bool otherSelected = false;
  String otherSsid = '';
  String password = '';

  /// The network the person picked (or typed).
  String get chosenSsid => otherSelected ? otherSsid.trim() : (selectedSsid ?? '');

  bool get chosenSecure {
    if (otherSelected) return true;
    return networks.where((n) => n.ssid == selectedSsid).firstOrNull?.secure ?? true;
  }

  bool get canJoin => chosenSsid.isNotEmpty && (!chosenSecure || password.isNotEmpty);

  Future<void> scan() async {
    final g = _gen;
    scanning = true;
    wifiError = null;
    _notify();
    try {
      final found = await _setupClient.scanNetworks();
      if (_disposed || g != _gen) return;
      networks = found;
    } catch (_) {
      if (_disposed || g != _gen) return;
      wifiError = 'Couldn\'t look for networks. Check your phone is still connected to your device.';
    }
    scanning = false;
    _notify();
  }

  void pickNetwork(WifiNetwork n) {
    selectedSsid = n.ssid;
    otherSelected = false;
    password = '';
    _notify();
  }

  void pickOther() {
    otherSelected = true;
    selectedSsid = null;
    password = '';
    _notify();
  }

  void setOtherSsid(String v) {
    otherSsid = v;
    _notify();
  }

  void setPassword(String v) {
    password = v;
    _notify();
  }

  // --- Joining ----------------------------------------------------------------

  JoinPhase joinPhase = JoinPhase.sending;

  /// The network being joined (kept for the failure screen).
  String joiningSsid = '';
  void Function()? _cancelFind;

  Future<void> joinNetwork() async {
    if (!canJoin) return;
    HapticFeedback.lightImpact();
    final ssid = chosenSsid;
    final psk = chosenSecure ? password : '';
    password = '';
    joiningSsid = ssid;
    joinPhase = JoinPhase.sending;
    _go(SetupStep.joining);
    final g = _gen;
    try {
      final phone = await phoneZoneReader();
      if (_disposed || g != _gen) return;
      final zone = wledTimezoneFor(phone.iana, phone.offset);
      await _setupClient.joinWifi(ssid, psk,
        tz: zone.tz,
        offsetSeconds: zone.offsetSeconds,
      );
    } catch (_) {
      if (_disposed || g != _gen) return;
      wifiError = 'Your device didn\'t take that. Check your phone is still connected to it, then try again.';
      _go(SetupStep.wifi, dir: -1);
      return;
    }
    if (_disposed || g != _gen) return;
    joinPhase = JoinPhase.searching;
    _notify();
    await wifi.release();
    if (_disposed || g != _gen) return;
    final found = await _findByMac(g);
    if (_disposed || g != _gen) return;
    if (found == null) {
      _go(SetupStep.joinFailed);
      return;
    }
    try {
      await devices.addAndSelect(found.host, setupName.isEmpty ? found.name : setupName);
    } catch (_) {}
    if (_disposed || g != _gen) return;
    if (!devices.isConnected) {
      _go(SetupStep.joinFailed);
      return;
    }
    HapticFeedback.mediumImpact();
    await _target(found.host);
    if (_disposed || g != _gen) return;
    _go(SetupStep.check);
  }

  /// Looks for the device on the home network by its MAC: mDNS first, then
  /// a scan of the phone's subnet, again and again until [findTimeout].
  Future<DiscoveredDevice?> _findByMac(int g) {
    final target = _normMac(setupMac);
    final known = {for (final d in devices.saved) d.host};
    final c = Completer<DiscoveredDevice?>();
    final subs = <StreamSubscription<DiscoveredDevice>>[];
    final tried = <String, DateTime>{};
    Timer? deadline, scanTimer;
    var done = false;

    void finish(DiscoveredDevice? d) {
      if (done) return;
      done = true;
      deadline?.cancel();
      scanTimer?.cancel();
      for (final s in subs) {
        s.cancel();
      }
      c.complete(d);
    }

    bool matches(DiscoveredDevice d) {
      if (target.isNotEmpty) return _normMac(d.mac) == target;
      return d.name == setupName && !known.contains(d.host);
    }

    Future<void> consider(DiscoveredDevice d) async {
      if (done) return;
      if (_normMac(d.mac).isNotEmpty) {
        if (matches(d)) finish(d);
        return;
      }
      final now = DateTime.now();
      final last = tried[d.host];
      if (last != null && now.difference(last) < const Duration(seconds: 5)) return;
      tried[d.host] = now;
      final p = await services.probe(d.host);
      if (p != null && matches(p)) finish(p);
    }

    void listen(Stream<DiscoveredDevice> s, {VoidCallback? onDone}) {
      subs.add(s.listen(consider, onError: (Object _) {}, onDone: onDone));
    }

    void scanRound() {
      if (done) return;
      listen(services.scan(), onDone: () {
        if (!done) scanTimer = Timer(findRescanGap, scanRound);
      });
    }

    listen(services.discover());
    scanTimer = Timer(findScanAfter, scanRound);
    deadline = Timer(findTimeout, () => finish(null));
    _cancelFind = () => finish(null);
    return c.future;
  }

  /// "Try again" on the failure screen: the device opens its own network
  /// again after a short while, so start over at Join.
  void retryJoin() => _go(SetupStep.join, dir: -1);

  /// "Enter its address": a typed address, checked and saved like a search.
  Future<String?> connectAddress(DiscoveredDevice d) => connectFound(d);

  // --- Check ------------------------------------------------------------------

  bool checkUnreachable = false;
  SetupSupport unsupportedReason = SetupSupport.supported;
  String? pinError;
  bool pinBusy = false;

  void retryCheck() => unawaited(_runCheck());

  Future<void> _runCheck() async {
    final g = _gen;
    host ??= devices.selected?.host;
    checkUnreachable = false;
    _notify();
    if (host == null) {
      checkUnreachable = true;
      _notify();
      return;
    }
    try {
      final c = client;
      var s = await c.setupState(checkLock: true);
      if (_disposed || g != _gen) return;
      final pending = await store.load(s.mac);
      if (_disposed || g != _gen) return;
      if (pending?.needsRestore == true && !s.pinLocked) {
        final restored = await store.restore(c, devices, snapshot: pending);
        if (_disposed || g != _gen) return;
        if (!restored.ok) throw StateError('Restore pending');
        s = await c.setupState();
      }
      if (_disposed || g != _gen) return;
      _handleState(s);
    } catch (_) {
      if (_disposed || g != _gen) return;
      checkUnreachable = true;
      _notify();
    }
  }

  void _handleState(DeviceSetupState s) {
    state = s;
    if (s.pinLocked) {
      pinError = null;
      _go(SetupStep.pin);
      return;
    }
    if (s.support != SetupSupport.supported) {
      unsupportedReason = s.support;
      _go(SetupStep.unsupported);
      return;
    }
    _initDraft(s);
    final g = s.grid;
    _fromChoice = false;
    if (g != null && s.isConfigured(DisplaySetup.grid(g))) {
      fastPath = true;
      _go(SetupStep.look);
    } else {
      fastPath = false;
      // A display Glyph can't tell apart from one panel starts with the
      // question; one it already knows goes to its own screen.
      _go(
        g != null && !g.isSingle
            ? SetupStep.grid
            : s.isMatrix
            ? SetupStep.size
            : SetupStep.panelsChoice,
      );
    }
  }

  Future<void> unlock(String pin) async {
    if (pinBusy || pin.isEmpty) return;
    pinBusy = true;
    pinError = null;
    _notify();
    final g = _gen;
    try {
      await client.unlockSettings(pin);
    } catch (e) {
      if (_disposed || g != _gen) return;
      pinBusy = false;
      pinError = e is WledException && e.cause == 401
          ? 'That PIN didn\'t work. Try again.'
          : 'Couldn\'t reach your device. Is it on?';
      _notify();
      return;
    }
    if (_disposed || g != _gen) return;
    pinBusy = false;
    _go(SetupStep.check);
  }

  /// "Done" on the unsupported screen: nothing to set up, finish.
  void skipToDone() {
    unawaited(_setTime());
    _go(SetupStep.done);
  }

  /// Part of setup, no extra step: the device learns the time (best effort).
  Future<void> _setTime() async {
    try {
      await ensureDeviceTime(client);
    } catch (_) {}
  }

  // --- Size -------------------------------------------------------------------

  /// The size of one panel (of the whole display when it is one panel).
  int? draftWidth, draftHeight;
  PanelWiring? draftWiring;

  /// Panels across and down. 1 × 1 is a single panel.
  int draftCols = 1, draftRows = 1;

  /// The person said the display is made of several panels (set even while
  /// the grid is still 1 × 1, so the grid screen stays the grid screen).
  bool severalPanels = false;

  /// How the panels are chained (see [PanelGrid.chain]); null until known.
  PanelWiring? draftChain;

  /// Grid cells (column, row) of panels that sit upside down.
  final Set<(int, int)> flippedCells = {};

  /// Came to Size or Grid from the one-or-several question.
  bool _fromChoice = false;

  void _initDraft(DeviceSetupState s) {
    if (draftWidth != null) return;
    final g = s.grid;
    final w = s.width, h = s.height;
    if (s.isMatrix && g != null) {
      draftWidth = g.panelW;
      draftHeight = g.panelH;
      draftCols = g.cols;
      draftRows = g.rows;
      draftChain = g.chain;
      severalPanels = !g.isSingle;
      final base = g.wiring.first;
      flippedCells
        ..clear()
        ..addAll({
          for (var k = 1; k < g.panelCount; k++)
            if (g.wiring[k] != base && g.wiring[k] == base.turnedUpsideDown) g.cellOf(k),
        });
    } else if (s.isMatrix && w != null && h != null) {
      draftWidth = w;
      draftHeight = h;
    } else {
      final n = s.ledCount;
      final common = commonSizes.where((c) => c.$1 * c.$2 == n).firstOrNull;
      if (common != null) {
        draftWidth = common.$1;
        draftHeight = common.$2;
      } else {
        final side = math.sqrt(n).round();
        if (n > 0 && side * side == n && side <= _maxSide) {
          draftWidth = side;
          draftHeight = side;
        }
      }
    }
    draftWiring = s.wiring;
  }

  int get deviceLeds => state?.ledCount ?? 0;
  bool get hasSize => draftWidth != null && draftHeight != null;

  /// Several panels were chosen and there are at least two.
  bool get isGrid => severalPanels && draftCols * draftRows > 1;
  int get draftPanels => isGrid ? draftCols * draftRows : 1;
  int get draftPanelLeds => (draftWidth ?? 0) * (draftHeight ?? 0);
  int get draftLeds => draftPanelLeds * draftPanels;

  /// The whole display, in LEDs across and down.
  int get displayWidth => (draftWidth ?? 0) * (isGrid ? draftCols : 1);
  int get displayHeight => (draftHeight ?? 0) * (isGrid ? draftRows : 1);
  bool get changesLeds => hasSize && deviceLeds != draftLeds;

  /// Why the layout can't be driven, in plain words; null when it can.
  String? get sizeProblem {
    if (!hasSize) return null;
    if (!isGrid) return draftPanelLeds > maxDisplayLeds ? tooBigWords : null;
    return PanelGrid.uniform(
      cols: draftCols,
      rows: draftRows,
      panelW: draftWidth!,
      panelH: draftHeight!,
    ).limitProblem;
  }

  /// A tile or the steppers picked a size (of one panel).
  void setSize(int w, int h, {bool click = true}) {
    if (click) HapticFeedback.selectionClick();
    final nw = w.clamp(1, _maxSide), nh = h.clamp(1, _maxSide);
    if (nw != draftWidth || nh != draftHeight) _resetAnswers();
    draftWidth = nw;
    draftHeight = nh;
    _notify();
  }

  /// "One panel" or "Several panels" on the first Size question.
  void choosePanels({required bool several}) {
    HapticFeedback.selectionClick();
    _fromChoice = true;
    _setSeveral(several);
    _go(several ? SetupStep.grid : SetupStep.size);
  }

  /// The quiet link on Size and Grid that switches between the two.
  void switchPanels({required bool several}) {
    HapticFeedback.selectionClick();
    _setSeveral(several);
    _go(several ? SetupStep.grid : SetupStep.size, dir: several ? 1 : -1);
  }

  void _setSeveral(bool several) {
    if (several == severalPanels && (!several || draftCols * draftRows > 1)) return;
    _resetAnswers();
    if (several) {
      severalPanels = true;
      if (draftCols * draftRows < 2) _guessGrid();
    } else {
      // One panel: the size is the whole display.
      final w = displayWidth, h = displayHeight;
      severalPanels = false;
      if (hasSize && _fitsSide(w, h)) {
        draftWidth = w;
        draftHeight = h;
      }
      draftCols = draftRows = 1;
      flippedCells.clear();
      draftChain = null;
    }
  }

  bool _fitsSide(int w, int h) => w >= 1 && h >= 1 && w <= _maxSide && h <= _maxSide;

  /// A first guess for the grid from the LEDs the device already has: a
  /// common panel size that divides the count, laid out wider than tall.
  void _guessGrid() {
    final n = deviceLeds;
    for (final (pw, ph) in panelSizes) {
      final panels = n ~/ (pw * ph);
      if (n % (pw * ph) != 0 || panels < 2 || panels > maxPanels) continue;
      var rows = math.sqrt(panels).floor();
      while (rows > 1 && panels % rows != 0) {
        rows--;
      }
      final cols = panels ~/ rows;
      if (cols > maxGridSide || rows > maxGridSide) continue;
      draftWidth = pw;
      draftHeight = ph;
      draftCols = cols;
      draftRows = rows;
      return;
    }
    if (!hasSize || displayWidth * displayHeight > 1024) {
      draftWidth = 16;
      draftHeight = 16;
    }
    draftCols = 2;
    draftRows = 1;
  }

  /// The grid steppers.
  void setGrid(int cols, int rows, {bool click = true}) {
    if (click) HapticFeedback.selectionClick();
    final nc = cols.clamp(1, maxGridSide), nr = rows.clamp(1, maxGridSide);
    if (nc != draftCols || nr != draftRows) {
      _resetAnswers();
      draftChain = null;
    }
    draftCols = nc;
    draftRows = nr;
    _notify();
  }

  bool get canGridNext => hasSize && draftCols * draftRows >= 2 && sizeProblem == null;

  void gridNext() {
    if (!canGridNext) return;
    _resetAnswers();
    _go(SetupStep.orderQ1);
  }

  void sizeNext() {
    if (!hasSize || sizeProblem != null) return;
    if (severalPanels && draftCols * draftRows < 2) severalPanels = false;
    _resetAnswers();
    _go(isGrid ? SetupStep.orderQ1 : SetupStep.wiringQ1);
  }

  // --- Panel order test ---------------------------------------------------------

  /// Q1: the corner of the grid the first panel sits in.
  StartCorner? answerPanelCorner;

  /// Q2: the chain runs across (the next panel is beside the first) or down.
  bool? answerChainAcross;

  /// Q3: the second run starts at the far end (snake) or on the same side.
  bool? answerChainSnake;
  bool _askedOrderRun = false, _askedOrderJump = false;

  /// The grid cell of the corner [c].
  (int, int) cornerCell(StartCorner c) => (
    c.isRight && draftCols > 1 ? draftCols - 1 : 0,
    c.isBottom && draftRows > 1 ? draftRows - 1 : 0,
  );

  /// The corner a first-panel cell is in, or null when it isn't a corner.
  StartCorner? cornerOfCell((int, int) cell) {
    final (cx, cy) = cell;
    final xs = {0, draftCols - 1}, ys = {0, draftRows - 1};
    if (!xs.contains(cx) || !ys.contains(cy)) return null;
    return StartCorner.of(bottom: draftRows > 1 && cy == draftRows - 1, right: draftCols > 1 && cx == draftCols - 1);
  }

  /// The cells a first panel can be in: the corners of the grid.
  Set<(int, int)> get firstPanelCells => {for (final c in StartCorner.values) cornerCell(c)};

  /// The panels beside the first one: next across and next down.
  Set<(int, int)> get nextPanelCells {
    final c = answerPanelCorner;
    if (c == null) return const {};
    final (fx, fy) = cornerCell(c);
    final dx = fx == 0 ? 1 : -1, dy = fy == 0 ? 1 : -1;
    return {if (draftCols > 1) (fx + dx, fy), if (draftRows > 1) (fx, fy + dy)};
  }

  /// The cell of the first panel as answered.
  (int, int)? get firstCell {
    final c = answerPanelCorner;
    return c == null ? null : cornerCell(c);
  }

  /// Q3's two places the second run can start: [near] on the same side the
  /// first run started (the chain goes straight on), [far] at the other end
  /// (it snakes back).
  ({(int, int) near, (int, int) far})? get jumpCells {
    final c = answerPanelCorner, across = answerChainAcross;
    if (c == null || across == null) return null;
    if (across) {
      final y = c.isBottom ? draftRows - 2 : 1;
      final nearX = c.isRight ? draftCols - 1 : 0;
      return (near: (nearX, y), far: (draftCols - 1 - nearX, y));
    }
    final x = c.isRight ? draftCols - 2 : 1;
    final nearY = c.isBottom ? draftRows - 1 : 0;
    return (near: (x, nearY), far: (x, draftRows - 1 - nearY));
  }

  /// The corners of the grid that give different first panels (one row or
  /// column has fewer).
  List<StartCorner> get firstPanelCorners {
    final seen = <(int, int)>{};
    return [
      for (final c in StartCorner.values)
        if (seen.add(cornerCell(c))) c,
    ];
  }

  /// Q1: a panel was tapped. Only the grid's corner panels can start a chain.
  void pickFirstPanel((int, int) cell) {
    final c = cornerOfCell(cell);
    if (c == null) return;
    HapticFeedback.selectionClick();
    answerPanelCorner = c;
    answerChainAcross = null;
    answerChainSnake = null;
    _askedOrderRun = false;
    _askedOrderJump = false;
    if (draftCols == 1 || draftRows == 1) {
      // Only one way to run: no question to ask.
      answerChainAcross = draftCols > 1;
      _afterOrderRun();
    } else {
      _askedOrderRun = true;
      _go(SetupStep.orderQ2);
    }
  }

  /// Q2: the next panel, by tapping it or by picking Across or Down.
  void pickNextPanel((int, int) cell) {
    final c = answerPanelCorner;
    if (c == null || !nextPanelCells.contains(cell)) return;
    pickChainRun(across: cell.$2 == cornerCell(c).$2);
  }

  void pickChainRun({required bool across}) {
    HapticFeedback.selectionClick();
    answerChainAcross = across;
    answerChainSnake = null;
    _afterOrderRun();
  }

  /// Runs of panels for the answered direction.
  int get chainRunCount => (answerChainAcross ?? true) ? draftRows : draftCols;

  /// Panels in the first run for the answered direction.
  int get chainRunPanels => (answerChainAcross ?? true) ? draftCols : draftRows;

  void _afterOrderRun() {
    if (chainRunCount < 2) {
      answerChainSnake = false;
      _finishOrder();
    } else {
      _askedOrderJump = true;
      _go(SetupStep.orderQ3);
    }
  }

  void pickChainJump({required bool snake}) {
    HapticFeedback.selectionClick();
    answerChainSnake = snake;
    _finishOrder();
  }

  void _finishOrder() {
    draftChain = normalizeChain(
      PanelWiring.fromAnswers(
        corner: answerPanelCorner!,
        firstRunAlongWidth: answerChainAcross!,
        secondRunStartsAtFarEnd: answerChainSnake ?? false,
      ),
      draftCols,
      draftRows,
    );
    flippedCells.clear();
    _go(SetupStep.orderResult);
  }

  void orderTestAgain() {
    _resetOrderAnswers();
    draftChain = null;
    flippedCells.clear();
    _go(SetupStep.orderQ1, dir: -1);
  }

  void chooseManualOrder() {
    draftChain ??= const PanelWiring(zigzag: true);
    _go(SetupStep.orderManual);
  }

  void setManualOrder({StartCorner? corner, bool? vertical, bool? zigzag}) {
    if (corner != null) HapticFeedback.selectionClick();
    final c = draftChain ?? const PanelWiring(zigzag: true);
    draftChain = PanelWiring(
      corner: corner ?? c.corner,
      vertical: vertical ?? c.vertical,
      zigzag: zigzag ?? c.zigzag,
    );
    flippedCells.clear();
    _notify();
  }

  /// "Looks right" or "Use this" for the panel order: on to the LED wiring.
  void orderLooksRight() {
    if (draftChain == null) return;
    _go(SetupStep.wiringQ1);
  }

  // --- Upside-down panels ---------------------------------------------------------

  /// A panel was tapped on "Are any panels upside down?". The first panel
  /// defines the wiring, so it can't be marked.
  void toggleFlipped((int, int) cell) {
    final g = draftGrid;
    if (g == null || g.cellOf(0) == cell) return;
    HapticFeedback.selectionClick();
    if (!flippedCells.add(cell)) flippedCells.remove(cell);
    _notify();
  }

  void orientationDone() {
    if (_step != SetupStep.orientation) return;
    HapticFeedback.lightImpact();
    _go(SetupStep.review);
  }

  // --- Wiring test ------------------------------------------------------------

  StartCorner? answerCorner;
  bool? answerAlongWidth;
  bool? answerFarEnd;
  bool _askedRun = false, _askedJump = false;

  /// Shown above the first question when Look sent the person back.
  String? wiringNote;

  /// The test needs more LEDs than the device is set for.
  bool testNeedsMoreLeds = false;
  String? testError;

  void _resetWiringAnswers() {
    answerCorner = null;
    answerAlongWidth = null;
    answerFarEnd = null;
    _askedRun = false;
    _askedJump = false;
  }

  void _resetOrderAnswers() {
    answerPanelCorner = null;
    answerChainAcross = null;
    answerChainSnake = null;
    _askedOrderRun = false;
    _askedOrderJump = false;
  }

  void _resetAnswers() {
    _resetWiringAnswers();
    _resetOrderAnswers();
  }

  /// The size of one panel: the wiring questions are asked inside it.
  int get _w => draftWidth ?? state?.width ?? 1;
  int get _h => draftHeight ?? state?.height ?? 1;

  /// LEDs in one run for the answered direction.
  int get firstRunLength => (answerAlongWidth ?? true) ? _w : _h;

  /// How many runs there are for the answered direction.
  int get runCount => (answerAlongWidth ?? true) ? _h : _w;

  void pickCorner(StartCorner c) {
    HapticFeedback.selectionClick();
    answerCorner = c;
    answerAlongWidth = null;
    answerFarEnd = null;
    _askedRun = false;
    _askedJump = false;
    if (_w == 1 || _h == 1) {
      // Only one way to run: no question to ask.
      answerAlongWidth = _w > 1 || _h == 1;
      _afterRun();
    } else {
      _askedRun = true;
      _go(SetupStep.wiringQ2);
    }
  }

  void pickRun({required bool alongWidth}) {
    HapticFeedback.selectionClick();
    answerAlongWidth = alongWidth;
    answerFarEnd = null;
    _afterRun();
  }

  void _afterRun() {
    if (runCount < 2) {
      answerFarEnd = false;
      _finishWiring();
    } else {
      _askedJump = true;
      _go(SetupStep.wiringQ3);
    }
  }

  void pickJump({required bool farEnd}) {
    HapticFeedback.selectionClick();
    answerFarEnd = farEnd;
    _finishWiring();
  }

  void _finishWiring() {
    draftWiring = PanelWiring.fromAnswers(
      corner: answerCorner!,
      firstRunAlongWidth: answerAlongWidth!,
      secondRunStartsAtFarEnd: answerFarEnd ?? false,
    );
    _go(SetupStep.wiringResult);
  }

  void testAgain() {
    _resetWiringAnswers();
    _go(SetupStep.wiringQ1, dir: -1);
  }

  void chooseManual() {
    draftWiring ??= const PanelWiring();
    _go(SetupStep.wiringManual);
  }

  void setManualWiring({StartCorner? corner, bool? vertical, bool? zigzag}) {
    if (corner != null) HapticFeedback.selectionClick();
    final w = draftWiring ?? const PanelWiring();
    draftWiring = PanelWiring(
      corner: corner ?? w.corner,
      vertical: vertical ?? w.vertical,
      zigzag: zigzag ?? w.zigzag,
    );
    _notify();
  }

  /// "Looks right" or "Use this" for the wiring inside a panel.
  void looksRight() {
    if (draftWiring == null) return;
    _go(isGrid ? SetupStep.orientation : SetupStep.review);
  }

  /// The panels as drawn so far: [draftWiring] in every panel, turned
  /// upside down where marked. Null until the size and wiring are known.
  PanelGrid? get draftGrid {
    final base = draftWiring;
    if (!hasSize || base == null) return null;
    if (!isGrid) return PanelGrid.single(draftWidth!, draftHeight!, base);
    final chain = normalizeChain(draftChain ?? const PanelWiring(zigzag: true), draftCols, draftRows);
    return PanelGrid(
      cols: draftCols,
      rows: draftRows,
      panelW: draftWidth!,
      panelH: draftHeight!,
      chain: chain,
      wiring: [
        for (var k = 0; k < draftCols * draftRows; k++)
          k > 0 && flippedCells.contains(chain.positionOf(k, draftCols, draftRows)) ? base.turnedUpsideDown : base,
      ],
    );
  }

  DisplaySetup? get draftSetup {
    final g = draftGrid;
    if (g == null) return null;
    return g.isSingle ? DisplaySetup(draftWidth!, draftHeight!, draftWiring!) : DisplaySetup.grid(g);
  }

  // --- Test session -------------------------------------------------------------

  SetupSession? _session;
  bool _testReady = false, _rlmOverridden = false, _suspended = false;
  int _testToken = 0;
  Timer? _chase;
  int _chaseAt = 0;
  Future<void> _ending = Future.value(), _starting = Future.value();
  WledClient? _rlmClient;

  bool _testCurrent(int token) =>
      token == _testToken && !_disposed && !_cleaned && _resumed;

  Future<void> _start(Future<void> Function(int) run) {
    if (!_resumed) _suspended = true;
    final token = ++_testToken;
    final ending = _ending;
    return _starting = _starting.then((_) async {
      await ending;
      if (_testCurrent(token)) await run(token);
    });
  }

  bool get testRunning => _testReady;

  SetupSession _makeSession(int token) => SetupSession(
    canStart: () => _testCurrent(token),
    playback: playback,
    devices: devices,
    host: host!,
    client: client,
    senderFactory: _senderFactory,
    observeLifecycle: false,
  );

  Future<void> _prepareTest() => _start(_prepareTestNow);

  Future<void> _prepareTestNow(int token) async {
    if (_testReady) {
      _showTestPattern();
      return;
    }
    testError = null;
    if (!_testCurrent(token)) return;
    try {
      await _ensureSnapshot();
      if (!_testCurrent(token)) return;
      final s = state!;
      if (s.isMatrix && s.realtimeMaps) {
        _snapshot = _snapshot!.withNeedsRestore(true);
        await store.save(_snapshot!);
        if (!_testCurrent(token)) return;
        _rlmClient = client;
        _rlmOverridden = true;
        await _rlmClient!.setRealtimeMaps(false);
      }
      if (!_testCurrent(token)) {
        await _restoreRlm();
        return;
      }
      final session = _makeSession(token);
      await session.start();
      if (!_testCurrent(token)) {
        await session.end();
        await _restoreRlm();
        return;
      }
      _session = session;
      _testReady = true;
    } catch (_) {
      if (!_testCurrent(token)) return;
      testError = 'Couldn\'t show anything on your device. Is it still on and on the same Wi-Fi?';
      await _restoreRlm();
      _notify();
      return;
    }
    _showTestPattern();
    _notify();
  }

  Future<void> _restoreRlm() async {
    if (!_rlmOverridden) return;
    try {
      await _rlmClient!.setRealtimeMaps(_snapshot?.realtimeMaps ?? true);
      _rlmOverridden = false;
      _rlmClient = null;
      if (_snapshot != null) {
        _snapshot = _snapshot!.withNeedsRestore(false);
        await store.save(_snapshot!);
      }
    } catch (_) {}
  }

  /// Ends the test or Look session and puts the realtime map back.
  Future<void> _endTest({int? width, int? height}) {
    _testToken++;
    _chase?.cancel();
    _chase = null;
    _testReady = false;
    final s = _session;
    _session = null;
    final prev = _ending, starting = _starting;
    return _ending = prev.then((_) async {
      await starting;
      try {
        await s?.end(width: width, height: height);
      } catch (_) {}
      await _restoreRlm();
    });
  }

  int get _ledCount {
    final n = state?.ledCount ?? 0;
    return n > 0 ? n : draftLeds;
  }

  /// The first (up to four) LEDs of the [k]-th panel in the chain: enough
  /// to spot on a big panel.
  List<int> _panelLeds(int k) => [
    for (var i = 0; i < math.min(4, draftPanelLeds); i++) k * draftPanelLeds + i,
  ];

  void _showTestPattern() {
    final session = _session;
    if (session == null || !_testReady) return;
    _chase?.cancel();
    _chase = null;
    final n = _ledCount;
    testNeedsMoreLeds = false;

    /// Shows [lit]; when the device has fewer LEDs than the highest one,
    /// says so and lights what can be lit.
    void show(List<int> lit) {
      testNeedsMoreLeds = lit.any((i) => i >= n);
      session.showRaw(litLeds(n, lit));
    }

    switch (_step) {
      case SetupStep.wiringQ1:
        session.showRaw(litLeds(n, const [0]));
      case SetupStep.wiringQ2:
        final k = math.max(1, math.min(4, math.min(_w, _h) - 1));
        if (k >= n) {
          testNeedsMoreLeds = true;
        } else if (reduceMotion) {
          session.showRaw(litLeds(n, [for (var i = 0; i <= k; i++) i]));
        } else {
          _chaseAt = 0;
          session.showRaw(litLeds(n, const [0]));
          _chase = Timer.periodic(chaseEvery, (_) {
            _chaseAt = _chaseAt >= k ? 0 : _chaseAt + 1;
            session.showRaw(litLeds(n, [for (var i = 0; i <= _chaseAt; i++) i]));
          });
        }
      case SetupStep.wiringQ3:
        final run = firstRunLength;
        if (run >= n) {
          testNeedsMoreLeds = true;
          session.showRaw(litLeds(n, const [0]));
        } else {
          session.showRaw(litLeds(n, [run]));
        }
      case SetupStep.orderQ1:
        show(_panelLeds(0));
      case SetupStep.orderQ2:
        show(_panelLeds(1));
      case SetupStep.orderQ3:
        show(_panelLeds(chainRunPanels));
      case SetupStep.orientation:
        // LED 0 of every panel at once.
        show([for (var k = 0; k < draftPanels; k++) k * draftPanelLeds]);
      default:
        break;
    }
  }

  /// "Try again" in the Nothing lit up sheet.
  Future<void> retryTest() async {
    await _endTest();
    if (_disposed || !_isTest(_step)) return;
    await _prepareTest();
  }

  /// "Set it to M LEDs now" when the device has fewer LEDs than the display.
  Future<void> setLedsNow() async {
    final s = state;
    if (s == null || s.outputs.isEmpty || !hasSize) return;
    final g = _gen, c = client, count = draftLeds;
    bool stale() => _disposed || g != _gen;
    try {
      await _ensureSnapshot();
      if (stale()) return;
      wrote = true;
      await c.setLedCount(count, s.outputs.first);
      if (stale()) return;
      await _delay(settle);
      if (stale()) return;
      final play = _snapshot?.playback;
      if (play != null) {
        try {
          await c.restorePlayback(play);
        } catch (_) {}
      }
      if (stale()) return;
      final fresh = await c.setupState();
      if (_disposed || g != _gen) return;
      state = fresh;
      _showTestPattern();
    } catch (_) {
      if (stale()) return;
      testError = 'Couldn\'t change the number of LEDs.';
    }
    _notify();
  }

  // --- Snapshot ---------------------------------------------------------------

  SetupSnapshot? _snapshot;
  SetupSnapshot? _prior;
  Future<void>? _snapshotting;

  bool get hasSnapshot => _snapshot != null;

  /// Saves what the device is like now, before the first write of this run.
  Future<void> _ensureSnapshot() => _snapshotting ??= _takeSnapshot();

  Future<void> _takeSnapshot() async {
    final s = state!, c = client, target = host!;
    final saved = devices.saved.where((d) => d.host == host).firstOrNull;
    Map<String, dynamic>? playback;
    try {
      playback = await c.state();
    } catch (_) {}
    final snap = SetupSnapshot.of(s,
        host: target, appLayout: saved?.layout ?? MatrixLayout.identity, playback: playback);
    try {
      _prior = await store.load(s.mac);
      await store.save(snap);
    } catch (_) {
      _snapshotting = null;
      rethrow;
    }
    _snapshot = snap;
  }

  Future<void> _forgetSnapshot() async {
    final snap = _snapshot;
    _snapshot = null;
    _snapshotting = null;
    if (snap == null) return;
    // A newer snapshot replaced an older undo point; give that back.
    final prior = _prior;
    _prior = null;
    try {
      if (prior != null) {
        await store.save(prior);
      } else {
        await store.clear(snap.mac);
      }
    } catch (_) {}
  }

  // --- Review -----------------------------------------------------------------

  double? supplyAmps;

  int? get currentLimitMa => state?.currentLimitMa;

  /// The limit the chosen supply gives (null when none is chosen).
  int? get newLimitMa => supplyAmps == null ? null : recommendedLimitMa(supplyAmps!, currentLimitMa);

  /// The existing limit is stricter than the recommendation.
  bool get keepsCurrentLimit {
    final a = supplyAmps, cur = currentLimitMa;
    if (a == null || cur == null || cur <= 0) return false;
    return recommendedLimitMa(a, null) > cur;
  }

  void setSupply(double? amps) {
    supplyAmps = amps;
    _notify();
  }

  // --- Apply ------------------------------------------------------------------

  ApplyPhase applyPhase = ApplyPhase.backup;
  bool rollbackFailed = false;

  /// The phases this setup goes through.
  List<ApplyPhase> get applyPhases => [
    ApplyPhase.backup,
    if (changesLeds) ApplyPhase.leds,
    ApplyPhase.layout,
    ApplyPhase.verify,
  ];

  /// Writes the setup to the device; rolls back on any failure.
  Future<void> apply() async {
    final setup = draftSetup;
    if ((_step != SetupStep.review && _step != SetupStep.applyFailed) || setup == null) return;
    if (setup.grid.limitProblem != null) return;
    HapticFeedback.lightImpact();
    rollbackFailed = false;
    applyPhase = ApplyPhase.backup;
    _go(SetupStep.applying);
    final g = _gen;
    bool stale() => _disposed || g != _gen;
    try {
      await _ending;
      await _ensureSnapshot();
      if (stale()) return;
      final c = client;
      var cur = state!;
      final limit = newLimitMa;
      if (cur.ledCount != setup.ledCount) {
        applyPhase = ApplyPhase.leds;
        _notify();
        wrote = true;
        await c.setLedCount(setup.ledCount, cur.outputs.first);
        await _delay(settle);
        cur = await c.setupState();
        if (cur.ledCount != setup.ledCount) throw StateError('LED count');
        if (stale()) return;
      }
      applyPhase = ApplyPhase.layout;
      _notify();
      wrote = true;
      await c.setPanelLayout(setup);
      if (!cur.realtimeMaps) await c.setRealtimeMaps(true);
      if (limit != null && limit != cur.currentLimitMa) await c.setCurrentLimit(limit);
      applyPhase = ApplyPhase.verify;
      _notify();
      final after = await c.setupState();
      if (stale()) return;
      if (!after.isConfigured(setup) || (limit != null && after.currentLimitMa != limit)) {
        throw StateError('The device kept its old setup');
      }
      final saved = devices.saved.where((d) => d.host == host).firstOrNull;
      if (saved != null && !saved.layout.isIdentity) {
        await devices.updateSaved(saved.copyWith(layout: MatrixLayout.identity));
      }
      state = after;
      final play = _snapshot?.playback;
      if (play != null) {
        try {
          await c.restorePlayback(play);
        } catch (_) {}
      }
      try {
        await devices.refresh();
      } catch (_) {}
      if (stale()) return;
    } catch (_) {
      if (stale()) return;
      await _rollback();
      return;
    }
    HapticFeedback.mediumImpact();
    _go(SetupStep.look);
  }

  Future<void> _rollback() async {
    final snap = _snapshot;
    var ok = false;
    if (snap != null) {
      try {
        final r = await store.restore(client, devices, snapshot: snap, clearOnSuccess: false);
        ok = r.ok;
      } catch (_) {}
    }
    if (_disposed) return;
    rollbackFailed = !ok;
    if (ok) {
      wrote = false;
      await _forgetSnapshot();
      try {
        state = await client.setupState();
      } catch (_) {}
    }
    if (_disposed) return;
    _go(SetupStep.applyFailed);
  }

  // --- Look -------------------------------------------------------------------

  Frame get lookFrame => cornerCheckFrame(displayWidth, displayHeight);

  Future<void> _startLook() => _start(_startLookNow);

  Future<void> _startLookNow(int token) async {
    testError = null;
    if (!_testCurrent(token)) return;
    final session = _makeSession(token);
    try {
      await session.start();
    } catch (_) {
      if (_testCurrent(token)) {
        testError = 'Couldn\'t show anything on your device. Is it still on and on the same Wi-Fi?';
        _notify();
      }
      return;
    }
    if (!_testCurrent(token)) {
      await session.end();
      return;
    }
    _session = session;
    _testReady = true;
    session.showFrame(lookFrame);
    _notify();
  }

  Future<void> lookMatches() async {
    if (_step != SetupStep.look) return;
    HapticFeedback.mediumImpact();
    confirmed = true;
    final g = _gen;
    final saved = devices.saved.where((d) => d.host == host).firstOrNull;
    if (saved != null && !saved.layout.isIdentity) {
      // What Look showed is the identity layout; normal playback must match.
      try {
        await _ensureSnapshot();
        await devices.updateSaved(saved.copyWith(layout: MatrixLayout.identity));
        wrote = true;
      } catch (_) {}
    }
    await _endTest(width: displayWidth, height: displayHeight);
    if (_disposed || g != _gen) return;
    try {
      await devices.refresh();
    } catch (_) {}
    if (_disposed || g != _gen) return;
    unawaited(_setTime());
    _go(SetupStep.done);
  }

  void lookDoesNotMatch() {
    if (_step != SetupStep.look) return;
    _resetAnswers();
    if (fastPath) {
      _go(isGrid ? SetupStep.grid : (state?.isMatrix ?? true) ? SetupStep.size : SetupStep.panelsChoice, dir: -1);
    } else if (isGrid) {
      wiringNote = 'Let\'s test the panels again.';
      _go(SetupStep.orderQ1, dir: -1);
    } else {
      wiringNote = 'Let\'s test the wiring again.';
      _go(SetupStep.wiringQ1, dir: -1);
    }
  }

  // --- Undo ---------------------------------------------------------------------

  /// Puts the device back the way this run found it. Returns whether
  /// everything went back.
  Future<bool> undo() async {
    final snap = _snapshot ?? await store.load(state?.mac ?? devices.info?.mac ?? '');
    if (snap == null) return true;
    await _endTest();
    var ok = false;
    try {
      final r = await store.restore(client, devices, snapshot: snap, clearOnSuccess: false);
      ok = r.ok;
    } catch (_) {}
    if (ok) {
      HapticFeedback.mediumImpact();
      wrote = false;
      confirmed = false;
      // The device is back as before: nothing is left to undo, not even an
      // older backup this run had replaced.
      _prior = null;
      await _forgetSnapshot();
      try {
        await store.clear(snap.mac);
      } catch (_) {}
      try {
        await devices.refresh();
        final caps = devices.caps;
        if (caps != null) playback.resize(caps.width, caps.height);
        state = await client.setupState();
      } catch (_) {}
    }
    return ok;
  }

  /// Look's "Undo setup": undo, then start the display setup again.
  Future<bool> undoAndRestart() async {
    final ok = await undo();
    if (_disposed) return ok;
    if (ok) {
      draftWidth = null;
      draftHeight = null;
      draftWiring = null;
      draftChain = null;
      draftCols = draftRows = 1;
      severalPanels = false;
      flippedCells.clear();
      _resetAnswers();
      supplyAmps = null;
      fastPath = false;
      _go(SetupStep.check, dir: -1);
    }
    return ok;
  }

  // --- Done and leaving ----------------------------------------------------------

  /// Saves the name for a new device and ends the wizard's work.
  Future<void> finish({String? name}) async {
    final n = name?.trim();
    if (isNewDevice && n != null && n.isNotEmpty && n != (devices.info?.name ?? '')) {
      try {
        await devices.renameOnDevice(n);
      } catch (_) {}
    }
    await cleanUp();
  }

  /// Ends every session and puts back anything that was only a test. Safe to
  /// call more than once; run on every way out.
  Future<void>? _cleaning;

  Future<void> cleanUp() => _cleaning ??= _cleanUp();

  Future<void> _cleanUp() async {
    if (_cleaned) return;
    _cleaned = true;
    _gen++;
    _stopGuided();
    _cancelFind?.call();
    _cancelFind = null;
    await _endTest();
    if (!wrote && !(_snapshot?.needsRestore ?? false)) await _forgetSnapshot();
    // Back onto the normal network; a slow answer must not hold anyone up.
    unawaited(wifi.release().catchError((Object _) {}));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final away = state != AppLifecycleState.resumed;
    if (away == !_resumed) return;
    _resumed = !away;
    if (away) {
      _suspended = _isTest(_step) || _step == SetupStep.look;
      unawaited(_endTest());
    } else if (_suspended) {
      _suspended = false;
      if (_isTest(_step)) unawaited(_prepareTest());
      if (_step == SetupStep.look) unawaited(_startLook());
    }
  }

  @override
  void dispose() {
    if (!_disposed) {
      _disposed = true;
      WidgetsBinding.instance.removeObserver(this);
      _guidedTimer?.cancel();
      _chase?.cancel();
      _cancelFind?.call();
      final client = _client, setup = _setupClientCache;
      // Best effort: the device must not stay in a test state.
      unawaited(
        cleanUp().whenComplete(() {
          client?.close();
          setup?.close();
        }),
      );
    }
    super.dispose();
  }
}
