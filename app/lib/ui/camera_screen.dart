import 'package:flutter/material.dart';

import '../app_controller.dart';

/// Everything camera related lives here: presence detection by motion, nothing else.
class CameraScreen extends StatelessWidget {
  const CameraScreen({super.key, required this.controller});
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
        final enabled = cfg['camera_presence'] == true;
        return Scaffold(
          appBar: AppBar(title: const Text('Camera & presence')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Card(
                child: ListTile(
                  leading: Icon(Icons.privacy_tip_outlined),
                  title: Text('Privacy'),
                  subtitle: Text(
                    'The camera is only used to notice movement near the tablet. Frames are compared in memory and '
                    'dropped: nothing is recorded, stored or sent. A notification is shown while the camera runs.',
                  ),
                ),
              ),
              SwitchListTile(
                title: const Text('Presence detection'),
                subtitle: const Text('Raises the night light / wakes the screen and hides the glance screen when someone is near'),
                value: enabled,
                onChanged: (v) async {
                  await _set('camera_presence', v);
                  if (v && !s.cameraPermission) await controller.platform.requestPermission('camera');
                },
              ),
              if (enabled && !s.cameraPermission)
                ListTile(
                  leading: const Icon(Icons.warning_amber, color: Colors.orange),
                  title: const Text('Camera permission needed'),
                  trailing: TextButton(
                    onPressed: () => controller.platform.requestPermission('camera'),
                    child: const Text('Grant'),
                  ),
                ),
              if (enabled && s.cameraError != null && s.cameraPermission)
                ListTile(
                  leading: const Icon(Icons.error_outline, color: Colors.red),
                  title: const Text('Camera problem'),
                  subtitle: Text(s.cameraError!),
                ),
              ListTile(
                leading: Icon(s.cameraActive ? Icons.videocam : Icons.videocam_off),
                title: Text(s.cameraActive ? (s.cameraMotion ? 'Running · motion' : 'Running · no motion') : 'Not running'),
                subtitle: Text('change score ${(s.cameraScore * 100).toStringAsFixed(1)} %'),
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'front', label: Text('Front camera'), icon: Icon(Icons.camera_front)),
                  ButtonSegment(value: 'back', label: Text('Back camera'), icon: Icon(Icons.camera_rear)),
                ],
                selected: {(cfg['camera_facing'] ?? 'front') as String},
                onSelectionChanged: (v) => _set('camera_facing', v.first),
              ),
              const SizedBox(height: 16),
              _Slider(
                label: 'Sensitivity',
                value: ((cfg['camera_sensitivity'] ?? 50) as num).toDouble(),
                min: 0,
                max: 100,
                suffix: ' %',
                onEnd: (v) => _set('camera_sensitivity', v.round()),
              ),
              _Slider(
                label: 'Frame rate',
                value: ((cfg['camera_fps'] ?? 3) as num).toDouble(),
                min: 1,
                max: 10,
                suffix: ' fps',
                onEnd: (v) => _set('camera_fps', v.round()),
              ),
              const Text('Lower frame rate and sensitivity use less battery. The camera keeps running while the screen is on.'),
            ],
          ),
        );
      },
    );
  }
}

class _Slider extends StatefulWidget {
  const _Slider({required this.label, required this.value, required this.min, required this.max, required this.onEnd, this.suffix = ''});
  final String label;
  final double value;
  final double min;
  final double max;
  final String suffix;
  final ValueChanged<double> onEnd;
  @override
  State<_Slider> createState() => _SliderState();
}

class _SliderState extends State<_Slider> {
  double? _drag;
  @override
  Widget build(BuildContext context) {
    final v = (_drag ?? widget.value).clamp(widget.min, widget.max);
    return Row(children: [
      Expanded(flex: 3, child: Text(widget.label)),
      Expanded(
        flex: 5,
        child: Slider(
          value: v,
          min: widget.min,
          max: widget.max,
          onChanged: (x) => setState(() => _drag = x),
          onChangeEnd: (x) {
            widget.onEnd(x);
            setState(() => _drag = null);
          },
        ),
      ),
      SizedBox(width: 72, child: Text('${v.round()}${widget.suffix}', textAlign: TextAlign.end)),
    ]);
  }
}
