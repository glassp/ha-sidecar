import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../ha/sidecar_client.dart';
import '../../health.dart';
import '../../permissions.dart';
import '../../platform/kiosk_platform.dart';
import '../design.dart';
import '../dialogs.dart';
import '../setting_widgets.dart';

/// First-run guide: connect, choose what this device is for, then each thing the kiosk needs.
class WizardScreen extends StatefulWidget {
  const WizardScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<WizardScreen> createState() => _WizardScreenState();
}

class _Step {
  const _Step(this.id, this.label, {this.skippable = false});
  final String id;
  final String label;
  final bool skippable;
}

class _WizardScreenState extends State<WizardScreen> with WidgetsBindingObserver {
  int _index = 0;
  AppController get c => widget.controller;

  List<_Step> get _steps => [
        const _Step('welcome', 'Welcome'),
        const _Step('connect', 'Connect'),
        const _Step('mode', 'Purpose'),
        if (c.setupMode == 'kiosk') ...const [
          _Step('companion', 'Home Assistant app', skippable: true),
          _Step('dashboard', 'Dashboard'),
          _Step('pin', 'PIN'),
          _Step('protection', 'Protection', skippable: true),
        ],
        const _Step('permissions', 'Permissions', skippable: true),
        if (c.setupMode == 'kiosk') ...const [
          _Step('startup', 'Start-up', skippable: true),
          _Step('display', 'Display', skippable: true),
        ],
        const _Step('done', 'Done'),
      ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // resume where the user left off if already paired
    if (c.settings.isPaired) _index = 2;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) c.refresh();
  }

  bool _canContinue(String id, LinkState link) {
    final s = c.status;
    return switch (id) {
      'connect' => link == LinkState.connected,
      'dashboard' => ((s.cfg['kiosk_dashboard'] ?? '') as String).isNotEmpty,
      'pin' => s.hasPin,
      _ => true,
    };
  }

  void _next() => setState(() => _index = (_index + 1).clamp(0, _steps.length - 1));
  void _back() => setState(() => _index = (_index - 1).clamp(0, _steps.length - 1));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => ValueListenableBuilder<LinkState>(
        valueListenable: c.link ?? ValueNotifier(LinkState.disconnected),
        builder: (context, link, _) {
          final steps = _steps;
          final index = _index.clamp(0, steps.length - 1);
          final step = steps[index];
          final last = index == steps.length - 1;
          final ok = _canContinue(step.id, link);
          final t = Theme.of(context);
          return Scaffold(
            body: SafeArea(
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: kContentWidth),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text('Step ${index + 1} of ${steps.length}', style: t.textTheme.labelLarge?.copyWith(color: t.colorScheme.primary)),
                          const SizedBox(width: 8),
                          Text('· ${step.label}', style: t.textTheme.labelLarge?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                        ]),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(value: (index + 1) / steps.length, minHeight: 6),
                        ),
                      ]),
                    ),
                  ),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: kContentWidth),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                        child: _body(step.id, link),
                      ),
                    ),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: t.colorScheme.outlineVariant.withValues(alpha: .5)))),
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: kContentWidth),
                      child: Row(children: [
                        if (index > 0) TextButton(onPressed: _back, child: const Text('Back')),
                        const Spacer(),
                        if (step.skippable)
                          TextButton(onPressed: _next, child: const Text('Skip for now')),
                        const SizedBox(width: 8),
                        if (!last) FilledButton(onPressed: ok ? _next : null, child: Text(index == 0 ? 'Get started' : 'Continue')),
                        if (last) ..._finishButtons(),
                      ]),
                    ),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _finishButtons() {
    final kiosk = c.setupMode == 'kiosk';
    final problems = computeIssues(c, c.link?.value ?? LinkState.disconnected, (_, _) {}).where((i) => i.severity == Severity.problem);
    return [
      if (kiosk)
        OutlinedButton(
          onPressed: problems.isEmpty
              ? () async {
                  await toggleLockdown(context, c, true);
                  await c.completeSetup();
                }
              : null,
          child: const Text('Lock the kiosk now'),
        ),
      const SizedBox(width: 8),
      FilledButton(onPressed: c.completeSetup, child: const Text('Open the app')),
    ];
  }

  Widget _body(String id, LinkState link) => switch (id) {
        'welcome' => const _WelcomeStep(),
        'connect' => _ConnectStep(controller: c, link: link),
        'mode' => _ModeStep(controller: c),
        'companion' => _CompanionStep(controller: c),
        'dashboard' => _DashboardStep(controller: c),
        'pin' => _PinStep(controller: c),
        'protection' => _ProtectionStep(controller: c),
        'permissions' => _PermissionsStep(controller: c),
        'startup' => _StartupStep(controller: c),
        'display' => _DisplayStep(controller: c),
        _ => _DoneStep(controller: c),
      };
}

