import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../app/playback.dart';
import '../../library/catalog.dart';
import '../../library/user_library.dart';
import '../actions.dart';
import '../scope.dart';
import 'channels.dart';

/// Picking a look wakes a device that was switched off from Display's power
/// key. The request goes out before streaming starts; a failure is left to
/// the stream (or the next tap) to surface.
void wakeDevice(BuildContext context) {
  final d = AppScope.of(context).devices;
  if (!d.isConnected || d.isOn != false) return;
  unawaited(d.setPower(true).catchError((Object _) {}));
}

/// The remote's state: which channel you're surfing, which way the last
/// change went (for the caption slide), and the Surprise shuffle.
class TuneController extends ChangeNotifier {
  TuneController(this._channel, {required this.playback, required this.library, Random? random})
      : _random = random ?? Random();

  final PlaybackController playback;
  final UserLibrary library;
  final Random _random;

  Channel _channel;
  int _index = 0;
  int _direction = 1;
  bool _shuffling = false;
  Timer? _shuffleTimer;

  /// Called when a tile tunes in, with the tile's global rect, so the screen
  /// can fly the look up to the Stage.
  void Function(Rect from, TuneEntry entry)? onTunedFrom;

  Channel get channel => _channel;

  /// +1 when the last change went forward, -1 backward.
  int get direction => _direction;

  /// True while the Surprise slot machine spins.
  bool get shuffling => _shuffling;

  /// Position of what's playing in the channel, or -1 if it came from
  /// elsewhere (Make, a game…).
  int get position => _channel.indexOfPlaying(playback);

  TuneEntry? get current {
    final i = position;
    return i < 0 ? null : _channel.items[i];
  }

  /// Makes [channel] the surf order without playing anything (e.g. on open).
  void adopt(Channel channel, {int index = 0}) {
    _channel = channel;
    _index = index;
    notifyListeners();
  }

  /// Tunes in to [entry] and makes [channel] the surf order.
  Future<void> tune(BuildContext context, Channel channel, TuneEntry entry) {
    _cancelShuffle();
    _channel = channel;
    final i = channel.items.indexOf(entry);
    _direction = i >= _index ? 1 : -1;
    _index = max(0, i);
    notifyListeners();
    wakeDevice(context);
    return entry.play(context);
  }

  /// Next (+1) or previous (-1) in the current channel.
  Future<void> surf(BuildContext context, int dir) async {
    if (_shuffling) return;
    final items = _channel.items;
    if (items.isEmpty) return;
    final at = position;
    final from = at >= 0 ? at : (dir > 0 ? _index - 1 : _index + 1);
    _index = (from + dir) % items.length;
    if (_index < 0) _index += items.length;
    _direction = dir;
    notifyListeners();
    wakeDevice(context);
    await items[_index].play(context);
  }

  /// AHA #7: a slot-machine spin through random looks (~700 ms, slowing
  /// down like a reel) that lands on a pick, which starts a "Surprise"
  /// channel so swiping keeps the randomness going.
  void surprise(BuildContext context, Catalog catalog) {
    if (_shuffling || catalog.items.isEmpty) return;
    final picks = surprisePicks(catalog, _random, avoid: playback.item?.generatorId);
    if (picks.isEmpty) return;
    final reel = surprisePicks(catalog, _random, count: 12);
    // Gaps between reel stops; ~735 ms in all.
    const steps = [40, 45, 50, 60, 70, 85, 105, 130, 150];
    _shuffling = true;
    _direction = 1;
    notifyListeners();
    var k = 0;
    void step() {
      if (!context.mounted) return _cancelShuffle();
      if (k < steps.length) {
        playback.playItem(reel[k % max(1, reel.length)]);
        HapticFeedback.selectionClick();
        _shuffleTimer = Timer(Duration(milliseconds: steps[k++]), step);
        return;
      }
      _shuffleTimer = null;
      _shuffling = false;
      _channel = Channel(id: 'surprise', name: 'Surprise', items: [for (final i in picks) ItemEntry(i)]);
      _index = 0;
      HapticFeedback.mediumImpact();
      notifyListeners();
      wakeDevice(context);
      GlyphActions.play(context, picks.first);
    }

    step();
  }

  void _cancelShuffle() {
    _shuffleTimer?.cancel();
    _shuffleTimer = null;
    if (_shuffling) {
      _shuffling = false;
      notifyListeners();
    }
  }

  /// Hearts what's playing (library looks only).
  bool toggleFavourite() {
    final item = playback.item;
    if (item == null) return false;
    library.toggleFavourite(item.id);
    return library.isFavourite(item.id);
  }

  @override
  void dispose() {
    _shuffleTimer?.cancel();
    super.dispose();
  }
}

/// Hands the [TuneController] to tiles, rails and pages.
class TuneScope extends InheritedNotifier<TuneController> {
  const TuneScope({super.key, required TuneController controller, required super.child})
      : super(notifier: controller);

  static TuneController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TuneScope>()!.notifier!;

  static TuneController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<TuneScope>()!.notifier!;
}
