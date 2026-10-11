// StepLayout takes its body before the action buttons, in reading order.
// ignore_for_file: sort_child_properties_last

import 'package:flutter/material.dart';

import '../../features/device/setup/setup_controller.dart';
import '../../features/device/widgets/common.dart';
import '../../wled/discovery.dart';
import '../design/parts.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../onboarding/search_step.dart';
import 'setup_parts.dart';

/// "Is your device on your Wi-Fi?": two big choices.
class ConnectScreen extends StatelessWidget {
  const ConnectScreen({super.key, required this.controller});

  final SetupController controller;

  @override
  Widget build(BuildContext context) => StepLayout(
    title: 'Is your device on your Wi-Fi?',
    line: 'Plug it in first. Glyph can find it either way.',
    children: [
      _Choice(
        icon: Icons.wifi_sharp,
        title: 'Yes, it\'s on my Wi-Fi',
        line: 'Find it on your network',
        onTap: controller.chooseOnWifi,
      ),
      const SizedBox(height: 12),
      _Choice(
        icon: Icons.power_sharp,
        title: 'No, it\'s new',
        line: 'Connect to it and add it to your Wi-Fi',
        onTap: controller.chooseNew,
      ),
    ],
  );
}

class _Choice extends StatelessWidget {
  const _Choice({required this.icon, required this.title, required this.line, required this.onTap});

  final IconData icon;
  final String title, line;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '$title. $line',
    excludeSemantics: true,
    onTap: onTap,
    child: LbPanel(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: Lb.text2, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: LbType.heading),
                const SizedBox(height: 4),
                Text(line, style: LbType.small),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_sharp, color: Lb.text3),
        ],
      ),
    ),
  );
}

/// "Connect to your device": the assisted system dialog, or the guided
/// "join it in Wi-Fi settings" steps.
class JoinScreen extends StatelessWidget {
  const JoinScreen({super.key, required this.controller});

  final SetupController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final guided = c.showGuided;
    final name = c.networkName, pw = c.networkPassword;
    return StepLayout(
      title: guided ? 'Join it in Wi-Fi settings' : 'Connect to your device',
      line: guided ? null : 'Plug it in. It makes its own Wi-Fi network, usually called WLED-AP.',
      gap: guided ? 16 : 24,
      children: [
        if (guided) ...[
          _StepLine('1. Open Wi-Fi settings'),
          _StepLine('2. Join $name. The password is $pw.'),
          _StepLine('3. Come back to Glyph.'),
          const SizedBox(height: 20),
          Row(
            children: [
              const LedSpinner(),
              const SizedBox(width: 12),
              Flexible(child: Text('Waiting for your device…', style: LbType.small)),
            ],
          ),
        ] else
          LbPanel(
            child: Column(
              children: [
                _Kv('Network', name),
                const SizedBox(height: 8),
                _Kv('Password', pw),
              ],
            ),
          ),
        if (c.joinError != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(c.joinError!, style: LbType.small.copyWith(color: Lb.danger)),
          ),
        AnimatedSize(
          duration: Lb.fast,
          curve: Lb.ease,
          alignment: Alignment.topCenter,
          child: c.advancedOpen ? _RenamedFields(controller: c) : const SizedBox(width: double.infinity),
        ),
      ],
      primary: guided
          ? SetupPrimary('Open Wi-Fi settings', onPressed: c.openWifiSettings)
          : SetupPrimary('Connect', busy: c.joinBusy, onPressed: c.connectAssisted),
      secondary: !guided && c.assisted ? SetupSecondary('Use Wi-Fi settings instead', onPressed: c.useGuided) : null,
      link: SetupLink('Renamed its network?', onPressed: () => c.setAdvancedOpen(!c.advancedOpen)),
    );
  }
}

class _StepLine extends StatelessWidget {
  const _StepLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(text, style: LbType.body),
  );
}

class _Kv extends StatelessWidget {
  const _Kv(this.k, this.v);