/// Shared look of a step: big icon, headline, intro, content.
class _Frame extends StatelessWidget {
  const _Frame({required this.icon, required this.title, required this.intro, this.children = const []});
  final IconData icon;
  final String title;
  final String intro;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      IconBadge(icon, size: 64),
      const SizedBox(height: 20),
      Text(title, style: t.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Text(intro, style: t.textTheme.bodyLarge?.copyWith(color: t.colorScheme.onSurfaceVariant)),
      const SizedBox(height: 24),
      ...children,
    ]);
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.icon, this.title, this.text);
  final IconData icon;
  final String title;
  final String text;
  @override
  Widget build(BuildContext context) => Tile(icon: icon, title: title, subtitle: text);
}

// ------------------------------------------------------------------------------ steps

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep();
  @override
  Widget build(BuildContext context) => _Frame(
        icon: Icons.tablet_mac,
        title: 'Turn this tablet into a Home Assistant display',
        intro: 'HA Sidecar adds what the Home Assistant app does not: a lockable kiosk, smart brightness, alarms and extra sensors. '
            'Setup takes about five minutes.',
        children: const [
          GroupCard(children: [
            _Bullet(Icons.lock_outline, 'Kiosk lock', 'Keeps your dashboard on screen. Leave it with a PIN.'),
            _Bullet(Icons.brightness_6_outlined, 'Smart brightness', 'Dims when idle, night light when someone walks past.'),
            _Bullet(Icons.alarm, 'Alarms and sensors', 'Alarms that Home Assistant can set, plus touch, camera and security sensors.'),
          ]),
        ],
      );
}

class _ConnectStep extends StatefulWidget {
  const _ConnectStep({required this.controller, required this.link});
  final AppController controller;
  final LinkState link;
  @override
  State<_ConnectStep> createState() => _ConnectStepState();
}

