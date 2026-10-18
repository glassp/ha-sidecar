import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:beamer/beamer.dart';

import '../voice/voice_skin.dart';
import '../app_controller.dart';
import '../ha/sidecar_client.dart';
import '../permissions.dart';
import '../platform/kiosk_platform.dart';
import '../ui/design.dart';
import '../ui/dialogs.dart';
import '../ui/setting_widgets.dart';
import '../ui/pairing.dart';
import '../ui/wake_words_dialog.dart';
import 'connection_route.dart';
import 'connection_settings.dart';

/// Every setting in the app, in one list: the Kiosk/Display/System pages render it by section and
/// group, and the search screen filters it. A setting added here is automatically searchable.
/// Texts come from the translation files: `settings.<id>.title|desc|kw`.
enum Section {
  kiosk(Icons.lock_outline),
  display(Icons.brightness_6_outlined),
  system(Icons.tune);

  const Section(this.icon);
  final IconData icon;
  String get label => 'section.$name.title'.tr();
  String get subtitle => 'section.$name.subtitle'.tr();
}

class SettingEntry {
  const SettingEntry({
    required this.id,
    required this.section,
    required this.group,
    required this.title,
    required this.description,
    this.keywords = const [],
    required this.builder,
  });

  final String id;
  final Section section;
  final String group; // already translated
  final String title;
  final String description;
  final List<String> keywords;
  final Widget Function(BuildContext context) builder;

  String get breadcrumb => '${section.label} › $group';
}

String fmtSeconds(double s) {
  final v = s.round();
  if (v < 60) return '$v s';
  if (v < 3600) {
    final m = v ~/ 60;
    final r = v % 60;
    return r == 0 ? '$m min' : '$m min $r s';
  }
  return '${(v / 3600).toStringAsFixed(v % 3600 == 0 ? 0 : 1)} h';
}

String _t(String id, String part) => 'settings.$id.$part'.tr();
String _g(String key) => 'group.$key'.tr();

