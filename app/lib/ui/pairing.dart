import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import 'timers.dart';

/// Starts and shows pairing mode: while it is on the tablet advertises itself (mDNS) so Home Assistant finds it, and
/// shows the code and address for the manual route. Used by the setup wizard and the System page.
class PairingPanel extends StatelessWidget {
  const PairingPanel({super.key, required this.controller});
  final AppController controller;

  Future<void> _start() async {
    await controller.platform.startPairing();
    await controller.refresh();
  }

  Future<void> _stop() async {
    await controller.platform.stopPairing();
    await controller.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = controller.status.pairing;
    final active = p?['active'] == true;
    if (!active) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (p?['locked'] == true)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'pairing.locked'.tr(),
                style: TextStyle(color: t.colorScheme.error),
              ),
            ),
          FilledButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.wifi_tethering),
            label: Text('pairing.start'.tr()),
          ),
        ],
      );
    }
    final hosts = ((p!['hosts'] as List?) ?? const []).cast<String>();
    final port = p['port'];
    final expires = DateTime.fromMillisecondsSinceEpoch(
      (p['expires_at'] as num).toInt(),
    );
    return Card(
      elevation: 0,
      color: t.colorScheme.primaryContainer.withValues(alpha: .35),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.wifi_tethering),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'pairing.waiting'.tr(),
                    style: t.textTheme.titleMedium,
                  ),
                ),
                SecondTicker(
                  builder: (context, now) {
                    final left = expires.difference(now);
                    return Text(
                      formatClock(left.isNegative ? Duration.zero : left),
                      style: t.textTheme.titleMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('pairing.found_auto'.tr(), style: t.textTheme.bodyMedium),
            const SizedBox(height: 16),
            Text('pairing.manual'.tr(), style: t.textTheme.labelLarge),
            const SizedBox(height: 8),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                Clipboard.setData(ClipboardData(text: '${p['code']}'));
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('common.copied'.tr())));
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '${p['code']}',
                  style: t.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 4,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            Text(
              [for (final h in hosts) '$h:$port'].join('   '),
              style: t.textTheme.titleMedium?.copyWith(
                color: t.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextButton(onPressed: _stop, child: Text('common.cancel'.tr())),
          ],
        ),
      ),
    );
  }
}

/// Shows Home Assistant's pairing request (confirm mode) above whatever the app is showing, however it was reached.
class PairingRequestHost extends StatelessWidget {
  const PairingRequestHost({
    super.key,
    required this.controller,
    required this.child,
  });
  final AppController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final req = controller.status.pairing?['request'] as Map?;
        return Stack(
          children: [
            child,
            if (req != null) ...[
              const ModalBarrier(dismissible: false, color: Colors.black54),
              Center(
                child: Material(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(28),
                  elevation: 6,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.link, size: 36),
                          const SizedBox(height: 12),
                          Text(
                            'pairing.request_title'.tr(
                              namedArgs: {'name': '${req['ha_name']}'},
                            ),
                            style: Theme.of(context).textTheme.titleLarge,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'pairing.request_text'.tr(),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '${req['sas']}'.replaceRange(3, 3, ' '),
                            style: Theme.of(context).textTheme.displayMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 4,
                                ),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () async {
                                    await controller.platform.answerPairing(
                                      false,
                                    );
                                    await controller.refresh();
                                  },
                                  child: Text('pairing.deny'.tr()),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton(
                                  onPressed: () async {
                                    await controller.platform.answerPairing(
                                      true,
                                    );
                                    await controller.refresh();
                                  },
                                  child: Text('pairing.allow'.tr()),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
