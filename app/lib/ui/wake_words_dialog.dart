import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../app_controller.dart';

Future<void> showWakeWordsDialog(BuildContext context, AppController c) =>
    showDialog<void>(
      context: context,
      builder: (_) => WakeWordsDialog(controller: c),
    );

/// Which wake words to listen for (several at once) and which models are on the tablet: tick to listen,
/// download or remove the model of each phrase. Updates live while models download.
class WakeWordsDialog extends StatefulWidget {
  const WakeWordsDialog({super.key, required this.controller});
  final AppController controller;

  @override
  State<WakeWordsDialog> createState() => _WakeWordsDialogState();
}

class _WakeWordsDialogState extends State<WakeWordsDialog> {
  AppController get c => widget.controller;

  /// The selection as the user sees it while writes are on their way. The tablet's status lags a refresh behind, so a
  /// second tap computed from it would undo the first.
  List<String>? _local;
  int _inflight = 0;
  Future<void> _writes = Future.value();

  List<String> get _chosen =>
      _local ?? [for (final w in c.status.activeWakeWords) w['id'] as String];

  void _toggle(String id, bool on) {
    final next = [..._chosen];
    on ? (next.contains(id) ? null : next.add(id)) : next.remove(id);
    setState(() => _local = next);
    _inflight++;
    _writes = _writes
        .then((_) => c.setConfig('wake_word_ids', next.join(',')))
        .then((_) {})
        .whenComplete(() {
          if (--_inflight == 0 && mounted) setState(() => _local = null);
        });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final st = c.status;
        final chosen = _chosen;
        return AlertDialog(
          title: Text('wakeword.dialog_title'.tr()),
          content: SizedBox(
            width: 520,
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(
                  'wakeword.dialog_hint'.tr(),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                for (final w in st.wakeWords)
                  _Row(
                    word: w,
                    active: chosen.contains(w['id']),
                    fraction: st.wakeWordDownloading == w['id']
                        ? st.wakeWordDownloadFraction
                        : null,
                    onToggle: (on) => _toggle(w['id'] as String, on),
                    onDownload: () async {
                      await c.platform.downloadWakeWord(w['id'] as String);
                      await c.refresh();
                    },
                    onRemove: () async {
                      setState(() => _local = _chosen..remove(w['id']));
                      await c.platform.removeWakeWord(w['id'] as String);
                      await c.refresh();
                      if (mounted && _inflight == 0) {
                        setState(() => _local = null);
                      }
                    },
                  ),
                const SizedBox(height: 8),
                Text(
                  'wakeword.dialog_sources'.tr(),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('wakeword.done'.tr()),
            ),
          ],
        );
      },
    );
  }
}

String _mb(num bytes) => (bytes / 1048576).toStringAsFixed(1);

class _Row extends StatelessWidget {
  const _Row({
    required this.word,
    required this.active,
    required this.fraction,
    required this.onToggle,
    required this.onDownload,
    required this.onRemove,
  });
  final Map<String, dynamic> word;
  final bool active;
  final double? fraction; // while this model downloads
  final ValueChanged<bool> onToggle;
  final VoidCallback onDownload;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final installed = word['installed'] == true;
    final downloading = word['downloading'] == true;
    final queued = word['queued'] == true;
    final missing = (word['missing_bytes'] as num?) ?? 0;
    final subtitle = downloading
        ? 'wakeword.downloading_row'.tr(
            namedArgs: {'pct': ((fraction ?? 0) * 100).round().toString()},
          )
        : queued
        ? 'wakeword.queued'.tr()
        : installed
        ? 'wakeword.on_tablet'.tr(namedArgs: {'mb': _mb(word['size_bytes'])})
        : 'wakeword.not_on_tablet'.tr(namedArgs: {'mb': _mb(missing)});
    return ListTile(
      key: ValueKey('wake-${word['id']}'),
      contentPadding: EdgeInsets.zero,
      leading: Checkbox(
        key: ValueKey('wake-check-${word['id']}'),
        value: active,
        onChanged: (v) => onToggle(v ?? false),
      ),
      title: Text(word['phrase'] as String),
      subtitle: downloading
          ? Padding(
              padding: const EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(value: fraction),
            )
          : Text(subtitle),
      trailing: downloading || queued
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : installed
          ? IconButton(
              key: ValueKey('wake-remove-${word['id']}'),
              tooltip: 'wakeword.remove'.tr(),
              icon: const Icon(Icons.delete_outline),
              onPressed: onRemove,
            )
          : TextButton.icon(
              key: ValueKey('wake-download-${word['id']}'),
              onPressed: onDownload,
              icon: const Icon(Icons.download_outlined, size: 18),
              label: Text('wakeword.download'.tr()),
            ),
    );
  }
}
