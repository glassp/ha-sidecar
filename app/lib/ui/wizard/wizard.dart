import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../ha/sidecar_client.dart';
import '../../health.dart';
import '../../permissions.dart';
import '../../platform/kiosk_platform.dart';
import '../design.dart';
import '../pairing.dart';
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
  const _Step(this.id, {this.skippable = false});
  final String id;
  final bool skippable;
  String get label => 'wiz.step.$id'.tr();
}

class _WizardScreenState extends State<WizardScreen>
    with WidgetsBindingObserver {
  int _index = 0;
  AppController get c => widget.controller;

  List<_Step> get _steps => [
    const _Step('welcome'),
    const _Step('connect'),
    const _Step('mode'),
    if (c.setupMode == 'kiosk') ...const [
      _Step('companion', skippable: true),
      _Step('dashboard'),
      _Step('pin'),
      _Step('protection', skippable: true),
    ],
    const _Step('permissions', skippable: true),
    if (c.setupMode == 'kiosk') ...const [
      _Step('startup', skippable: true),
      _Step('display', skippable: true),
    ],
    const _Step('done'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (c.settings.isPaired) _index = 2; // resume where the user left off
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

  void _next() =>
      setState(() => _index = (_index + 1).clamp(0, _steps.length - 1));
  void _back() =>
      setState(() => _index = (_index - 1).clamp(0, _steps.length - 1));

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
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: kContentWidth,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'wiz.progress'.tr(
                                    namedArgs: {
                                      'n': '${index + 1}',
                                      'total': '${steps.length}',
                                    },
                                  ),
                                  style: t.textTheme.labelLarge?.copyWith(
                                    color: t.colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '· ${step.label}',
                                  style: t.textTheme.labelLarge?.copyWith(
                                    color: t.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: (index + 1) / steps.length,
                                minHeight: 6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: kContentWidth,
                        ),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: _body(step.id, link),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: t.colorScheme.outlineVariant.withValues(
                            alpha: .5,
                          ),
                        ),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: kContentWidth,
                        ),
                        child: Row(
                          children: [
                            if (index > 0)
                              TextButton(
                                onPressed: _back,
                                child: Text('common.back'.tr()),
                              ),
                            const Spacer(),
                            if (step.skippable)
                              TextButton(
                                onPressed: _next,
                                child: Text('wiz.skip'.tr()),
                              ),
                            const SizedBox(width: 8),
                            if (!last)
                              FilledButton(
                                onPressed: ok ? _next : null,
                                child: Text(
                                  index == 0
                                      ? 'wiz.get_started'.tr()
                                      : 'common.continue'.tr(),
                                ),
                              ),
                            if (last) ..._finishButtons(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _finishButtons() {
    final kiosk = c.setupMode == 'kiosk';
    final problems = computeIssues(
      c,
      c.link?.value ?? LinkState.disconnected,
      (_, _) {},
    ).where((i) => i.severity == Severity.problem);
    return [
      if (kiosk)
        OutlinedButton(
          onPressed: problems.isEmpty
              ? () async {
                  await toggleLockdown(context, c, true);
                  await c.completeSetup();
                }
              : null,
          child: Text('wiz.lock_now'.tr()),
        ),
      const SizedBox(width: 8),
      FilledButton(
        onPressed: c.completeSetup,
        child: Text('wiz.open_app'.tr()),
      ),
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

/// Shared look of a step: big icon (or the brand logo), headline, intro, content.
class _Frame extends StatelessWidget {
  const _Frame({
    required this.icon,
    required this.title,
    required this.intro,
    this.children = const [],
    this.logo = false,
  });
  final IconData icon;
  final String title;
  final String intro;
  final List<Widget> children;
  final bool logo;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (logo)
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.asset('assets/brand/icon.png', width: 72, height: 72),
          )
        else
          IconBadge(icon, size: 64),
        const SizedBox(height: 20),
        Text(
          title,
          style: t.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          intro,
          style: t.textTheme.bodyLarge?.copyWith(
            color: t.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        ...children,
      ],
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.icon, this.titleKey, this.textKey);
  final IconData icon;
  final String titleKey;
  final String textKey;
  @override
  Widget build(BuildContext context) =>
      Tile(icon: icon, title: titleKey.tr(), subtitle: textKey.tr());
}

// ------------------------------------------------------------------------------ steps

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep();
  @override
  Widget build(BuildContext context) => _Frame(
    icon: Icons.tablet_mac,
    logo: true,
    title: 'wiz.welcome.title'.tr(),
    intro: 'wiz.welcome.intro'.tr(),
    children: const [
      GroupCard(
        children: [
          _Bullet(
            Icons.lock_outline,
            'wiz.welcome.b1_title',
            'wiz.welcome.b1_text',
          ),
          _Bullet(
            Icons.brightness_6_outlined,
            'wiz.welcome.b2_title',
            'wiz.welcome.b2_text',
          ),
          _Bullet(Icons.alarm, 'wiz.welcome.b3_title', 'wiz.welcome.b3_text'),
        ],
      ),
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
  late final _url = TextEditingController(
    text: widget.controller.settings.haUrl.isEmpty
        ? 'http://homeassistant.local:8123'
        : widget.controller.settings.haUrl,
  );
  late final _token = TextEditingController(
    text: widget.controller.settings.token,
  );
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
      LinkState.connected => (
        'wiz.connect.ok'.tr(),
        Semantic.ok,
        Icons.check_circle,
      ),
      LinkState.connecting => (
        'link.connecting'.tr(),
        Semantic.warn,
        Icons.sync,
      ),
      LinkState.authFailed => (
        'wiz.connect.rejected'.tr(),
        Semantic.bad,
        Icons.error_outline,
      ),
      LinkState.disconnected => (
        'wiz.connect.not_yet'.tr(),
        Semantic.bad,
        Icons.link_off,
      ),
    };
    return _Frame(
      icon: Icons.hub_outlined,
      title: 'wiz.connect.title'.tr(),
      intro: 'wiz.connect.intro'.tr(),
      children: [
        const GroupCard(
          children: [
            _Bullet(
              Icons.looks_one_outlined,
              'wiz.connect.s1_title',
              'wiz.connect.s1_text',
            ),
            _Bullet(
              Icons.looks_two_outlined,
              'wiz.connect.s2_title',
              'wiz.connect.s2_text',
            ),
            _Bullet(
              Icons.looks_3_outlined,
              'wiz.connect.s3_title',
              'wiz.connect.s3_text',
            ),
          ],
        ),
        const SizedBox(height: 24),
        PairingPanel(controller: widget.controller),
        const SizedBox(height: 16),
        Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                statusText,
                style: t.textTheme.bodyMedium?.copyWith(color: color),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text('wiz.connect.manual_title'.tr()),
          subtitle: Text('wiz.connect.manual_text'.tr()),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          children: [
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'wiz.connect.address'.tr(),
                prefixIcon: const Icon(Icons.language),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _token,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'wiz.connect.token'.tr(),
                prefixIcon: const Icon(Icons.key_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _connect,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link),
                  label: Text(
                    connected
                        ? 'wiz.connect.reconnect'.tr()
                        : 'wiz.connect.connect'.tr(),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Row(
                    children: [
                      Icon(icon, color: color, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          statusText,
                          style: t.textTheme.bodyMedium?.copyWith(color: color),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.icon,
    required this.title,
    required this.text,
    required this.selected,
    required this.onTap,
  });
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
      color: selected
          ? t.colorScheme.primaryContainer
          : t.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: selected ? t.colorScheme.primary : Colors.transparent,
          width: 2,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              IconBadge(icon, size: 52),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(text, style: t.textTheme.bodyMedium),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: t.colorScheme.primary,
              ),
            ],
          ),
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
    title: 'wiz.mode.title'.tr(),
    intro: 'wiz.mode.intro'.tr(),
    children: [
      _Choice(
        icon: Icons.tablet_mac,
        title: 'wiz.mode.kiosk_title'.tr(),
        text: 'wiz.mode.kiosk_text'.tr(),
        selected: controller.setupMode == 'kiosk',
        onTap: () => controller.setSetupMode('kiosk'),
      ),
      _Choice(
        icon: Icons.smartphone,
        title: 'wiz.mode.extras_title'.tr(),
        text: 'wiz.mode.extras_text'.tr(),
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
      title: 'wiz.companion.title'.tr(),
      intro: 'wiz.companion.intro'.tr(),
      children: [
        GroupCard(
          children: [
            Tile(
              icon: found.isEmpty
                  ? Icons.download_outlined
                  : Icons.check_circle,
              color: found.isEmpty ? Semantic.warn : Semantic.ok,
              title: found.isEmpty
                  ? 'wiz.companion.missing'.tr()
                  : 'wiz.companion.installed'.tr(),
              subtitle: found.isEmpty
                  ? 'wiz.companion.missing_text'.tr()
                  : found
                        .map(
                          (p) => p.endsWith('.minimal')
                              ? 'wiz.companion.minimal'.tr()
                              : 'wiz.companion.full'.tr(),
                        )
                        .join(', '),
              trailing: found.isEmpty
                  ? FilledButton.tonal(
                      onPressed: controller.refresh,
                      child: Text('wiz.companion.check_again'.tr()),
                    )
                  : null,
            ),
            const _Bullet(
              Icons.login,
              'wiz.companion.b1_title',
              'wiz.companion.b1_text',
            ),
            const _Bullet(
              Icons.fullscreen,
              'wiz.companion.b2_title',
              'wiz.companion.b2_text',
            ),
          ],
        ),
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
    title: 'wiz.dashboard.title'.tr(),
    intro: 'wiz.dashboard.intro'.tr(),
    children: [
      GroupCard(
        children: [
          DashboardSetting(
            controller: controller,
            configKey: 'kiosk_dashboard',
            icon: Icons.dashboard_outlined,
            required: true,
            title: 'settings.kiosk_dashboard.title'.tr(),
            help: 'settings.kiosk_dashboard.help'.tr(),
            value: (controller.status.cfg['kiosk_dashboard'] ?? '') as String,
          ),
        ],
      ),
      HelpText('wiz.dashboard.example'.tr()),
      HelpText('wiz.dashboard.later'.tr()),
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
      title: 'wiz.pin.title'.tr(),
      intro: 'wiz.pin.intro'.tr(),
      children: [
        GroupCard(
          children: [
            Tile(
              icon: has ? Icons.check_circle : Icons.pin_outlined,
              color: has ? Semantic.ok : null,
              title: has ? 'wiz.pin.is_set'.tr() : 'wiz.pin.not_set'.tr(),
              trailing: FilledButton.tonal(
                onPressed: () => showPinDialog(context, controller),
                child: Text(has ? 'wiz.pin.change'.tr() : 'pin.set'.tr()),
              ),
            ),
            const _Bullet(
              Icons.touch_app_outlined,
              'wiz.pin.b1_title',
              'wiz.pin.b1_text',
            ),
            const _Bullet(
              Icons.cloud_outlined,
              'wiz.pin.b2_title',
              'wiz.pin.b2_text',
            ),
          ],
        ),
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
      title: 'wiz.protection.title'.tr(),
      intro: 'wiz.protection.intro'.tr(),
      children: [
        GroupCard(
          children: [
            Tile(
              icon: Icons.verified_user_outlined,
              color: s.deviceOwner ? Semantic.ok : null,
              title: 'sheet.protection.owner_title'.tr(),
              subtitle: s.deviceOwner
                  ? 'owner.active_desc'.tr()
                  : 'wiz.protection.owner_text'.tr(),
              trailing: s.deviceOwner
                  ? Pill(
                      'owner.active'.tr(),
                      color: Semantic.ok,
                      icon: Icons.check,
                    )
                  : null,
            ),
            Tile(
              icon: Icons.accessibility_new,
              color: s.accessibilityEnabled ? Semantic.ok : null,
              title: 'prot.accessibility'.tr(),
              subtitle: 'wiz.protection.guard_text'.tr(),
              trailing: s.accessibilityEnabled
                  ? Pill(
                      'common.on'.tr(),
                      color: Semantic.ok,
                      icon: Icons.check,
                    )
                  : FilledButton.tonal(
                      onPressed: () =>
                          controller.platform.openSettings('accessibility'),
                      child: Text('common.turn_on'.tr()),
                    ),
            ),
          ],
        ),
        if (!s.deviceOwner) ...[
          SectionTitle('wiz.protection.command'.tr()),
          const CopyBlock(
            'adb shell dpm set-device-owner dev.glassp.ha_sidecar/.SidecarDeviceAdminReceiver',
          ),
          HelpText('wiz.protection.command_help'.tr()),
        ],
        if (s.mode == EnforcementMode.none)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: HelpText('wiz.protection.none'.tr()),
          ),
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
      if (!kiosk && (p.id == 'overlay' || p.id == 'accessibility')) {
        return false;
      }
      if (p.id == 'accessibility' && s.deviceOwner) return false;
      return true;
    }).toList();
    return _Frame(
      icon: Icons.admin_panel_settings_outlined,
      title: 'wiz.permissions.title'.tr(),
      intro: 'wiz.permissions.intro'.tr(),
      children: [
        GroupCard(
          children: [
            for (final p in specs)
              PermissionRow(spec: p, controller: controller, showWhy: true),
          ],
        ),
        HelpText('wiz.permissions.skip_help'.tr()),
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
      title: 'wiz.startup.title'.tr(),
      intro: 'wiz.startup.intro'.tr(),
      children: [
        GroupCard(
          children: [
            SwitchSetting(
              icon: Icons.home_outlined,
              title: 'settings.home_app.title'.tr(),
              subtitle: !s.kioskLauncher
                  ? 'wiz.startup.recommended'.tr()
                  : s.isHomeApp
                  ? 'home.active'.tr()
                  : s.deviceOwner
                  ? 'home.applying'.tr()
                  : 'home.choose'.tr(),
              value: s.kioskLauncher,
              onChanged: (v) async {
                await controller.platform.setKioskLauncher(v);
                if (v && !s.deviceOwner) {
                  await controller.platform.openSettings('home');
                }
                await controller.refresh();
              },
            ),
          ],
        ),
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
      title: 'wiz.display.title'.tr(),
      intro: 'wiz.display.intro'.tr(),
      children: [
        _Choice(
          icon: Icons.brightness_auto,
          title: 'wiz.display.smart_title'.tr(),
          text: 'wiz.display.smart_text'.tr(),
          selected: auto,
          onTap: () async {
            await controller.setConfig('mode', 'auto');
            await controller.setConfig('auto_dim', true);
            await controller.setConfig('night_light', true);
          },
        ),
        _Choice(
          icon: Icons.brightness_medium,
          title: 'wiz.display.manual_title'.tr(),
          text: 'wiz.display.manual_text'.tr(),
          selected: !auto,
          onTap: () => controller.setConfig('mode', 'manual'),
        ),
        if (auto && !s.writeSettingsGranted)
          GroupCard(
            children: [
              PermissionRow(
                spec: permissionSpecs.firstWhere(
                  (p) => p.id == 'write_settings',
                ),
                controller: controller,
                showWhy: true,
              ),
            ],
          ),
        if (auto) HelpText('wiz.display.note'.tr()),
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
    final issues = computeIssues(
      controller,
      controller.link?.value ?? LinkState.disconnected,
      (_, _) {},
    );
    final problems = issues
        .where((i) => i.severity == Severity.problem)
        .toList();
    return _Frame(
      icon: problems.isEmpty ? Icons.check_circle_outline : Icons.flag_outlined,
      title: problems.isEmpty
          ? 'wiz.done.title_ok'.tr()
          : 'wiz.done.title_open'.tr(),
      intro: problems.isEmpty
          ? (kiosk ? 'wiz.done.intro_kiosk'.tr() : 'wiz.done.intro_extras'.tr())
          : 'wiz.done.intro_open'.tr(),
      children: [
        if (problems.isNotEmpty)
          GroupCard(
            children: [
              for (final i in problems)
                Tile(
                  icon: i.icon,
                  color: Semantic.warn,
                  title: i.title,
                  subtitle: i.detail,
                ),
            ],
          ),
      ],
    );
  }
}
