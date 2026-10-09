import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../ha/sidecar_client.dart';
import '../platform/kiosk_platform.dart';
import 'allowlist_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.controller});
  final AppController controller;

  DeviceStatus get s => controller.status;
  KioskPlatform get platform => controller.platform;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('HA Sidecar')),
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _connectionCard(context),
            _enforcementCard(context),
            _kioskCard(context),
            _alarmsCard(context),
            _updateCard(context),
            const Card(
              child: ListTile(
                leading: Icon(Icons.mic_none),
                title: Text('Voice assistant'),
                subtitle: Text('Planned: Assist satellite with on-device wake word. See docs/ROADMAP.md.'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _connectionCard(BuildContext context) {
    final link = controller.link;
    return Card(
      child: ValueListenableBuilder<LinkState>(
        valueListenable: link ?? ValueNotifier(LinkState.disconnected),
        builder: (context, state, _) => ListTile(
          leading: Icon(state == LinkState.connected ? Icons.link : Icons.link_off),
          title: Text(switch (state) {
            LinkState.connected => 'Connected',
            LinkState.connecting => 'Connecting…',
            LinkState.authFailed => 'Token rejected - re-pair',
            LinkState.disconnected => 'Disconnected',
          }),
          subtitle: Text(controller.settings.haUrl),
          trailing: TextButton(onPressed: controller.unpair, child: const Text('Unpair')),
        ),
      ),
    );
  }

  Widget _enforcementCard(BuildContext context) {
    Widget row(String label, bool ok, {String? fix, String? kind, String? note}) => ListTile(
          dense: true,
          leading: Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked, color: ok ? Colors.green : null),
          title: Text(label),
          subtitle: note == null ? null : Text(note),
          trailing: !ok && kind != null ? TextButton(onPressed: () => platform.openSettings(kind), child: Text(fix ?? 'Grant')) : null,
        );

    final modeText = switch (s.mode) {
      EnforcementMode.deviceOwner => 'Device owner (lock-task mode)',
      EnforcementMode.accessibility => 'Accessibility fallback',
      EnforcementMode.none => 'No enforcement available',
    };
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(title: const Text('Enforcement'), subtitle: Text(modeText)),
          row('Device owner', s.deviceOwner,
              note: 'adb shell dpm set-device-owner dev.glassp.ha_sidecar/.SidecarDeviceAdminReceiver'),
          row('Accessibility guard', s.accessibilityEnabled, kind: 'accessibility', fix: 'Enable',
              note: 'Fallback when not device owner; also reports the foreground app'),
          row('Draw over other apps', s.overlayGranted, kind: 'overlay',
              note: 'PIN hot corner + launching the HA app from the background'),
          row('Modify system settings', s.writeSettingsGranted, kind: 'write_settings', note: 'Remote brightness'),
        ],
      ),
    );
  }

  Widget _kioskCard(BuildContext context) {
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('Lockdown'),
            subtitle: Text(s.hasPin
                ? 'Target: ${s.targetPackage ?? 'HA companion app not found'}. Exit: tap top-left corner 5×, enter PIN.'
                : 'Set a PIN first'),
            value: s.lockdown,
            onChanged: (on) => _toggleLockdown(context, on),
          ),
          ListTile(
            title: Text(s.hasPin ? 'Change PIN' : 'Set PIN'),
            leading: const Icon(Icons.pin_outlined),
            onTap: () => _setPin(context),
          ),
          ListTile(
            title: const Text('Allowed apps'),
            subtitle: Text('${s.allowlist.length} selected (+ HA app, keyboard)'),
            leading: const Icon(Icons.apps),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AllowlistScreen(controller: controller))),
          ),
          SwitchListTile(
            title: const Text('Act as home app'),
            subtitle: Text(!s.kioskLauncher
                ? 'Starts on boot and re-opens the HA app when it exits or Home is pressed'
                : s.isHomeApp
                    ? 'Active: this is the default home app'
                    : s.deviceOwner
                        ? 'Applying…'
                        : 'Also choose "HA Sidecar" as the default home app in Android settings'),
            value: s.kioskLauncher,
            onChanged: (v) async {
              await platform.setKioskLauncher(v);
              if (v && !s.deviceOwner) await platform.openSettings('home');
              await controller.refresh();
            },
          ),
          SwitchListTile(
            title: const Text('Keep screen on'),
            value: s.keepScreenOn,
            onChanged: (v) async {
              await platform.setKeepScreenOn(v);
              await controller.refresh();
            },
          ),
        ],
      ),
    );
  }

  Widget _alarmsCard(BuildContext context) {
    return Card(
      child: Column(
        children: [
          ListTile(
            title: const Text('Alarms'),
            trailing: IconButton(icon: const Icon(Icons.add_alarm), onPressed: () => _addAlarm(context)),
          ),
          for (final a in controller.alarms)
            SwitchListTile(
              title: Text('${a.hour.toString().padLeft(2, '0')}:${a.minute.toString().padLeft(2, '0')}  ${a.label}'),
              subtitle: Text(a.days.isEmpty ? 'Once' : a.days.map((d) => const ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'][d - 1]).join(' ')),
              value: a.enabled,
              onChanged: (v) async {
                await platform.upsertAlarm(AlarmSpec(
                  id: a.id, hour: a.hour, minute: a.minute, days: a.days,
                  label: a.label, enabled: v, snoozeMinutes: a.snoozeMinutes,
                ));
                await controller.refresh();
              },
              secondary: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  await platform.removeAlarm(a.id);
                  await controller.refresh();
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _updateCard(BuildContext context) {
    final pending = s.pendingUpdate;
    return Card(
      child: ListTile(
        leading: Icon(pending != null ? Icons.system_update : Icons.verified_outlined),
        title: Text(pending != null ? 'OS update available' : 'Android ${s.androidRelease}'),
        subtitle: Text(s.deviceOwner
            ? 'Security patch ${s.securityPatch}'
            : 'Security patch ${s.securityPatch}. Update detection needs device owner.'),
        trailing: TextButton(onPressed: () => platform.openSettings('system_update'), child: const Text('Open')),
      ),
    );
  }

  Future<void> _toggleLockdown(BuildContext context, bool on) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await platform.setLockdown(on);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not change lockdown: $e')));
    }
    await controller.refresh();
  }

  Future<void> _setPin(BuildContext context) async {
    final field = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New PIN (4+ digits)'),
        content: TextField(controller: field, keyboardType: TextInputType.number, obscureText: true, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, field.text), child: const Text('Save')),
        ],
      ),
    );
    if (pin != null && pin.length >= 4) {
      await platform.setPin(pin);
      await controller.refresh();
    }
  }

  Future<void> _addAlarm(BuildContext context) async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (t == null) return;
    await platform.upsertAlarm(AlarmSpec(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      hour: t.hour,
      minute: t.minute,
    ));
    await controller.refresh();
  }
}
