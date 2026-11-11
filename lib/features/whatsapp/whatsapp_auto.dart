import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/offline/local_store.dart';
import '../auth/presentation/auth_controller.dart';
import 'whatsapp_share.dart';

// After a sale or a payment, WhatsApp opens by itself with the invoice or
// receipt ready for the customer, so staff only press Send. On by default;
// whether it does is remembered on this computer (the "Send on WhatsApp"
// tick on the sale form). Not when Aimify's WhatsApp Business account
// already sends that message itself, so nobody gets it twice.

const _key = 'whatsapp_auto_open';

class WhatsAppAutoOpenNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async => (await ref.read(localStoreProvider).read(_key)) != 'off';

  Future<void> set(bool on) async {
    state = AsyncData(on);
    await ref.read(localStoreProvider).write(_key, on ? 'on' : 'off');
  }
}

final whatsAppAutoOpenProvider = AsyncNotifierProvider<WhatsAppAutoOpenNotifier, bool>(WhatsAppAutoOpenNotifier.new);

enum WhatsAppMessageKind { invoice, receipt }

/// Whether Aimify itself sends this message to this recipient, so the app
/// shouldn't open WhatsApp for it as well.
bool sentAutomatically(WidgetRef ref, WhatsAppMessageKind kind, {required bool recipientAgreed}) {
  final status = ref.read(authControllerProvider).valueOrNull?.whatsapp;
  if (status == null || !status.connected || !recipientAgreed) return false;
  return kind == WhatsAppMessageKind.invoice ? status.invoices : status.receipts;
}

/// Opens WhatsApp with [text] for [phone] when that is wanted here: a usable
/// number, the setting on, and the message not sent automatically.
Future<bool> autoOpenWhatsApp(
  BuildContext context,
  WidgetRef ref, {
  required String? phone,
  required String text,
  required WhatsAppMessageKind kind,
  bool recipientAgreed = true,
}) async {
  if (toWhatsAppNumber(phone) == null) return false;
  final on = ref.read(whatsAppAutoOpenProvider).valueOrNull ?? true;
  if (!on || sentAutomatically(ref, kind, recipientAgreed: recipientAgreed)) return false;
  await openWhatsApp(context, ref, phone: phone, text: text);
  return true;
}