class _ConnectStepState extends State<_ConnectStep> {
  late final _url = TextEditingController(text: widget.controller.settings.haUrl.isEmpty ? 'http://homeassistant.local:8123' : widget.controller.settings.haUrl);
  late final _token = TextEditingController(text: widget.controller.settings.token);
  bool _busy = false;

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() => _busy = true);
    await widget.controller.pair(_url.text.trim(), _token.text.trim());
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final connected = widget.link == LinkState.connected;
    final (statusText, color, icon) = switch (widget.link) {
      LinkState.connected => ('Connected to Home Assistant', Semantic.ok, Icons.check_circle),
      LinkState.connecting => ('Connecting…', Semantic.warn, Icons.sync),
      LinkState.authFailed => ('Home Assistant rejected the token. Check it and try again.', Semantic.bad, Icons.error_outline),
      LinkState.disconnected => ('Not connected yet', Semantic.bad, Icons.link_off),
    };
    return _Frame(
      icon: Icons.hub_outlined,
      title: 'Connect to Home Assistant',
      intro: 'This tablet talks to the HA Sidecar integration in Home Assistant.',
      children: [
        GroupCard(children: const [
          _Bullet(Icons.looks_one_outlined, 'Install the integration', 'In HACS add the HA Sidecar repository (Custom repositories → Integration) and restart Home Assistant.'),
          _Bullet(Icons.looks_two_outlined, 'Add this tablet', 'Settings → Devices & services → Add integration → HA Sidecar. Name the tablet.'),
          _Bullet(Icons.looks_3_outlined, 'Copy the token', 'Home Assistant shows a pairing token. Enter it below with the address of your server.'),
        ]),
        const SizedBox(height: 24),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: InputDecoration(labelText: 'Home Assistant address', prefixIcon: const Icon(Icons.language), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _token,
          autocorrect: false,
          decoration: InputDecoration(labelText: 'Pairing token', prefixIcon: const Icon(Icons.key_outlined), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))),
        ),
        const SizedBox(height: 16),
        Row(children: [
          FilledButton.icon(
            onPressed: _busy ? null : _connect,
            icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.link),
            label: Text(connected ? 'Reconnect' : 'Connect'),
          ),
          const SizedBox(width: 16),
          Expanded(child: Row(children: [Icon(icon, color: color, size: 20), const SizedBox(width: 8), Expanded(child: Text(statusText, style: t.textTheme.bodyMedium?.copyWith(color: color)))])),
        ]),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.icon, required this.title, required this.text, required this.selected, required this.onTap});
  final IconData icon;
  final String title;
  final String text;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: selected ? t.colorScheme.primaryContainer : t.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: selected ? t.colorScheme.primary : Colors.transparent, width: 2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            IconBadge(icon, size: 52),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: t.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(text, style: t.textTheme.bodyMedium),
              ]),
            ),
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: t.colorScheme.primary),
          ]),
        ),
      ),
    );
  }
}