List<SettingEntry> buildRegistry(AppController c) {
  DeviceStatus s() => c.status;
  Map<String, dynamic> cfg() => c.status.cfg;
  num n(String k, num fallback) => (cfg()[k] ?? fallback) as num;
  bool b(String k) => cfg()[k] == true;
  String str(String k, String fallback) => (cfg()[k] ?? fallback) as String;
  List<String> kw(String id) => _t(
    id,
    'kw',
  ).split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  Future<void> set(BuildContext ctx, String key, Object v) async {
    final err = await c.setConfig(key, v);
    if (err != null && ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  SettingEntry base(
    String id,
    Section sec,
    String group,
    Widget Function(BuildContext) builder, {
    String? title,
  }) => SettingEntry(
    id: id,
    section: sec,
    group: group,
    title: title ?? _t(id, 'title'),
    description: _t(id, 'desc'),
    keywords: kw(id),
    builder: builder,
  );

  SettingEntry switchEntry(
    String id,
    Section sec,
    String group,
    IconData icon,
    String key, {
    Future<void> Function(BuildContext, bool)? onChanged,
  }) => base(
    id,
    sec,
    group,
    (ctx) => SwitchSetting(
      icon: icon,
      title: _t(id, 'title'),
      subtitle: _t(id, 'desc'),
      value: b(key),
      onChanged: (v) =>
          onChanged != null ? onChanged(ctx, v) : set(ctx, key, v),
    ),
  );

  SettingEntry sliderEntry(
    String id,
    Section sec,
    String group,
    IconData icon,
    String key, {
    required double min,
    required double max,
    required num fallback,
    int? divisions,
    String Function(double)? format,
    bool asDouble = false,

    /// A brightness level: stored as 0..255, shown as percent unless the developer option is on.
    bool brightness = false,
  }) => base(id, sec, group, (ctx) {
    if (brightness && !b('raw_brightness')) {
      return SliderSetting(
        icon: icon,
        title: _t(id, 'title'),
        subtitle: _t(id, 'desc'),
        value: brightnessPercent(n(key, fallback).round()).toDouble(),
        min: 0,
        max: 100,
        format: (v) => '${v.round()} %',
        onChanged: (v) => set(ctx, key, brightnessRaw(v.round())),
      );
    }
    return SliderSetting(
      icon: icon,
      title: _t(id, 'title'),
      subtitle: _t(id, 'desc'),
      value: n(key, fallback).toDouble(),
      min: min,
      max: max,
      divisions: divisions,
      format: format,
      onChanged: (v) => set(
        ctx,
        key,
        asDouble ? double.parse(v.toStringAsFixed(1)) : v.round(),
      ),
    );
  });

  SettingEntry timeEntry(String id, String key, IconData icon) => base(
    id,
    Section.display,
    _g('night'),
    (ctx) => TimeSetting(
      icon: icon,
      title: _t(id, 'title'),
      subtitle: _t(id, 'desc'),
      minutes: n(key, 0).toInt(),
      onChanged: (m) => set(ctx, key, m),
    ),
  );

  final dashboards = _g('dashboards');
  final lock = _g('lock');
  final start = _g('start_screen');
  final day = _g('day');
  final night = _g('night');
  final presence = _g('presence');
  final camera = _g('camera');

  return <SettingEntry>[
    // ---------------------------------------------------------------- Kiosk › Dashboards
    base(
      'kiosk_dashboard',
      Section.kiosk,
      dashboards,
      (ctx) => DashboardSetting(
        controller: c,
        configKey: 'kiosk_dashboard',
        icon: Icons.dashboard_outlined,
        required: true,
        title: _t('kiosk_dashboard', 'title'),
        help: _t('kiosk_dashboard', 'help'),
        value: str('kiosk_dashboard', ''),
      ),
    ),
    switchEntry(
      'glance_enabled',
      Section.kiosk,
      dashboards,
      Icons.wb_twilight,
      'glance',
    ),
    base(
      'glance_dashboard',
      Section.kiosk,
      dashboards,
      (ctx) => DashboardSetting(
        controller: c,
        configKey: 'glance_dashboard',
        icon: Icons.wb_twilight,
        title: _t('glance_dashboard', 'title'),
        help: _t('glance_dashboard', 'help'),
        value: str('glance_dashboard', ''),
      ),
    ),
    sliderEntry(
      'glance_after',
      Section.kiosk,
      dashboards,
      Icons.timer_outlined,
      'glance_after_s',
      min: 30,
      max: 3600,
      fallback: 300,
      format: fmtSeconds,
    ),

    // ---------------------------------------------------------------- Kiosk › Lock
    base('lockdown', Section.kiosk, lock, (ctx) {
      final st = s();
      final missing = [
        if (!st.hasPin) 'lock.need_pin'.tr(),
        if (((cfg()['kiosk_dashboard'] ?? '') as String).isEmpty)
          'lock.need_dashboard'.tr(),
        if (st.mode == EnforcementMode.none) 'lock.need_protection'.tr(),
      ];
      return SwitchSetting(
        icon: st.lockdown ? Icons.lock : Icons.lock_open,
        title: _t('lockdown', 'title'),
        subtitle: st.lockdown
            ? (st.allowlist.isEmpty
                  ? 'lock.locked_only_ha'.tr()
                  : 'lock.locked_with_allowed'.tr())
            : missing.isEmpty
            ? _t('lockdown', 'desc')
            : 'lock.first_setup'.tr(namedArgs: {'items': missing.join(', ')}),
        value: st.lockdown,
        onChanged: (v) => toggleLockdown(ctx, c, v),
      );
    }),
    base(
      'pin',
      Section.kiosk,
      lock,
      (ctx) => ActionSetting(
        icon: Icons.pin_outlined,
        title: s().hasPin ? 'pin.change'.tr() : 'pin.set'.tr(),
        subtitle: s().hasPin ? _t('pin', 'desc') : 'pin.required_desc'.tr(),
        trailing: s().hasPin
            ? Pill('common.set'.tr(), color: Semantic.ok, icon: Icons.check)
            : Pill(
                'common.required'.tr(),
                color: Semantic.warn,
                icon: Icons.priority_high,
              ),
        onTap: () => showPinDialog(ctx, c),
      ),
      title: s().hasPin ? 'pin.change'.tr() : 'pin.set'.tr(),
    ),
    base(
      'hot_corner',
      Section.kiosk,
      lock,
      (ctx) => SegmentedSetting(
        icon: Icons.touch_app_outlined,
        title: _t('hot_corner', 'title'),
        subtitle: _t('hot_corner', 'desc'),
        options: {
          for (final c in const [
            'bottom_left',
            'bottom_right',
            'top_left',
            'top_right',
          ])
            c: 'corner.$c'.tr(),
        },
        value: str('hot_corner', 'top_left'),
        onChanged: (v) => set(ctx, 'hot_corner', v),
      ),
    ),
    base(
      'allowed_apps',
      Section.kiosk,
      lock,
      (ctx) => ActionSetting(
        icon: Icons.apps,
        title: _t('allowed_apps', 'title'),
        subtitle: s().allowlist.isEmpty
            ? 'allowed.none'.tr()
            : 'allowed.count'.plural(s().allowlist.length),
        onTap: () => ctx.beamToNamed('/allowed-apps', stacked: false),
      ),
    ),
    base('protection', Section.kiosk, lock, (ctx) {
      final st = s();
      final (label, color, icon) = switch (st.mode) {
        EnforcementMode.deviceOwner => (
          'prot.device_owner'.tr(),
          Semantic.ok,
          Icons.verified_user,
        ),
        EnforcementMode.accessibility => (
          'prot.accessibility'.tr(),
          Semantic.warn,
          Icons.shield_outlined,
        ),
        EnforcementMode.none => (
          'prot.none'.tr(),
          Semantic.bad,
          Icons.gpp_maybe_outlined,
        ),
      };
      return ActionSetting(
        icon: icon,
        title: _t('protection', 'title'),
        subtitle: switch (st.mode) {
          EnforcementMode.deviceOwner => 'prot.device_owner_desc'.tr(),
          EnforcementMode.accessibility => 'prot.accessibility_desc'.tr(),
          EnforcementMode.none => 'prot.none_desc'.tr(),
        },
        color: color,
        trailing: Pill(label, color: color),
        onTap: () => showProtectionSheet(ctx, c),
      );
    }),

    // ---------------------------------------------------------------- Kiosk › Start & screen
    base('home_app', Section.kiosk, start, (ctx) {
      final st = s();
      final isHome = st.isHomeApp;
      // a status, not a switch: Android decides who the home app is, so this shows whether it is this app (and who it is if not)
      final current = st.homePackage.isEmpty || isHome
          ? ''
          : ' ${'home.current'.tr(namedArgs: {'package': st.homePackage})}';
      return ActionSetting(
        icon: Icons.home_outlined,
        title: _t('home_app', 'title'),
        subtitle: isHome
            ? 'home.active'.tr()
            : (!st.kioskLauncher
                      ? _t('home_app', 'desc')
                      : st.deviceOwner
                      ? 'home.applying'.tr()
                      : 'home.choose'.tr()) +
                  current,
        trailing: isHome
            ? Pill('home.is_home'.tr(), color: Semantic.ok, icon: Icons.check)
            : Pill('home.not_home'.tr(), color: Semantic.warn),
        onTap: () async {
          if (isHome && st.deviceOwner) {
            await c.platform.setKioskLauncher(
              false,
            ); // device owner pins it: this is how to give it up
          } else if (isHome) {
            await c.platform.openSettings(
              'home',
            ); // change the default home app in Android
          } else {
            await c.platform.setKioskLauncher(true);
            if (!st.deviceOwner) await c.platform.openSettings('home');
          }
          await c.refresh();
        },
      );
    }),
    base(
      'keep_screen_on',
      Section.kiosk,
      start,
      (ctx) => SwitchSetting(
        icon: Icons.light_mode_outlined,
        title: _t('keep_screen_on', 'title'),
        subtitle: _t('keep_screen_on', 'desc'),
        value: s().keepScreenOn,
        onChanged: (v) async {
          await c.platform.setKeepScreenOn(v);
          await c.refresh();
        },
      ),
    ),
    base('companion_app', Section.kiosk, start, (ctx) {
      final found = s().companionPackages;
      return ActionSetting(
        icon: Icons.home_work_outlined,
        title: _t('companion_app', 'title'),
        subtitle: found.isEmpty
            ? 'companion.missing'.tr()
            : 'companion.found'.tr(
                namedArgs: {
                  'builds': found
                      .map(
                        (p) => p.endsWith('.minimal')
                            ? 'companion.minimal'.tr()
                            : 'companion.full'.tr(),
                      )
                      .join(', '),
                },
              ),
        trailing: found.isEmpty
            ? Pill('companion.missing_pill'.tr(), color: Semantic.bad)
            : Pill(
                'companion.installed'.tr(),
                color: Semantic.ok,
                icon: Icons.check,
              ),
        onTap: () async {
          await c.refresh();
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              SnackBar(
                content: Text(
                  s().companionPackages.isEmpty
                      ? 'companion.still_missing'.tr()
                      : 'companion.now_found'.tr(),
                ),
              ),
            );
          }
        },
      );
    }),

    // ---------------------------------------------------------------- Kiosk › Watchdog
    switchEntry(
      'watchdog',
      Section.kiosk,
      _g('watchdog'),
      Icons.pets_outlined,
      'watchdog',
    ),
    base(
      'watchdog_action',
      Section.kiosk,
      _g('watchdog'),
      (ctx) => SegmentedSetting(
        icon: Icons.build_circle_outlined,
        title: _t('watchdog_action', 'title'),
        subtitle: _t('watchdog_action', 'desc'),
        options: {
          'restart': 'wd.action_restart'.tr(),
          'notify': 'wd.action_notify'.tr(),
        },
        value: str('watchdog_action', 'restart'),
        onChanged: (v) => set(ctx, 'watchdog_action', v),
      ),
    ),
    sliderEntry(
      'watchdog_probe',
      Section.kiosk,
      _g('watchdog'),
      Icons.timer_outlined,
      'watchdog_probe_s',
      min: 5,
      max: 300,
      fallback: 20,
      format: fmtSeconds,
    ),
    sliderEntry(
      'watchdog_startup',
      Section.kiosk,
      _g('watchdog'),
      Icons.hourglass_bottom,
      'watchdog_startup_s',
      min: 20,
      max: 600,
      fallback: 90,
      format: fmtSeconds,
    ),
    base('watchdog_status', Section.kiosk, _g('watchdog'), (ctx) {
      final w = c.status.watchdog;
      final state = (w['state'] ?? 'off') as String;
      final restarts = (w['restarts'] ?? 0) as int;
      final reason = w['last_reason'] as String?;
      return Tile(
        icon: Icons.monitor_heart_outlined,
        title: _t('watchdog_status', 'title'),
        subtitle: [
          'wd.state_$state'.tr(),
          if (restarts > 0)
            'wd.restarts'.tr(
              namedArgs: {
                'count': '$restarts',
                'reason': reason == null ? '' : 'wd.reason_$reason'.tr(),
              },
            ),
        ].join(' · '),
      );
    }),
    base(
      'watchdog_restart',
      Section.kiosk,
      _g('watchdog'),
      (ctx) => ActionSetting(
        icon: Icons.restart_alt,
        title: _t('watchdog_restart', 'title'),
        subtitle: _t('watchdog_restart', 'desc'),
        onTap: () async {
          await c.platform.restartCompanion();
          await c.refresh();
        },
      ),
    ),

    // ---------------------------------------------------------------- System › Voice
    base('wake_word', Section.system, _g('voice'), (ctx) {
      return SwitchSetting(
        icon: Icons.record_voice_over_outlined,
        title: _t('wake_word', 'title'),
        subtitle: _t('wake_word', 'desc'),
        value: b('wake_word'),
        onChanged: (v) async {
          await set(ctx, 'wake_word', v);
          if (v && !s().micPermission) await c.platform.requestMicPermission();
          await c.refresh();
        },
      );
    }),
    base('wake_word_phrase', Section.system, _g('voice'), (ctx) {
      final active = s().activeWakeWords;
      return ActionSetting(
        icon: Icons.chat_bubble_outline,
        title: _t('wake_word_phrase', 'title'),
        subtitle: active.isEmpty
            ? 'wakeword.none_chosen'.tr()
            : active.map((w) => w['phrase']).join(', '),
        trailing: FilledButton.tonal(
          onPressed: () => showWakeWordsDialog(ctx, c),
          child: Text('wakeword.manage'.tr()),
        ),
        onTap: () => showWakeWordsDialog(ctx, c),
      );
    }),
    sliderEntry(
      'wake_word_threshold',
      Section.system,
      _g('voice'),
      Icons.tune,
      'wake_word_threshold',
      min: 10,
      max: 99,
      fallback: 50,
      divisions: 89,
      format: (v) => '${v.round()} %',
    ),
    sliderEntry(
      'voice_volume',
      Section.system,
      _g('voice'),
      Icons.volume_up_outlined,
      'voice_volume',
      min: 0,
      max: 100,
      fallback: 50,
      divisions: 20,
      format: (v) => '${v.round()} %',
    ),
    switchEntry(
      'conversation',
      Section.system,
      _g('voice'),
      Icons.forum_outlined,
      'conversation',
    ),
    sliderEntry(
      'conversation_timeout',
      Section.system,
      _g('voice'),
      Icons.hourglass_bottom,
      'conversation_timeout_s',
      min: 3,
      max: 30,
      fallback: 8,
      divisions: 27,
      format: fmtSeconds,
    ),
    switchEntry(
      'voice_sounds',
      Section.system,
      _g('voice'),
      Icons.notifications_active_outlined,
      'voice_sounds',
    ),
    base(
      'voice_skin',
      Section.system,
      _g('voice'),
      (ctx) => SkinPickerSetting(
        icon: Icons.palette_outlined,
        title: _t('voice_skin', 'title'),
        subtitle: _t('voice_skin', 'desc'),
        skins: VoiceSkin.all,
        names: {for (final s in VoiceSkin.all) s.id: 'voice.skin_${s.id}'.tr()},
        value: VoiceSkin.byId(cfg()['voice_skin']).id,
        onChanged: (v) => set(ctx, 'voice_skin', v),
      ),
    ),
    switchEntry(
      'voice_docked',
      Section.system,
      _g('voice'),
      Icons.dock_outlined,
      'voice_docked',
    ),
    base(
      'echo_cancellation',
      Section.system,
      _g('voice'),
      (ctx) => SegmentedSetting(
        icon: Icons.graphic_eq,
        title: _t('echo_cancellation', 'title'),
        subtitle: _t('echo_cancellation', 'desc'),
        options: {
          for (final m in const ['auto', 'on', 'off']) m: 'mic.echo_$m'.tr(),
        },
        value: str('echo_cancellation', 'auto'),
        onChanged: (v) => set(ctx, 'echo_cancellation', v),
      ),
    ),
    base('echo_status', Section.system, _g('voice'), (ctx) {
      final st = c.status;
      final echo = st.echoCancellationState;
      final noise = st.noiseSuppressionState;
      final source = st.micSourceInUse;
      // "on" is a statement that the tablet should have it: say so when it does not
      final problem =
          echo == 'unavailable' && str('echo_cancellation', 'auto') == 'on';
      return Tile(
        icon: Icons.settings_voice_outlined,
        color: problem ? Semantic.warn : null,
        title: _t('echo_status', 'title'),
        subtitle: [
          'mic.echo_state_$echo'.tr(),
          if (b('noise_suppression')) 'mic.noise_state_$noise'.tr(),
          if (source != null)
            'mic.source_in_use'.tr(
              namedArgs: {'source': 'mic.source_$source'.tr()},
            ),
        ].join('\n'),
        trailing: Pill(
          'mic.state_$echo'.tr(),
          color: echo == 'active'
              ? Semantic.ok
              : problem
              ? Semantic.warn
              : null,
        ),
      );
    }),
    switchEntry(
      'noise_suppression',
      Section.system,
      _g('voice'),
      Icons.noise_aware_outlined,
      'noise_suppression',
    ),
    base(
      'mic_source',
      Section.system,
      _g('voice'),
      (ctx) => SegmentedSetting(
        icon: Icons.mic_external_on_outlined,
        title: _t('mic_source', 'title'),
        subtitle: _t('mic_source', 'desc'),
        options: {
          for (final m in const [
            'auto',
            'voice_recognition',
            'voice_communication',
          ])
            m: 'mic.source_$m'.tr(),
        },
        value: str('mic_source', 'auto'),
        onChanged: (v) => set(ctx, 'mic_source', v),
      ),
    ),
    base('wake_word_status', Section.system, _g('voice'), (ctx) {
      final st = c.status;
      final chosenMissing = [
        for (final w in st.activeWakeWords)
          if (w['installed'] != true) w,
      ];
      if (st.wakeWordDownloading != null) {
        final name = st.wakeWords
            .where((w) => w['id'] == st.wakeWordDownloading)
            .map((w) => w['phrase'])
            .firstOrNull;
        return Tile(
          icon: Icons.downloading,
          title: _t('wake_word_status', 'title'),
          subtitle: 'wakeword.downloading'.tr(
            namedArgs: {
              'name': '$name',
              'pct': (st.wakeWordDownloadFraction * 100).round().toString(),
            },
          ),
        );
      }
      final err = st.wakeWordError;
      if (b('wake_word') && st.wakeWordDownloadError != null) {
        return ActionSetting(
          icon: Icons.download_outlined,
          color: Semantic.warn,
          title: 'wakeword.download_failed'.tr(),
          subtitle: 'wakeword.err_${st.wakeWordDownloadError}'.tr(),
          trailing: FilledButton.tonal(
            onPressed: () async {
              for (final w in chosenMissing) {
                await c.platform.downloadWakeWord(w['id'] as String);
              }
            },
            child: Text('wakeword.retry'.tr()),
          ),
          onTap: () => showWakeWordsDialog(ctx, c),
        );
      }
      if (b('wake_word') && st.activeWakeWords.isEmpty) {
        return ActionSetting(
          icon: Icons.chat_bubble_outline,
          color: Semantic.warn,
          title: 'wakeword.none_chosen'.tr(),
          subtitle: 'wakeword.choose_one'.tr(),
          onTap: () => showWakeWordsDialog(ctx, c),
        );
      }
      if (b('wake_word') && err == 'mic_permission') {
        return ActionSetting(
          icon: Icons.mic_off_outlined,
          color: Semantic.warn,
          title: 'voice.err_mic_permission'.tr(),
          subtitle: _t('wake_word_status', 'desc'),
          trailing: FilledButton.tonal(
            onPressed: () => c.platform.requestMicPermission(),
            child: Text('perm.grant'.tr()),
          ),
          onTap: () => c.platform.requestMicPermission(),
        );
      }
      if (b('wake_word') && err != null && err != 'models_missing') {
        return Tile(
          icon: Icons.error_outline,
          color: Semantic.bad,
          title: 'wakeword.problem'.tr(),
          subtitle: 'wakeword.err_$err'.tr(),
        );
      }
      return Tile(
        icon: st.wakeWordListening ? Icons.hearing : Icons.hearing_disabled,
        title: _t('wake_word_status', 'title'),
        subtitle: st.wakeWordListening
            ? 'wakeword.listening'.tr()
            : 'wakeword.off'.tr(),
        trailing: st.wakeWordListening
            ? Pill('wakeword.on'.tr(), color: Semantic.ok, icon: Icons.hearing)
            : null,
      );
    }),

    // ---------------------------------------------------------------- Display › Brightness
    base(
      'brightness_mode',
      Section.display,
      _g('brightness'),
      (ctx) => SegmentedSetting(
        icon: Icons.brightness_auto,
        title: _t('brightness_mode', 'title'),
        subtitle: _t('brightness_mode', 'desc'),
        options: {
          'manual': 'mode.manual'.tr(),
          'auto': 'mode.auto'.tr(),
          'day': 'mode.day'.tr(),
          'night': 'mode.night'.tr(),
        },
        value: str('mode', 'manual'),
        onChanged: (v) => set(ctx, 'mode', v),
      ),
    ),

    // ---------------------------------------------------------------- Display › Day
    sliderEntry(
      'day_level',
      Section.display,
      day,
      Icons.wb_sunny_outlined,
      'day_level',
      min: 0,
      max: 255,
      fallback: 200,
      brightness: true,
    ),
    switchEntry(
      'auto_dim',
      Section.display,
      day,
      Icons.brightness_medium,
      'auto_dim',
    ),
    sliderEntry(
      'day_dim_level',
      Section.display,
      day,
      Icons.brightness_low,
      'day_dim_level',
      min: 0,
      max: 255,
      fallback: 60,
      brightness: true,
    ),
    sliderEntry(
      'dim_after',
      Section.display,
      day,
      Icons.timer_outlined,
      'dim_after_s',
      min: 10,
      max: 1800,
      fallback: 120,
      format: fmtSeconds,
    ),

    // ---------------------------------------------------------------- Display › Night
    timeEntry('night_start', 'night_start', Icons.bedtime_outlined),
    timeEntry('night_end', 'night_end', Icons.wb_twilight),
    sliderEntry(
      'night_level',
      Section.display,
      night,
      Icons.nightlight_outlined,
      'night_level',
      min: 0,
      max: 255,
      fallback: 6,
      brightness: true,
    ),
    switchEntry(
      'night_light',
      Section.display,
      night,
      Icons.lightbulb_outline,
      'night_light',
    ),
    sliderEntry(
      'night_light_level',
      Section.display,
      night,
      Icons.lightbulb,
      'night_light_level',
      min: 0,
      max: 255,
      fallback: 50,
      brightness: true,
    ),
    sliderEntry(
      'night_touch_level',
      Section.display,
      night,
      Icons.touch_app_outlined,
      'night_touch_level',
      min: 0,
      max: 255,
      fallback: 120,
      brightness: true,
    ),
    sliderEntry(
      'night_hold',
      Section.display,
      night,
      Icons.timer_outlined,
      'night_hold_s',
      min: 5,
      max: 300,
      fallback: 20,
      format: fmtSeconds,
    ),

    // ---------------------------------------------------------------- Display › Presence
    base(
      'presence_sources',
      Section.display,
      presence,
      (ctx) => Tile(
        icon: Icons.sensors,
        title: _t('presence_sources', 'title'),
        subtitle: _t('presence_sources', 'help'),
        trailing: s().presence
            ? Pill('presence.near'.tr(), color: Semantic.ok, icon: Icons.person)
            : Pill('presence.nobody'.tr()),
      ),
    ),
    sliderEntry(
      'presence_hold',
      Section.display,
      presence,
      Icons.timer_outlined,
      'presence_hold_s',
      min: 5,
      max: 300,
      fallback: 30,
      format: fmtSeconds,
    ),
    sliderEntry(
      'fade',
      Section.display,
      presence,
      Icons.blur_linear,
      'fade_s',
      min: 0,
      max: 10,
      fallback: 1.5,
      divisions: 20,
      format: (v) => '${v.toStringAsFixed(1)} s',
      asDouble: true,
    ),

    // ---------------------------------------------------------------- Display › Presence camera
    base(
      'camera_presence',
      Section.display,
      camera,
      (ctx) => SwitchSetting(
        icon: Icons.videocam_outlined,
        title: _t('camera_presence', 'title'),
        subtitle: _t('camera_presence', 'desc'),
        value: b('camera_presence'),
        onChanged: (v) async {
          await set(ctx, 'camera_presence', v);
          if (v && !s().cameraPermission) {
            await c.platform.requestPermission('camera');
          }
        },
      ),
    ),
    base('camera_status', Section.display, camera, (ctx) {
      final st = s();
      if (!b('camera_presence')) {
        return Tile(
          icon: Icons.videocam_off_outlined,
          title: _t('camera_status', 'title'),
          subtitle: 'camera.off'.tr(),
          trailing: Pill('camera.off'.tr()),
        );
      }
      if (!st.cameraPermission) {
        return ActionSetting(
          icon: Icons.warning_amber_rounded,
          color: Semantic.warn,
          title: 'camera.permission_title'.tr(),
          subtitle: 'camera.permission_desc'.tr(),
          trailing: FilledButton.tonal(
            onPressed: () => c.platform.requestPermission('camera'),
            child: Text('perm.grant'.tr()),
          ),
          onTap: () => c.platform.requestPermission('camera'),
        );
      }
      if (st.cameraError != null) {
        return Tile(
          icon: Icons.error_outline,
          color: Semantic.bad,
          title: 'camera.problem'.tr(),
          subtitle: st.cameraError,
        );
      }
      return Tile(
        icon: st.cameraActive ? Icons.videocam : Icons.videocam_off_outlined,
        title: _t('camera_status', 'title'),
        subtitle: 'camera.change'.tr(
          namedArgs: {'pct': (st.cameraScore * 100).toStringAsFixed(1)},
        ),
        trailing: st.cameraActive
            ? (st.cameraMotion
                  ? Pill(
                      'camera.movement'.tr(),
                      color: Semantic.ok,
                      icon: Icons.directions_walk,
                    )
                  : Pill('camera.running'.tr()))
            : Pill('camera.starting'.tr(), color: Semantic.warn),
      );
    }),
    base(
      'camera_facing',
      Section.display,
      camera,
      (ctx) => SegmentedSetting(
        icon: Icons.cameraswitch_outlined,
        title: _t('camera_facing', 'title'),
        options: {'front': 'camera.front'.tr(), 'back': 'camera.back'.tr()},
        value: str('camera_facing', 'front'),
        onChanged: (v) => set(ctx, 'camera_facing', v),
      ),
    ),
    sliderEntry(
      'camera_sensitivity',
      Section.display,
      camera,
      Icons.tune,
      'camera_sensitivity',
      min: 0,
      max: 100,
      fallback: 50,
      format: (v) => '${v.round()} %',
    ),
    sliderEntry(
      'camera_fps',
      Section.display,
      camera,
      Icons.speed,
      'camera_fps',
      min: 1,
      max: 10,
      fallback: 3,
      divisions: 9,
      format: (v) => '${v.round()} fps',
    ),

    // ---------------------------------------------------------------- System › Home Assistant
    base('connection', Section.system, _g('home_assistant'), (ctx) {
      final link = c.link;
      return ValueListenableBuilder<LinkState>(
        valueListenable: link ?? ValueNotifier(LinkState.disconnected),
        builder: (_, state, _) {
          final (label, color) = switch (state) {
            LinkState.connected => ('link.connected'.tr(), Semantic.ok),
            LinkState.connecting => ('link.connecting'.tr(), Semantic.warn),
            LinkState.authFailed => ('link.rejected'.tr(), Semantic.bad),
            LinkState.disconnected => ('link.disconnected'.tr(), Semantic.bad),
          };
          return ActionSetting(
            icon: Icons.hub_outlined,
            title: _t('connection', 'title'),
            subtitle: c.settings.haUrl.isEmpty
                ? 'link.not_paired'.tr()
                : '${c.settings.haUrl} · ${switch (c.route.kind) {
                    RouteKind.internal => 'net.via_internal'.tr(),
                    RouteKind.external => 'net.via_external'.tr(),
                    RouteKind.waitingForHome => 'net.waiting_home'.tr(),
                    RouteKind.offline => 'net.offline'.tr(),
                  }}',
            color: color,
            trailing: Pill(label, color: color),
            onTap: () => showConnectionSheet(ctx, c),
          );
        },
      );
    }),

    base(
      'pair_ha',
      Section.system,
      _g('home_assistant'),
      (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: PairingPanel(controller: c),
      ),
    ),

    // ---------------------------------------------------------------- System › Network
    base('network_status', Section.system, _g('network'), (ctx) {
      final n = c.network;
      final where = n.vpn
          ? 'net.vpn'.tr()
          : n.wifi
          ? (n.ssid != null
                ? 'net.wifi_named'.tr(namedArgs: {'name': n.ssid!})
                : 'net.wifi'.tr())
          : n.ethernet
          ? 'net.ethernet'.tr()
          : n.cellular
          ? 'net.cellular'.tr()
          : 'net.none'.tr();
      final via = switch (c.route.kind) {
        RouteKind.internal => 'net.via_internal'.tr(),
        RouteKind.external => 'net.via_external'.tr(),
        RouteKind.waitingForHome => 'net.waiting_home'.tr(),
        RouteKind.offline => 'net.offline'.tr(),
      };
      return Tile(
        icon: Icons.network_check,
        title: _t('network_status', 'title'),
        subtitle: '$where · $via',
      );
    }),
    base(
      'internal_url',
      Section.system,
      _g('network'),
      (ctx) => TextFieldSetting(
        icon: Icons.home_outlined,
        title: _t('internal_url', 'title'),
        subtitle: _t('internal_url', 'desc'),
        hint: 'http://homeassistant.local:8123',
        value: c.settings.haUrl,
        onSaved: (v) => c.updateConnection(c.settings.copyWith(haUrl: v)),
      ),
    ),
    base(
      'external_url',
      Section.system,
      _g('network'),
      (ctx) => TextFieldSetting(
        icon: Icons.public,
        title: _t('external_url', 'title'),
        subtitle: _t('external_url', 'desc'),
        hint: 'https://ha.example.org',
        value: c.settings.externalUrl,
        onSaved: (v) => c.updateConnection(c.settings.copyWith(externalUrl: v)),
      ),
    ),
    base(
      'home_networks',
      Section.system,
      _g('network'),
      (ctx) => HomeNetworksSetting(controller: c),
    ),
    base(
      'vpn_is_home',
      Section.system,
      _g('network'),
      (ctx) => SwitchSetting(
        icon: Icons.vpn_lock_outlined,
        title: _t('vpn_is_home', 'title'),
        subtitle: _t('vpn_is_home', 'desc'),
        value: c.settings.vpnIsHome,
        onChanged: (v) async =>
            c.updateConnection(c.settings.copyWith(vpnIsHome: v)),
      ),
    ),
    base(
      'ethernet_is_home',
      Section.system,
      _g('network'),
      (ctx) => SwitchSetting(
        icon: Icons.settings_ethernet,
        title: _t('ethernet_is_home', 'title'),
        subtitle: _t('ethernet_is_home', 'desc'),
        value: c.settings.ethernetIsHome,
        onChanged: (v) async =>
            c.updateConnection(c.settings.copyWith(ethernetIsHome: v)),
      ),
    ),
    base(
      'connection_policy',
      Section.system,
      _g('network'),
      (ctx) => SegmentedSetting(
        icon: Icons.sync_lock,
        title: _t('connection_policy', 'title'),
        subtitle: _t('connection_policy', 'desc'),
        options: {
          'always': 'net.policy_always'.tr(),
          'home_only': 'net.policy_home'.tr(),
        },
        value: c.settings.policy == ConnectionPolicy.homeOnly
            ? 'home_only'
            : 'always',
        onChanged: (v) async => c.updateConnection(
          c.settings.copyWith(
            policy: v == 'home_only'
                ? ConnectionPolicy.homeOnly
                : ConnectionPolicy.always,
          ),
        ),
      ),
    ),

    // ---------------------------------------------------------------- System › Appearance
    base(
      'theme',
      Section.system,
      _g('appearance'),
      (ctx) => SegmentedSetting(
        icon: Icons.contrast,
        title: _t('theme', 'title'),
        subtitle: _t('theme', 'desc'),
        options: {
          'system': 'theme.system'.tr(),
          'light': 'theme.light'.tr(),
          'dark': 'theme.dark'.tr(),
          'night': 'theme.night'.tr(),
        },
        value: str('theme', 'system'),
        onChanged: (v) => set(ctx, 'theme', v),
      ),
    ),
    base('language', Section.system, _g('appearance'), (ctx) {
      final current = ctx.locale.languageCode;
      return SegmentedSetting(
        icon: Icons.language,
        title: _t('language', 'title'),
        subtitle: _t('language', 'desc'),
        options: const {'en': 'English', 'de': 'Deutsch'},
        value: current,
        onChanged: (v) => ctx.setLocale(Locale(v)),
      );
    }),

    // ---------------------------------------------------------------- System › Permissions
    for (final p in permissionSpecs)
      SettingEntry(
        id: 'perm_${p.id}',
        section: Section.system,
        group: _g('permissions'),
        title: p.title,
        description: p.why,
        keywords: [
          'permission',
          'allow',
          'grant',
          p.id,
          ..._t('permission', 'kw').split(',').map((e) => e.trim()),
        ],
        builder: (ctx) => PermissionRow(spec: p, controller: c),
      ),
    base(
      'device_owner',
      Section.system,
      _g('permissions'),
      (ctx) => ActionSetting(
        icon: Icons.admin_panel_settings_outlined,
        title: _t('device_owner', 'title'),
        subtitle: s().deviceOwner
            ? 'owner.active_desc'.tr()
            : 'owner.optional_desc'.tr(),
        trailing: s().deviceOwner
            ? Pill('owner.active'.tr(), color: Semantic.ok, icon: Icons.check)
            : Pill('owner.not_set'.tr()),
        onTap: () => s().deviceOwner
            ? showRemoveOwnerDialog(ctx, c)
            : showProtectionSheet(ctx, c),
      ),
    ),

    // ---------------------------------------------------------------- System › Updates
    base(
      'update',
      Section.system,
      _g('updates'),
      (ctx) => ActionSetting(
        icon: s().pendingUpdate != null
            ? Icons.system_update
            : Icons.verified_outlined,
        title: s().pendingUpdate != null
            ? 'update.available'.tr()
            : 'update.android'.tr(namedArgs: {'version': s().androidRelease}),
        subtitle:
            'update.patch'.tr(namedArgs: {'patch': s().securityPatch}) +
            (s().deviceOwner ? '' : ' ${'update.needs_owner'.tr()}'),
        trailing: Text('update.check'.tr()),
        onTap: () async {
          if (s().accessibilityEnabled) {
            await c.platform.runSystemUpdate();
          } else {
            await c.platform.openSettings('system_update');
          }
        },
      ),
    ),

    // ---------------------------------------------------------------- System › Setup
    base(
      'run_setup',
      Section.system,
      _g('setup'),
      (ctx) => ActionSetting(
        icon: Icons.auto_fix_high,
        title: _t('run_setup', 'title'),
        subtitle: _t('run_setup', 'desc'),
        onTap: () => c.restartSetup(),
      ),
    ),

    // ---------------------------------------------------------------- System › Developer options
    switchEntry(
      'raw_brightness',
      Section.system,
      _g('developer'),
      Icons.code,
      'raw_brightness',
    ),
  ];
}

