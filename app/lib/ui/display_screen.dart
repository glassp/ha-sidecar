import 'package:flutter/material.dart';

import '../app_controller.dart';

/// Brightness, night light and presence settings. The same keys are exposed as HA entities.
class DisplayScreen extends StatelessWidget {
  const DisplayScreen({super.key, required this.controller});
  final AppController controller;

  Future<void> _set(String key, Object value) async {
    await controller.platform.setDisplayConfig({key: value});
    await controller.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final s = controller.status;
        final cfg = s.cfg;
        final mode = (cfg['mode'] ?? 'manual') as String;

        Widget level(String key, String label, {int max = 255}) => _SliderTile(
              label: label,
              value: ((cfg[key] ?? 0) as num).toDouble(),
              min: 0,
              max: max.toDouble(),
              onChangeEnd: (v) => _set(key, v.round()),
            );
        Widget seconds(String key, String label, int min, int max) => _SliderTile(
              label: label,
              value: ((cfg[key] ?? min) as num).toDouble().clamp(min.toDouble(), max.toDouble()),
              min: min.toDouble(),
              max: max.toDouble(),
              suffix: ' s',
              onChangeEnd: (v) => _set(key, v.round()),
            );
        Widget time(String key, String label) {
          final m = ((cfg[key] ?? 0) as num).toInt();
          final t = TimeOfDay(hour: m ~/ 60, minute: m % 60);
          return ListTile(
            title: Text(label),
            trailing: Text(t.format(context)),
            onTap: () async {
              final picked = await showTimePicker(context: context, initialTime: t);
              if (picked != null) await _set(key, picked.hour * 60 + picked.minute);
            },
          );
        }

        return Scaffold(
          appBar: AppBar(title: const Text('Display & presence')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: Icon(s.isNight ? Icons.bedtime : Icons.wb_sunny),
                  title: Text(s.isNight ? 'Night' : 'Day'),
                  subtitle: Text([
                    s.presence ? 'someone is near' : 'nobody near',
                    if (s.targetBrightness != null) 'target brightness ${s.targetBrightness}',
                    if (s.displayError != null) 'needs permission: ${s.displayError}',
                  ].join(' · ')),
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'manual', label: Text('Manual')),
                  ButtonSegment(value: 'auto', label: Text('Auto')),
                  ButtonSegment(value: 'day', label: Text('Day')),
                  ButtonSegment(value: 'night', label: Text('Night')),
                ],
                selected: {mode},
                onSelectionChanged: (v) => _set('mode', v.first),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 8, bottom: 16),
                child: Text(
                  'Manual: the sidecar never changes brightness. Auto: follows the night schedule (or the HA night '
                  'entity). Day/Night force a period.',
                ),
              ),
              const _Header('Day'),
              level('day_level', 'Brightness'),
              SwitchListTile(
                title: const Text('Dim when idle'),
                value: cfg['auto_dim'] == true,
                onChanged: (v) => _set('auto_dim', v),
              ),
              level('day_dim_level', 'Idle brightness'),
              seconds('dim_after_s', 'Dim after', 10, 1800),
              const _Header('Night'),
              time('night_start', 'Night starts'),
              time('night_end', 'Night ends'),
              level('night_level', 'Brightness'),
              SwitchListTile(
                title: const Text('Night light'),
                subtitle: const Text('Brighter while someone is near, so you can see the floor'),
                value: cfg['night_light'] == true,
                onChanged: (v) => _set('night_light', v),
              ),
              level('night_light_level', 'Night light brightness'),
              level('night_touch_level', 'Brightness after a touch'),
              seconds('night_hold_s', 'Keep after a touch', 5, 300),
              const _Header('Presence'),
              seconds('presence_hold_s', 'Keep "present" after the last detection', 5, 300),
              _SliderTile(
                label: 'Fade time',
                value: ((cfg['fade_s'] ?? 1.5) as num).toDouble(),
                min: 0,
                max: 10,
                suffix: ' s',
                onChangeEnd: (v) => _set('fade_s', double.parse(v.toStringAsFixed(1))),
              ),
              const Text(
                'Presence comes from a Home Assistant sensor (choose it in the integration options) and/or the '
                'camera (Camera & presence). Needs the "Modify system settings" permission.',
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}

class _SliderTile extends StatefulWidget {
  const _SliderTile({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChangeEnd,
    this.suffix = '',
  });
  final String label;
  final double value;
  final double min;
  final double max;
  final String suffix;
  final ValueChanged<double> onChangeEnd;

  @override
  State<_SliderTile> createState() => _SliderTileState();
}

class _SliderTileState extends State<_SliderTile> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final v = (_drag ?? widget.value).clamp(widget.min, widget.max);
    return Row(
      children: [
        Expanded(flex: 3, child: Text(widget.label)),
        Expanded(
          flex: 5,
          child: Slider(
            value: v,
            min: widget.min,
            max: widget.max,
            onChanged: (x) => setState(() => _drag = x),
            onChangeEnd: (x) {
              widget.onChangeEnd(x);
              setState(() => _drag = null);
            },
          ),
        ),
        SizedBox(
          width: 64,
          child: Text(
            '${v == v.roundToDouble() ? v.round() : v.toStringAsFixed(1)}${widget.suffix}',
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}
