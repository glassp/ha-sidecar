import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';

Future<void> showPinDialog(BuildContext context, AppController c) async {
  final first = TextEditingController();
  final second = TextEditingController();
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      String? error;
      return StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(c.status.hasPin ? 'Change PIN' : 'Set a PIN'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('At least 4 digits. You will enter it by tapping the top-left corner of the locked screen 5 times.'),
            const SizedBox(height: 12),
            TextField(
              controller: first,
              autofocus: true,
              keyboardType: TextInputType.number,
              obscureText: true,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'New PIN', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: second,
              keyboardType: TextInputType.number,
              obscureText: true,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: 'Repeat PIN', errorText: error, border: const OutlineInputBorder()),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (first.text.length < 4) {
                  setState(() => error = 'Use at least 4 digits');
                } else if (first.text != second.text) {
                  setState(() => error = 'The PINs do not match');
                } else {
                  Navigator.pop(ctx, true);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );
    },
  );
  if (saved == true) {
    await c.platform.setPin(first.text);
    await c.refresh();
  }
}

/// Lock/unlock with a readable message for each way it can be refused.
Future<void> toggleLockdown(BuildContext context, AppController c, bool on) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await c.platform.setLockdown(on);
  } on PlatformException catch (e) {
    final msg = switch (e.code) {
      'dashboard_required' => 'Choose the kiosk dashboard first (Kiosk → Dashboards).',
      'pin_required' => 'Set a PIN first.',
      'no_enforcement_available' => 'Turn on the accessibility guard or make this tablet a device owner first.',
      _ => 'Could not change the lock: ${e.message ?? e.code}',
    };
    messenger.showSnackBar(SnackBar(content: Text(msg)));
  }
  await c.refresh();
}