/// Brightness is stored as the raw Android value 0..255 and shown as percent unless the developer option is on.
int brightnessPercent(int raw) => (raw * 100 / 255).round();
int brightnessRaw(int percent) => (percent * 255 / 100).round();

/// Brightness as text for a status line: `80 %`, or `204 / 255` with the developer option.
String brightnessText(int? raw, {required bool rawMode}) => raw == null
    ? '–'
    : rawMode
    ? '$raw / 255'
    : '${brightnessPercent(raw)} %';

/// Free-text search over title, description, keywords, group and section; every word must match.
List<SettingEntry> searchSettings(List<SettingEntry> all, String query) {
  final words = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return const [];
  int score(SettingEntry e) {
    var total = 0;
    final title = e.title.toLowerCase();
    final rest =
        '${e.description} ${e.keywords.join(' ')} ${e.group} ${e.section.label}'
            .toLowerCase();
    for (final w in words) {
      if (title.contains(w)) {
        total += title.startsWith(w) ? 6 : 4;
      } else if (rest.contains(w)) {
        total += 1;
      } else {
        return 0;
      }
    }
    return total;
  }

  final scored = [
    for (final e in all) (e, score(e)),
  ].where((p) => p.$2 > 0).toList()..sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final p in scored) p.$1];
}