  final String k, v;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(width: 92, child: MonoLabel(k)),
      Expanded(child: Text(v, style: LbType.mono.copyWith(color: Lb.text))),
    ],
  );
}

class _RenamedFields extends StatefulWidget {
  const _RenamedFields({required this.controller});

  final SetupController controller;

  @override
  State<_RenamedFields> createState() => _RenamedFieldsState();
}

class _RenamedFieldsState extends State<_RenamedFields> {
  late final _name = TextEditingController(text: widget.controller.setupSsid);
  late final _pw = TextEditingController(text: widget.controller.setupSsid.isEmpty ? '' : widget.controller.setupPassword);

  @override
  void dispose() {
    _name.dispose();
    _pw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Column(
      children: [
        TextField(
          controller: _name,
          style: LbType.body,
          decoration: fieldDecoration('Network name'),
          onChanged: (v) => widget.controller.setSetupNetwork(ssid: v),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pw,
          style: LbType.body,
          decoration: fieldDecoration('Network password'),
          onChanged: (v) => widget.controller.setSetupNetwork(password: v),
        ),
      ],
    ),
  );
}

/// "Which Wi-Fi should it join?": the device's own scan, strongest first.
class WifiScreen extends StatelessWidget {
  const WifiScreen({super.key, required this.controller});

  final SetupController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return StepLayout(
      title: 'Which Wi-Fi should it join?',
      line: c.setupName.isEmpty ? null : 'Connected to ${c.setupName}.',
      gap: 16,
      children: [
        if (c.scanning && c.networks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                const LedSpinner(),
                const SizedBox(width: 12),
                Flexible(child: Text('Looking for networks…', style: LbType.small)),
              ],
            ),
          ),
        for (final n in c.networks)
          Padding(
            key: ValueKey('net-${n.ssid}'),
            padding: const EdgeInsets.only(bottom: 8),
            child: _NetworkRow(
              ssid: n.ssid,
              rssi: n.rssi,
              secure: n.secure,
              selected: !c.otherSelected && c.selectedSsid == n.ssid,
              onTap: () => c.pickNetwork(n),
              field: n.secure ? _PasswordField(onChanged: c.setPassword) : null,
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _NetworkRow(
            ssid: 'Other network',
            selected: c.otherSelected,
            onTap: c.pickOther,
            field: Column(
              children: [
                TextField(
                  style: LbType.body,
                  autofocus: true,
                  decoration: fieldDecoration('Network name'),
                  onChanged: c.setOtherSsid,
                ),
                const SizedBox(height: 10),
                _PasswordField(onChanged: c.setPassword, autofocus: false),
              ],
            ),
          ),
        ),
        if (c.wifiError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(c.wifiError!, style: LbType.small.copyWith(color: Lb.danger)),
          ),
        const SizedBox(height: 4),
        const Note(
          color: Lb.phosphor,
          lit: true,
          text: 'Your device needs 2.4 GHz Wi-Fi. If yours isn\'t listed, it may only be 5 GHz.',
        ),
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(Lb.touch, Lb.touch), foregroundColor: Lb.text2),
          onPressed: c.scanning ? null : c.scan,
          child: const Text('Scan again'),
        ),
      ],
      primary: SetupPrimary('Join', onPressed: c.canJoin ? c.joinNetwork : null),
    );
  }
}

class _NetworkRow extends StatelessWidget {
  const _NetworkRow({
    required this.ssid,
    required this.selected,
    required this.onTap,
    this.rssi,
    this.secure = true,
    this.field,
  });

  final String ssid;
  final int? rssi;
  final bool secure, selected;
  final VoidCallback onTap;
  final Widget? field;

  static int bars(int rssi) => rssi > -60 ? 3 : (rssi > -75 ? 2 : 1);

