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
import '../../../wled/panel_setup.dart';
import '../../../wled/device.dart' show WledInfo;
import '../../../wled/wled_client.dart';
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
  size,
  wiringQ1,
  wiringQ2,
  wiringQ3,
  wiringResult,
  wiringManual,
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

bool _isTest(SetupStep s) =>
    s == SetupStep.wiringQ1 || s == SetupStep.wiringQ2 || s == SetupStep.wiringQ3;

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
    if (from == SetupStep.wiringQ1) wiringNote = null;
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
      case SetupStep.wiringQ1 || SetupStep.wiringQ2 || SetupStep.wiringQ3:
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
      SetupStep.check || SetupStep.pin || SetupStep.unsupported || SetupStep.size => root,
      SetupStep.wiringQ1 => SetupStep.size,
      SetupStep.wiringQ2 => SetupStep.wiringQ1,
      SetupStep.wiringQ3 => SetupStep.wiringQ2,
      SetupStep.wiringResult => _lastQuestion,
      SetupStep.wiringManual => SetupStep.wiringResult,
      SetupStep.review => SetupStep.wiringResult,
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
    host = d.host;
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
      await _setupClient.joinWifi(ssid, psk);
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
    host = found.host;
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
      final s = await client.setupState(checkLock: true);
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
    final w = s.width, h = s.height, wiring = s.wiring;
    if (w != null && h != null && wiring != null && s.isConfigured(DisplaySetup(w, h, wiring))) {
      fastPath = true;
      _go(SetupStep.look);
    } else {
      fastPath = false;
      _go(SetupStep.size);
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

  int? draftWidth, draftHeight;
  PanelWiring? draftWiring;

  void _initDraft(DeviceSetupState s) {
    if (draftWidth != null) return;
    final w = s.width, h = s.height;
    if (s.isMatrix && w != null && h != null) {
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
  int get draftLeds => (draftWidth ?? 0) * (draftHeight ?? 0);
  bool get changesLeds => hasSize && deviceLeds != draftLeds;

  /// A tile or the steppers picked a size.
  void setSize(int w, int h, {bool click = true}) {
    if (click) HapticFeedback.selectionClick();
    final nw = w.clamp(1, _maxSide), nh = h.clamp(1, _maxSide);
    if (nw != draftWidth || nh != draftHeight) _resetAnswers();
    draftWidth = nw;
    draftHeight = nh;
    _notify();
  }

  void sizeNext() {
    if (!hasSize) return;
    _resetAnswers();
    _go(SetupStep.wiringQ1);
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

  void _resetAnswers() {
    answerCorner = null;
    answerAlongWidth = null;
    answerFarEnd = null;
    _askedRun = false;
    _askedJump = false;
  }

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
    _resetAnswers();
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

  void looksRight() {
    if (draftWiring == null) return;
    _go(SetupStep.review);
  }

  DisplaySetup? get draftSetup =>
      hasSize && draftWiring != null ? DisplaySetup(draftWidth!, draftHeight!, draftWiring!) : null;

  // --- Test session -------------------------------------------------------------

  SetupSession? _session;
  bool _testReady = false, _rlmOverridden = false, _suspended = false;
  int _testToken = 0;
  Timer? _chase;
  int _chaseAt = 0;
  Future<void> _ending = Future.value();

  bool get testRunning => _testReady;

  SetupSession _makeSession() => SetupSession(
    playback: playback,
    devices: devices,
    host: host!,
    client: client,
    senderFactory: _senderFactory,
    observeLifecycle: false,
  );

  Future<void> _prepareTest() async {
    if (_testReady) {
      _showTestPattern();
      return;
    }
    final token = ++_testToken;
    testError = null;
    await _ending;
    if (token != _testToken || _disposed) return;
    try {
      await _ensureSnapshot();
      if (token != _testToken) return;
      final s = state!;
      if (s.isMatrix && s.realtimeMaps) {
        await client.setRealtimeMaps(false);
        _rlmOverridden = true;
      }
      if (token != _testToken) {
        await _restoreRlm();
        return;
      }
      final session = _makeSession();
      await session.start();
      if (token != _testToken) {
        await session.end();
        await _restoreRlm();
        return;
      }
      _session = session;
      _testReady = true;
    } catch (_) {
      if (token != _testToken) return;
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
    _rlmOverridden = false;
    try {
      await client.setRealtimeMaps(true);
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
    final prev = _ending;
    return _ending = prev.then((_) async {
      try {
        await s?.end(width: width, height: height);
      } catch (_) {}
      await _restoreRlm();
    });
  }

  int get _ledCount {
    final n = state?.ledCount ?? 0;
    return n > 0 ? n : _w * _h;
  }

  void _showTestPattern() {
    final session = _session;
    if (session == null || !_testReady) return;
    _chase?.cancel();
    _chase = null;
    final n = _ledCount;
    testNeedsMoreLeds = false;
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
    final g = _gen;
    try {
      await _ensureSnapshot();
      wrote = true;
      await client.setLedCount(draftLeds, s.outputs.first);
      await _delay(settle);
      final play = _snapshot?.playback;
      if (play != null) {
        try {
          await client.restorePlayback(play);
        } catch (_) {}
      }
      final fresh = await client.setupState();
      if (_disposed || g != _gen) return;
      state = fresh;
      _showTestPattern();
    } catch (_) {
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
    final s = state!;
    final saved = devices.saved.where((d) => d.host == host).firstOrNull;
    Map<String, dynamic>? playback;
    try {
      playback = await client.state();
    } catch (_) {}
    final snap = SetupSnapshot.of(s,
        host: host!, appLayout: saved?.layout ?? MatrixLayout.identity, playback: playback);
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

  Frame get lookFrame => cornerCheckFrame(_w, _h);

  Future<void> _startLook() async {
    final token = ++_testToken;
    testError = null;
    await _ending;
    if (token != _testToken || _disposed) return;
    final session = _makeSession();
    try {
      await session.start();
    } catch (_) {
      if (token == _testToken) {
        testError = 'Couldn\'t show anything on your device. Is it still on and on the same Wi-Fi?';
        _notify();
      }
      return;
    }
    if (token != _testToken) {
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
    await _endTest(width: _w, height: _h);
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
      _go(SetupStep.size, dir: -1);
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
  Future<void> cleanUp() async {
    if (_cleaned) return;
    _cleaned = true;
    _gen++;
    _stopGuided();
    _cancelFind?.call();
    _cancelFind = null;
    await _endTest();
    if (!wrote && _snapshot != null) await _forgetSnapshot();
    // Back onto the normal network; a slow answer must not hold anyone up.
    unawaited(wifi.release().catchError((Object _) {}));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final away = state != AppLifecycleState.resumed;
    if (away == !_resumed) return;
    _resumed = !away;
    if (away) {
      if (_testReady || _session != null || _rlmOverridden) {
        _suspended = true;
        unawaited(_endTest());
      }
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
        (_cleaned ? Future<void>.value() : _cleanUpAfterDispose()).whenComplete(() {
          client?.close();
          setup?.close();
        }),
      );
    }
    super.dispose();
  }

  Future<void> _cleanUpAfterDispose() async {
    _cleaned = true;
    unawaited(wifi.release().catchError((Object _) {}));
    await _endTest();
    if (!wrote && _snapshot != null) await _forgetSnapshot();
  }
}