class _ModeStep extends StatelessWidget {
  const _ModeStep({required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) => _Frame(
        icon: Icons.dashboard_customize_outlined,
        title: 'What is this device for?',
        intro: 'You can change this later by running the setup again.',
        children: [
          _Choice(
            icon: Icons.tablet_mac,
            title: 'Wall display (kiosk)',
            text: 'A tablet that permanently shows a Home Assistant dashboard, locked with a PIN.',
            selected: controller.setupMode == 'kiosk',
            onTap: () => controller.setSetupMode('kiosk'),
          ),
          _Choice(
            icon: Icons.smartphone,
            title: 'Sensors and alarms only',
            text: 'A phone or tablet you also use normally. No lock; Home Assistant gets extra sensors and can set alarms.',
            selected: controller.setupMode == 'extras',
            onTap: () => controller.setSetupMode('extras'),
          ),
        ],
      );
}

class _CompanionStep extends StatelessWidget {
  const _CompanionStep({required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final found = controller.status.companionPackages;
    return _Frame(
      icon: Icons.home_work_outlined,
      title: 'The Home Assistant app',
      intro: 'The kiosk shows your dashboard with the official Home Assistant companion app. HA Sidecar keeps it on screen.',
      children: [
        GroupCard(children: [
          Tile(
            icon: found.isEmpty ? Icons.download_outlined : Icons.check_circle,
            color: found.isEmpty ? Semantic.warn : Semantic.ok,
            title: found.isEmpty ? 'Not installed yet' : 'Installed',
            subtitle: found.isEmpty
                ? 'Install "Home Assistant" from Google Play, or the minimal build from the Home Assistant GitHub / F-Droid.'
                : found.map((p) => p.endsWith('.minimal') ? 'Minimal build' : 'Full build').join(', '),
            trailing: found.isEmpty ? FilledButton.tonal(onPressed: controller.refresh, child: const Text('Check again')) : null,
          ),
          const _Bullet(Icons.login, 'Sign in', 'Open the app once, sign in to your server and let it finish loading. Then come back here.'),
          const _Bullet(Icons.fullscreen, 'Fullscreen', 'In its settings, turn on fullscreen so no bars show. Do not set it as the launcher; HA Sidecar does that.'),
        ]),
      ],
    );
  }
}

class _DashboardStep extends StatelessWidget {
  const _DashboardStep({required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) => _Frame(
        icon: Icons.dashboard_outlined,
        title: 'Which dashboard stays on screen?',
        intro: 'Open the dashboard in a browser, copy its address and paste it here. Only the path is kept.',
        children: [
          GroupCard(children: [
            DashboardSetting(
              controller: controller,
              configKey: 'kiosk_dashboard',
              icon: Icons.dashboard_outlined,
              required: true,
              title: 'Main dashboard (kiosk)',
              help: 'Opened after a restart, when you press Home and when the lock starts.',
              value: (controller.status.cfg['kiosk_dashboard'] ?? '') as String,
            ),
          ]),
          const HelpText('Example: https://home.example.org/lovelace/wall-panel  →  lovelace/wall-panel'),
          const HelpText('You can add an idle dashboard (weather, temperatures) later under Kiosk → Dashboards.'),
        ],
      );
}

class _PinStep extends StatelessWidget {
  const _PinStep({required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final has = controller.status.hasPin;
    return _Frame(
      icon: Icons.pin_outlined,
      title: 'Choose a PIN',
      intro: 'The PIN is the only way to leave the locked kiosk on the tablet itself.',
      children: [
        GroupCard(children: [
          Tile(
            icon: has ? Icons.check_circle : Icons.pin_outlined,
            color: has ? Semantic.ok : null,
            title: has ? 'PIN is set' : 'No PIN yet',
            trailing: FilledButton.tonal(onPressed: () => showPinDialog(context, controller), child: Text(has ? 'Change' : 'Set PIN')),
          ),
          const _Bullet(Icons.touch_app_outlined, 'How to unlock', 'On the locked screen tap the top-left corner 5 times, then enter the PIN. After 5 wrong tries there is a short waiting time.'),
          const _Bullet(Icons.cloud_outlined, 'From Home Assistant', 'You can also unlock remotely from Home Assistant. Remote locking needs a PIN to exist.'),
        ]),
      ],
    );
  }
}

class _ProtectionStep extends StatelessWidget {
  const _ProtectionStep({required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final s = controller.status;
    return _Frame(
      icon: Icons.shield_outlined,
      title: 'How strong should the lock be?',
      intro: 'Android has two ways to keep other apps away from the dashboard. Device owner is strongest; the accessibility guard works on any tablet.',
      children: [
        GroupCard(children: [
          Tile(
            icon: Icons.verified_user_outlined,
            color: s.deviceOwner ? Semantic.ok : null,
            title: 'Device owner (strongest)',
            subtitle: s.deviceOwner
                ? 'Active: Android hides and blocks the system UI itself.'
                : 'Needs a factory-reset tablet with no accounts and a one-time computer command. Optional.',
            trailing: s.deviceOwner ? const Pill('Active', color: Semantic.ok, icon: Icons.check) : null,
          ),
          Tile(
            icon: Icons.accessibility_new,
            color: s.accessibilityEnabled ? Semantic.ok : null,
            title: 'Accessibility guard',
            subtitle: 'Sends other apps and the notification shade away within a moment. Does not read your screen.',
            trailing: s.accessibilityEnabled
                ? const Pill('On', color: Semantic.ok, icon: Icons.check)
                : FilledButton.tonal(onPressed: () => controller.platform.openSettings('accessibility'), child: const Text('Turn on')),
          ),
        ]),
        if (!s.deviceOwner) ...[
          const SectionTitle('Device owner command'),
          const CopyBlock('adb shell dpm set-device-owner dev.glassp.ha_sidecar/.SidecarDeviceAdminReceiver'),
          const HelpText('Run it once on a computer with the tablet connected by USB debugging. It cannot be undone except by a factory reset.'),
        ],
        if (s.mode == EnforcementMode.none)
          const Padding(padding: EdgeInsets.only(top: 16), child: HelpText('Without either, the kiosk cannot be locked.')),
      ],
    );
  }
}

class _PermissionsStep extends StatelessWidget {
  const _PermissionsStep({required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final kiosk = controller.setupMode == 'kiosk';
    final s = controller.status;
    final specs = permissionSpecs.where((p) {
      if (!kiosk && (p.id == 'overlay' || p.id == 'accessibility')) return false;
      if (p.id == 'accessibility' && s.deviceOwner) return false;
      return true;
    }).toList();
    return _Frame(
      icon: Icons.admin_panel_settings_outlined,
      title: 'Allow what the kiosk needs',
      intro: 'Tap Grant, follow the Android screen that opens, then come back. This list updates by itself.',
      children: [
        GroupCard(children: [for (final p in specs) PermissionRow(spec: p, controller: controller, showWhy: true)]),
        const HelpText('You can skip anything and finish it later; the Home screen lists what is still missing.'),
      ],
    );
  }
}

class _StartupStep extends StatelessWidget {
  const _StartupStep({required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final s = controller.status;
    return _Frame(
      icon: Icons.home_outlined,
      title: 'Start by itself',
      intro: 'Let HA Sidecar be the home app. After a reboot, or if the Home Assistant app closes or crashes, Android returns to HA Sidecar, which opens the dashboard again.',
      children: [
        GroupCard(children: [
          SwitchSetting(
            icon: Icons.home_outlined,
            title: 'Start automatically',
            subtitle: !s.kioskLauncher
                ? 'Recommended for a wall display.'
                : s.isHomeApp
                    ? 'Active.'
                    : s.deviceOwner
                        ? 'Applying…'
                        : 'Now choose "HA Sidecar" as the default home app in the Android screen.',
            value: s.kioskLauncher,
            onChanged: (v) async {
              await controller.platform.setKioskLauncher(v);
              if (v && !s.deviceOwner) await controller.platform.openSettings('home');
              await controller.refresh();
            },
          ),
        ]),
      ],
    );
  }
}

class _DisplayStep extends StatelessWidget {
  const _DisplayStep({required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final s = controller.status;
    final auto = (s.cfg['mode'] ?? 'manual') != 'manual';
    return _Frame(
      icon: Icons.brightness_6_outlined,
      title: 'Brightness',
      intro: 'Should the display manage its own brightness? Every detail can be fine-tuned later under Display.',
      children: [
        _Choice(
          icon: Icons.brightness_auto,
          title: 'Smart brightness',
          text: 'Bright by day, dims when nobody uses it, very dim at night with a night light when someone walks past.',
          selected: auto,
          onTap: () async {
            await controller.setConfig('mode', 'auto');
            await controller.setConfig('auto_dim', true);
            await controller.setConfig('night_light', true);
          },
        ),
        _Choice(
          icon: Icons.brightness_medium,
          title: 'Leave brightness alone',
          text: 'The sidecar never changes the screen brightness.',
          selected: !auto,
          onTap: () => controller.setConfig('mode', 'manual'),
        ),
        if (auto && !s.writeSettingsGranted)
          GroupCard(children: [PermissionRow(spec: permissionSpecs.firstWhere((p) => p.id == 'write_settings'), controller: controller, showWhy: true)]),
        if (auto) const HelpText('Night hours are 22:00 to 06:30 by default. Presence sensors are chosen in the Home Assistant integration options.'),
      ],
    );
  }
}

class _DoneStep extends StatelessWidget {
  const _DoneStep({required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final kiosk = controller.setupMode == 'kiosk';
    final issues = computeIssues(controller, controller.link?.value ?? LinkState.disconnected, (_, _) {});
    final problems = issues.where((i) => i.severity == Severity.problem).toList();
    return _Frame(
      icon: problems.isEmpty ? Icons.check_circle_outline : Icons.flag_outlined,
      title: problems.isEmpty ? 'You are all set' : 'Almost there',
      intro: problems.isEmpty
          ? (kiosk ? 'Lock the kiosk now, or open the app first and look around. You can change everything later, and search finds any setting.' : 'Home Assistant now gets sensors and can set alarms on this device.')
          : 'A few things are still open. You can finish them later from the Home screen.',
      children: [
        if (problems.isNotEmpty)
          GroupCard(children: [
            for (final i in problems) Tile(icon: i.icon, color: Semantic.warn, title: i.title, subtitle: i.detail),
          ]),
      ],
    );
  }
}
