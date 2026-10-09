import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'ha/sidecar_client.dart';
import 'permissions.dart';
import 'platform/kiosk_platform.dart';

enum Severity { problem, suggestion }

class Issue {
  const Issue({
    required this.id,
    required this.severity,
    required this.title,
    required this.detail,
    required this.icon,
    required this.fixLabel,
    required this.fix,
  });
  final String id;
  final Severity severity;
  final String title;
  final String detail;
  final IconData icon;
  final String fixLabel;
  final void Function(BuildContext) fix;
}

/// Everything that stops the kiosk from working properly, in the order it should be fixed.
/// [goTo] opens the settings group of an entry id (provided by the UI).
List<Issue> computeIssues(
  AppController c,
  LinkState link,
  void Function(BuildContext, String) goTo,
) {
  final s = c.status;
  final kiosk = c.setupMode == 'kiosk';
  final issues = <Issue>[];

  if (link != LinkState.connected) {
    final rejected = link == LinkState.authFailed;
    issues.add(
      Issue(
        id: 'link',
        severity: Severity.problem,
        title: rejected
            ? 'issue.link_rejected.title'.tr()
            : 'issue.link.title'.tr(),
        detail: rejected
            ? 'issue.link_rejected.detail'.tr()
            : 'issue.link.detail'.tr(),
        icon: Icons.link_off,
        fixLabel: 'issue.link.fix'.tr(),
        fix: (ctx) => goTo(ctx, 'connection'),
      ),
    );
  }

  if (kiosk) {
    if (s.companionPackages.isEmpty) {
      issues.add(
        Issue(
          id: 'companion',
          severity: Severity.problem,
          title: 'issue.companion.title'.tr(),
          detail: 'issue.companion.detail'.tr(),
          icon: Icons.apps_outlined,
          fixLabel: 'issue.companion.fix'.tr(),
          fix: (ctx) => goTo(ctx, 'companion_app'),
        ),
      );
    }
    if (((s.cfg['kiosk_dashboard'] ?? '') as String).isEmpty) {
      issues.add(
        Issue(
          id: 'dashboard',
          severity: Severity.problem,
          title: 'issue.dashboard.title'.tr(),
          detail: 'issue.dashboard.detail'.tr(),
          icon: Icons.dashboard_outlined,
          fixLabel: 'issue.dashboard.fix'.tr(),
          fix: (ctx) => goTo(ctx, 'kiosk_dashboard'),
        ),
      );
    }
    if (!s.hasPin) {
      issues.add(
        Issue(
          id: 'pin',
          severity: Severity.problem,
          title: 'issue.pin.title'.tr(),
          detail: 'issue.pin.detail'.tr(),
          icon: Icons.pin_outlined,
          fixLabel: 'issue.pin.fix'.tr(),
          fix: (ctx) => goTo(ctx, 'pin'),
        ),
      );
    }
    if (s.mode == EnforcementMode.none) {
      issues.add(
        Issue(
          id: 'protection',
          severity: Severity.problem,
          title: 'issue.protection.title'.tr(),
          detail: 'issue.protection.detail'.tr(),
          icon: Icons.shield_outlined,
          fixLabel: 'issue.protection.fix'.tr(),
          fix: (ctx) => goTo(ctx, 'protection'),
        ),
      );
    }
  }

  for (final p in permissionSpecs) {
    if (p.granted(s)) continue;
    final watchdogOn = s.cfg['watchdog'] == true;
    if (p.id == 'accessibility' && (s.deviceOwner || !kiosk) && !watchdogOn) {
      continue; // optional with device owner / in extras mode
    }
    if (p.id == 'overlay' && !kiosk) continue;
    if (p.id == 'write_settings' && ((s.cfg['mode'] ?? 'manual') == 'manual')) {
      continue;
    }
    issues.add(
      Issue(
        id: 'perm_${p.id}',
        severity: p.required || p.id == 'write_settings'
            ? Severity.problem
            : Severity.suggestion,
        title: 'issue.permission'.tr(namedArgs: {'name': p.title}),
        detail: p.why,
        icon: p.icon,
        fixLabel: 'perm.grant'.tr(),
        fix: (ctx) => p.grant(c),
      ),
    );
  }

  if (kiosk && !s.kioskLauncher) {
    issues.add(
      Issue(
        id: 'home_app',
        severity: Severity.suggestion,
        title: 'issue.home_app.title'.tr(),
        detail: 'issue.home_app.detail'.tr(),
        icon: Icons.home_outlined,
        fixLabel: 'issue.home_app.fix'.tr(),
        fix: (ctx) async {
          await c.platform.setKioskLauncher(true);
          if (!s.deviceOwner) await c.platform.openSettings('home');
          await c.refresh();
        },
      ),
    );
  }
  return issues;
}
