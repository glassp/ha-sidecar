import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'ha/sidecar_client.dart';
import 'permissions.dart';
import 'platform/kiosk_platform.dart';

enum Severity { problem, suggestion }

class Issue {
  const Issue({required this.id, required this.severity, required this.title, required this.detail, required this.icon, required this.fixLabel, required this.fix});
  final String id;
  final Severity severity;
  final String title;
  final String detail;
  final IconData icon;
  final String fixLabel;
  final void Function(BuildContext) fix;
}

/// Everything that stops the kiosk from working properly, in the order it should be fixed.
/// [goTo] navigates to a settings entry/section (provided by the shell).
List<Issue> computeIssues(AppController c, LinkState link, void Function(BuildContext, String) goTo) {
  final s = c.status;
  final kiosk = c.setupMode == 'kiosk';
  final issues = <Issue>[];

  if (link != LinkState.connected) {
    issues.add(Issue(
      id: 'link',
      severity: Severity.problem,
      title: link == LinkState.authFailed ? 'Home Assistant rejected the token' : 'Not connected to Home Assistant',
      detail: link == LinkState.authFailed
          ? 'Create a new pairing token in the integration and pair again.'
          : 'Remote control, sensors and alarms in Home Assistant need the connection. Local features keep working.',
      icon: Icons.link_off,
      fixLabel: 'Connection',
      fix: (ctx) => goTo(ctx, 'connection'),
    ));
  }

  if (kiosk) {
    if (s.companionPackages.isEmpty) {
      issues.add(Issue(
        id: 'companion',
        severity: Severity.problem,
        title: 'Home Assistant app not installed',
        detail: 'The kiosk shows your dashboard with the official Home Assistant companion app. Install it and sign in.',
        icon: Icons.apps_outlined,
        fixLabel: 'Details',
        fix: (ctx) => goTo(ctx, 'companion_app'),
      ));
    }
    if (((s.cfg['kiosk_dashboard'] ?? '') as String).isEmpty) {
      issues.add(Issue(
        id: 'dashboard',
        severity: Severity.problem,
        title: 'Choose the kiosk dashboard',
        detail: 'Paste the address of the dashboard that should stay on screen. Lockdown needs it.',
        icon: Icons.dashboard_outlined,
        fixLabel: 'Set dashboard',
        fix: (ctx) => goTo(ctx, 'kiosk_dashboard'),
      ));
    }
    if (!s.hasPin) {
      issues.add(Issue(
        id: 'pin',
        severity: Severity.problem,
        title: 'Set a PIN',
        detail: 'The PIN is the only way to leave the locked kiosk on the tablet.',
        icon: Icons.pin_outlined,
        fixLabel: 'Set PIN',
        fix: (ctx) => goTo(ctx, 'pin'),
      ));
    }
    if (s.mode == EnforcementMode.none) {
      issues.add(Issue(
        id: 'protection',
        severity: Severity.problem,
        title: 'No kiosk protection available',
        detail: 'Turn on the accessibility guard, or make this tablet a device owner for the strongest lock.',
        icon: Icons.shield_outlined,
        fixLabel: 'Protection',
        fix: (ctx) => goTo(ctx, 'protection'),
      ));
    }
  }

  for (final p in permissionSpecs) {
    if (p.granted(s)) continue;
    if (p.id == 'accessibility' && (s.deviceOwner || !kiosk)) continue; // optional with device owner / in extras mode
    if (p.id == 'overlay' && !kiosk) continue;
    if (p.id == 'write_settings' && ((s.cfg['mode'] ?? 'manual') == 'manual')) continue;
    issues.add(Issue(
      id: 'perm_${p.id}',
      severity: p.required || p.id == 'write_settings' ? Severity.problem : Severity.suggestion,
      title: 'Allow: ${p.title}',
      detail: p.why,
      icon: p.icon,
      fixLabel: p.grantLabel,
      fix: (ctx) => p.grant(c),
    ));
  }

  if (kiosk && !s.kioskLauncher) {
    issues.add(Issue(
      id: 'home_app',
      severity: Severity.suggestion,
      title: 'Start automatically after a restart',
      detail: 'Act as the home app so the kiosk comes back after a reboot or when the Home Assistant app closes.',
      icon: Icons.home_outlined,
      fixLabel: 'Turn on',
      fix: (ctx) async {
        await c.platform.setKioskLauncher(true);
        if (!s.deviceOwner) await c.platform.openSettings('home');
        await c.refresh();
      },
    ));
  }
  return issues;
}
