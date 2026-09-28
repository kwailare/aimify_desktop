import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/api_constants.dart';

/// Opens the website's billing page (`/dashboard/billing`) in the system
/// browser. All payment happens there — Paystack by card, bank transfer or
/// USSD — so this is the one action the app ever offers for it; nothing here
/// ever builds a payment form.
class ManageBillingLink extends StatelessWidget {
  const ManageBillingLink({super.key, this.label = 'Manage billing'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => launchUrl(
        Uri.parse(ApiConstants.billingUrl),
        mode: LaunchMode.externalApplication,
      ),
      icon: const Icon(Icons.open_in_new, size: 14),
      label: Text(label),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: const Size(0, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