  @override
  Widget build(BuildContext context) {
    final r = rssi;
    final signal = r == null ? null : switch (bars(r)) {
      3 => 'strong',
      2 => 'fair',
      _ => 'weak',
    };
    return Material(
      color: selected ? Lb.raised : Lb.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Lb.rPanel),
        side: BorderSide(color: selected ? Lb.text2 : Lb.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            selected: selected,
            label: '$ssid${signal == null ? '' : ', $signal signal'}${secure ? '' : ', open'}',
            excludeSemantics: true,
            onTap: onTap,
            child: InkWell(
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      if (r != null) ...[SignalDots(bars: bars(r)), const SizedBox(width: 14)],
                      Expanded(child: Text(ssid, maxLines: 2, overflow: TextOverflow.ellipsis, style: LbType.bodyStrong)),
                      if (r != null && secure) const Icon(Icons.lock_sharp, size: 16, color: Lb.text2),
                    ],
                  ),
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: Lb.fast,
            curve: Lb.ease,
            alignment: Alignment.topCenter,
            child: selected && field != null
                ? Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 14), child: field)
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// Signal strength as three LED dots.
class SignalDots extends StatelessWidget {
  const SignalDots({super.key, required this.bars});

  final int bars;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < 3; i++)
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(right: 3),
          decoration: BoxDecoration(shape: BoxShape.circle, color: i < bars ? Lb.text : Lb.ledOff),
        ),
    ],
  );
}

class _PasswordField extends StatefulWidget {
  const _PasswordField({required this.onChanged, this.autofocus = true});

  final ValueChanged<String> onChanged;
  final bool autofocus;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _show = false;

  @override
  Widget build(BuildContext context) => TextField(
    autofocus: widget.autofocus,
    obscureText: !_show,
    enableSuggestions: false,
    autocorrect: false,
    style: LbType.body,
    decoration: fieldDecoration(
      'Wi-Fi password',
      suffix: IconButton(
        tooltip: _show ? 'Hide password' : 'Show password',
        icon: Icon(_show ? Icons.visibility_off_sharp : Icons.visibility_sharp, size: 20),
        onPressed: () => setState(() => _show = !_show),
      ),
    ),
    onChanged: widget.onChanged,
  );
}

/// "Joining {ssid}…" then "Looking for it on your Wi-Fi…".
class JoiningScreen extends StatelessWidget {
  const JoiningScreen({super.key, required this.controller});

  final SetupController controller;

  @override
  Widget build(BuildContext context) {
    final sending = controller.joinPhase == JoinPhase.sending;
    return StepLayout(
      title: 'Joining ${controller.joiningSsid}',
      children: [
        StepStatusRow(
          label: 'Sent the Wi-Fi details',
          state: sending ? ProgressState.current : ProgressState.done,
        ),
        StepStatusRow(
          label: 'Looking for it on your Wi-Fi…',
          state: sending ? ProgressState.waiting : ProgressState.current,
        ),
        Text('This can take up to a minute.', style: LbType.small),
      ],
    );
  }
}

/// "Couldn't find it on {ssid}": likely causes and the way on.
class JoinFailedScreen extends StatelessWidget {
  const JoinFailedScreen({super.key, required this.controller, required this.services});

  final SetupController controller;
  final SetupServices services;

  Future<void> _address(BuildContext context) async {
    final d = await showModalBottomSheet<DiscoveredDevice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddressSheet(probe: services.probe),
    );
    if (d == null || !context.mounted) return;
    final err = await controller.connectAddress(d);
    if (err != null && context.mounted) toast(context, err);
  }

  @override
  Widget build(BuildContext context) => StepLayout(
    title: 'Couldn\'t find it on ${controller.joiningSsid}',
    line: 'Here\'s what usually causes that.',
    gap: 16,
    children: const [
      Note(
        color: Lb.phosphor,
        lit: true,
        text: 'The password may be wrong. Your device opens its own network again in about 30 seconds.',
      ),
      Note(color: Lb.phosphor, lit: true, text: 'It may be too far from your router.'),
      Note(color: Lb.phosphor, lit: true, text: 'Your Wi-Fi may be 5 GHz only.'),
    ],
    primary: SetupPrimary('Try again', onPressed: controller.retryJoin),
    secondary: SetupSecondary('Enter its address', onPressed: () => _address(context)),
  );
}
