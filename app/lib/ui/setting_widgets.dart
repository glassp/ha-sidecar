import '../voice/voice_skin.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import 'design.dart';

/// One widget per kind of setting; the settings registry composes them.

class SwitchSetting extends StatelessWidget {
  const SwitchSetting({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Tile(
    icon: icon,
    title: title,
    subtitle: subtitle,
    trailing: Switch(value: value, onChanged: onChanged),
    onTap: () => onChanged(!value),
  );
}

class SliderSetting extends StatefulWidget {
  const SliderSetting({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.format,
    this.divisions,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String Function(double)? format;
  final ValueChanged<double> onChanged;

  @override
  State<SliderSetting> createState() => _SliderSettingState();
}

class _SliderSettingState extends State<SliderSetting> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final v = (_drag ?? widget.value).clamp(widget.min, widget.max).toDouble();
    final label = widget.format?.call(v) ?? v.round().toString();
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(widget.icon),
              const SizedBox(width: 16),
              Expanded(
                child: Text(widget.title, style: t.textTheme.titleMedium),
              ),
              Text(
                label,
                style: t.textTheme.titleMedium?.copyWith(
                  color: t.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (widget.subtitle != null)
            Padding(
              padding: const EdgeInsets.only(left: 56, top: 2),
              child: Text(
                widget.subtitle!,
                style: t.textTheme.bodyMedium?.copyWith(
                  color: t.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 40),
            child: Slider(
              value: v,
              min: widget.min,
              max: widget.max,
              divisions: widget.divisions,
              onChanged: (x) => setState(() => _drag = x),
              onChangeEnd: (x) {
                widget.onChanged(x);
                setState(() => _drag = null);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Chooses a voice skin by looking at it: every skin is a small preview (its background, a user bubble, an answer bubble and its accent).
class SkinPickerSetting extends StatelessWidget {
  const SkinPickerSetting({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.skins,
    required this.names,
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final List<VoiceSkin> skins;
  final Map<String, String> names; // id -> label
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(icon),
              const SizedBox(width: 16),
              Expanded(child: Text(title, style: t.textTheme.titleMedium)),
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(left: 56, top: 2),
              child: Text(
                subtitle!,
                style: t.textTheme.bodyMedium?.copyWith(
                  color: t.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final s in skins)
                _SkinChip(
                  skin: s,
                  label: names[s.id] ?? s.id,
                  selected: s.id == value,
                  onTap: () => onChanged(s.id),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SkinChip extends StatelessWidget {
  const _SkinChip({
    required this.skin,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final VoiceSkin skin;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        key: Key('skin-${skin.id}'),
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: 112,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? t.colorScheme.primary
                  : t.colorScheme.outlineVariant,
              width: selected ? 2.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Container(
                height: 66,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: skin.background,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      height: 5,
                      margin: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: skin.accent,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const Spacer(),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        width: 44,
                        height: 12,
                        decoration: BoxDecoration(
                          color: skin.userBubble,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 56,
                        height: 12,
                        decoration: BoxDecoration(
                          color: skin.assistantBubble,
                          borderRadius: BorderRadius.circular(6),
                          border: skin.id == 'contrast'
                              ? Border.all(color: skin.outline)
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.textTheme.labelMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SegmentedSetting extends StatelessWidget {
  const SegmentedSetting({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.options,
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final Map<String, String> options; // value -> label
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(icon),
              const SizedBox(width: 16),
              Expanded(child: Text(title, style: t.textTheme.titleMedium)),
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(left: 56, top: 2),
              child: Text(
                subtitle!,
                style: t.textTheme.bodyMedium?.copyWith(
                  color: t.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                for (final e in options.entries)
                  ButtonSegment(value: e.key, label: Text(e.value)),
              ],
              selected: {
                options.containsKey(value) ? value : options.keys.first,
              },
              onSelectionChanged: (s) => onChanged(s.first),
            ),
          ),
        ],
      ),
    );
  }
}

class TimeSetting extends StatelessWidget {
  const TimeSetting({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.minutes,
    required this.onChanged,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final int minutes;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final time = TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
    return Tile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: Pill(time.format(context)),
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: time,
        );
        if (picked != null) onChanged(picked.hour * 60 + picked.minute);
      },
    );
  }
}

class ActionSetting extends StatelessWidget {
  const ActionSetting({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.trailing,
    this.color,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  final Color? color;

  @override
  Widget build(BuildContext context) => Tile(
    icon: icon,
    title: title,
    subtitle: subtitle,
    color: color,
    trailing:
        trailing ??
        Icon(
          Icons.chevron_right,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
    onTap: onTap,
  );
}

/// Dashboard link: paste the address from the browser, only the path is kept.
class DashboardSetting extends StatefulWidget {
  const DashboardSetting({
    super.key,
    required this.controller,
    required this.configKey,
    required this.icon,
    required this.title,
    required this.help,
    required this.value,
    this.required = false,
  });
  final AppController controller;
  final String configKey;
  final IconData icon;
  final String title;
  final String help;
  final String value;
  final bool required;

  @override
  State<DashboardSetting> createState() => _DashboardSettingState();
}

class _DashboardSettingState extends State<DashboardSetting> {
  late final TextEditingController _text = TextEditingController(
    text: widget.value,
  );
  final FocusNode _focus = FocusNode();
  String? _error;
  bool _saved = false;

  @override
  void didUpdateWidget(covariant DashboardSetting old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && widget.value != _text.text) {
      _text.text = widget.value;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final input = _text.text.trim();
    final err = await widget.controller.setConfig(widget.configKey, input);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _error = 'dashboard.invalid'.tr();
        _saved = false;
      });
      return;
    }
    final stored =
        (widget.controller.status.cfg[widget.configKey] ?? '') as String;
    setState(() {
      _error = null;
      _saved = true;
      _text.text = stored;
    });
    final pasted = Uri.tryParse(input);
    final paired = Uri.tryParse(widget.controller.settings.haUrl);
    if (pasted != null &&
        pasted.hasAuthority &&
        paired != null &&
        pasted.host != paired.host) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'dashboard.host_mismatch'.tr(
              namedArgs: {
                'host': pasted.host,
                'paired': paired.host,
                'path': stored,
              },
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final empty = widget.value.isEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(widget.icon),
              const SizedBox(width: 16),
              Expanded(
                child: Text(widget.title, style: t.textTheme.titleMedium),
              ),
              if (widget.required && empty)
                Pill(
                  'common.required'.tr(),
                  color: Semantic.warn,
                  icon: Icons.priority_high,
                ),
              if (!empty)
                Pill('common.set'.tr(), color: Semantic.ok, icon: Icons.check),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 56, top: 2, bottom: 12),
            child: Text(
              widget.help,
              style: t.textTheme.bodyMedium?.copyWith(
                color: t.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextField(
            controller: _text,
            focusNode: _focus,
            keyboardType: TextInputType.url,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            onChanged: (_) => setState(() => _saved = false),
            decoration: InputDecoration(
              hintText: 'https://home.example.org/lovelace/wall-panel',
              hintStyle: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: .45),
              ),
              errorText: _error,
              errorMaxLines: 3,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              prefixIcon: const Icon(Icons.link),
              suffixIcon: IconButton(
                icon: Icon(
                  _saved ? Icons.check_circle : Icons.save_outlined,
                  color: _saved ? Semantic.ok : null,
                ),
                tooltip: 'common.save'.tr(),
                onPressed: _save,
              ),
            ),
          ),
          if (!empty)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.subdirectory_arrow_right,
                    size: 16,
                    color: t.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text('dashboard.opens'.tr(), style: t.textTheme.bodySmall),
                  Expanded(
                    child: Text(
                      widget.value,
                      style: t.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                      ),
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

/// Reusable "copy this command" block (used for the device owner adb command).
class CopyBlock extends StatelessWidget {
  const CopyBlock(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
      decoration: BoxDecoration(
        color: t.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              text,
              style: t.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            tooltip: 'common.copy'.tr(),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('common.copied'.tr())));
            },
          ),
        ],
      ),
    );
  }
}

/// A free-text field that saves when submitted or when it loses focus (addresses).
class TextFieldSetting extends StatefulWidget {
  const TextFieldSetting({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.hint,
    required this.value,
    required this.onSaved,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? hint;
  final String value;
  final ValueChanged<String> onSaved;

  @override
  State<TextFieldSetting> createState() => _TextFieldSettingState();
}

class _TextFieldSettingState extends State<TextFieldSetting> {
  late final _ctl = TextEditingController(text: widget.value);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _save();
    });
  }

  void _save() {
    final v = _ctl.text.trim();
    if (v != widget.value) widget.onSaved(v);
  }

  @override
  void didUpdateWidget(TextFieldSetting old) {
    super.didUpdateWidget(old);
    // changed from elsewhere (pairing handed over new addresses): show it unless the user is typing
    if (widget.value != old.value && !_focus.hasFocus) _ctl.text = widget.value;
  }

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(widget.icon),
              const SizedBox(width: 16),
              Expanded(
                child: Text(widget.title, style: t.textTheme.titleMedium),
              ),
            ],
          ),
          if (widget.subtitle != null)
            Padding(
              padding: const EdgeInsets.only(left: 56, top: 2),
              child: Text(
                widget.subtitle!,
                style: t.textTheme.bodyMedium?.copyWith(
                  color: t.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 56, top: 8),
            child: TextField(
              controller: _ctl,
              focusNode: _focus,
              keyboardType: TextInputType.url,
              autocorrect: false,
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                hintText: widget.hint,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
