import 'package:easy_localization/easy_localization.dart';
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
          title: Text(c.status.hasPin ? 'pin.change'.tr() : 'pin.set'.tr()),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('pin.dialog_intro'.tr()),
              const SizedBox(height: 12),
              TextField(
                controller: first,
                autofocus: true,
                keyboardType: TextInputType.number,
                obscureText: true,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'pin.new'.tr(),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: second,
                keyboardType: TextInputType.number,
                obscureText: true,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'pin.repeat'.tr(),
                  errorText: error,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('common.cancel'.tr()),
            ),
            FilledButton(
              onPressed: () {
                if (first.text.length < 4) {
                  setState(() => error = 'pin.too_short'.tr());
                } else if (first.text != second.text) {
                  setState(() => error = 'pin.mismatch'.tr());
                } else {
                  Navigator.pop(ctx, true);
                }
              },
              child: Text('common.save'.tr()),
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
Future<void> toggleLockdown(
  BuildContext context,
  AppController c,
  bool on,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await c.platform.setLockdown(on);
  } on PlatformException catch (e) {
    final key = switch (e.code) {
      'dashboard_required' => 'lock.err_dashboard',
      'pin_required' => 'lock.err_pin',
      'no_enforcement_available' => 'lock.err_protection',
      _ => null,
    };
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          key != null
              ? key.tr()
              : 'lock.err_other'.tr(namedArgs: {'error': e.message ?? e.code}),
        ),
      ),
    );
  }
  await c.refresh();
}

/// Gives up device ownership (no factory reset). Asks for the kiosk PIN when one is set; the device owner can only be removed this way
/// or by a factory reset, so the dialog says what happens first.
Future<void> showRemoveOwnerDialog(
  BuildContext context,
  AppController c,
) async {
  final pin = TextEditingController();
  final needPin = c.status.hasPin;
  final messenger = ScaffoldMessenger.of(context);
  // outside the builder: the keyboard changes the layout, and Flutter may run the builder again, which would reset it
  String? error;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('owner.remove_title'.tr()),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('owner.remove_body'.tr()),
              if (needPin) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: pin,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'owner.remove_pin'.tr(),
                    errorText: error,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('common.cancel'.tr()),
            ),
            FilledButton(
              onPressed: () async {
                if (needPin) {
                  final r = await c.platform.unlockWithPin(pin.text);
                  if (r != 0) {
                    setState(
                      () => error = r < 0
                          ? 'pin.page.wrong'.tr()
                          : 'pin.page.locked'.tr(
                              namedArgs: {'seconds': '${(r + 999) ~/ 1000}'},
                            ),
                    );
                    return;
                  }
                }
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: Text('owner.remove_button'.tr()),
            ),
          ],
        ),
      );
    },
  );
  if (confirmed != true) return;
  try {
    await c.platform.clearDeviceOwner();
    await c.refresh();
    messenger.showSnackBar(SnackBar(content: Text('owner.removed'.tr())));
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text('owner.remove_failed'.tr(namedArgs: {'error': '$e'})),
      ),
    );
  }
}