// -------------------------------------------------------------------------------- sheets

Future<void> showProtectionSheet(BuildContext context, AppController c) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => ListenableBuilder(
      listenable: c,
      builder: (ctx, _) {
        final s = c.status;
        final t = Theme.of(ctx);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'sheet.protection.title'.tr(),
                  style: t.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text('sheet.protection.intro'.tr()),
                const SizedBox(height: 16),
                GroupCard(
                  children: [
                    Tile(
                      icon: Icons.shield_outlined,
                      title: 'prot.accessibility'.tr(),
                      subtitle: 'sheet.protection.accessibility_desc'.tr(),
                      trailing: s.accessibilityEnabled
                          ? Pill(
                              'common.on'.tr(),
                              color: Semantic.ok,
                              icon: Icons.check,
                            )
                          : FilledButton.tonal(
                              onPressed: () =>
                                  c.platform.openSettings('accessibility'),
                              child: Text('common.turn_on'.tr()),
                            ),
                    ),
                    Tile(
                      icon: Icons.verified_user_outlined,
                      title: 'sheet.protection.owner_title'.tr(),
                      subtitle: s.deviceOwner
                          ? 'owner.active_desc'.tr()
                          : 'sheet.protection.owner_desc'.tr(),
                      trailing: s.deviceOwner
                          ? Pill(
                              'owner.active'.tr(),
                              color: Semantic.ok,
                              icon: Icons.check,
                            )
                          : null,
                    ),
                  ],
                ),
                if (!s.deviceOwner) ...[
                  const SizedBox(height: 16),
                  Text(
                    'sheet.protection.how_title'.tr(),
                    style: t.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text('sheet.protection.how_steps'.tr()),
                  const SizedBox(height: 8),
                  const CopyBlock(
                    'adb shell dpm set-device-owner dev.glassp.ha_sidecar/.SidecarDeviceAdminReceiver',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'sheet.protection.warning'.tr(),
                    style: t.textTheme.bodySmall?.copyWith(
                      color: t.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    ),
  );
}

Future<void> showConnectionSheet(BuildContext context, AppController c) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'settings.connection.title'.tr(),
              style: Theme.of(ctx).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              c.settings.haUrl.isEmpty
                  ? 'link.not_paired'.tr()
                  : 'sheet.connection.paired_with'.tr(
                      namedArgs: {'url': c.settings.haUrl},
                    ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.link_off),
              label: Text('sheet.connection.pair_again'.tr()),
              onPressed: () async {
                Navigator.pop(ctx);
                await c.unpair();
                await c.restartSetup();
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// Home Wi-Fi names (chips), with "add the current network". Reading the Wi-Fi name needs the location permission.
class HomeNetworksSetting extends StatelessWidget {
  const HomeNetworksSetting({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = controller;
    final ssid = c.network.ssid;
    final s = c.settings;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconBadge(Icons.wifi),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'settings.home_networks.title'.tr(),
                  style: t.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 56, top: 2),
            child: Text(
              'settings.home_networks.desc'.tr(),
              style: t.textTheme.bodyMedium?.copyWith(
                color: t.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 56, top: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final n in s.homeSsids)
                  InputChip(
                    label: Text(n),
                    onDeleted: () => c.updateConnection(
                      s.copyWith(homeSsids: [...s.homeSsids]..remove(n)),
                    ),
                  ),
                if (!c.network.locationGranted)
                  ActionChip(
                    avatar: const Icon(Icons.location_on_outlined, size: 18),
                    label: Text('net.allow_location'.tr()),
                    onPressed: () => c.platform.requestPermission('location'),
                  )
                else if (ssid != null && !s.homeSsids.contains(ssid))
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: Text(
                      'net.add_current'.tr(namedArgs: {'name': ssid}),
                    ),
                    onPressed: () => c.updateConnection(
                      s.copyWith(homeSsids: [...s.homeSsids, ssid]),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
