import 'package:glyph/features/device/setup/setup_wifi.dart';

class FakeSetupWifi implements SetupWifi {
  FakeSetupWifi({this.assisted = true, this.result = const SetupWifiConnected('WLED-AP')});

  @override
  bool assisted;
  SetupWifiResult result;
  final List<({String? ssid, String prefix, String password})> connects = [];
  int releases = 0;
  int settingsOpened = 0;
  int binds = 0;

  @override
  Future<SetupWifiResult> connect({
    String? ssid,
    String prefix = 'WLED',
    String password = 'wled1234',
  }) async {
    connects.add((ssid: ssid, prefix: prefix, password: password));
    return result;
  }

  @override
  Future<void> release() async => releases++;

  @override
  Future<void> openSettings() async => settingsOpened++;

  @override
  Future<bool> bindCurrentWifi() async {
    binds++;
    return true;
  }
}
