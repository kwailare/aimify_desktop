import 'package:flutter/material.dart';

import '../../../shared/utils/formatters.dart';
import '../domain/customer.dart';

/// Read-only transaction history for one customer. Data comes straight off
/// the MOCK [Customer] object passed in — see `customers_repository.dart`.
class CustomerHistoryDialog extends StatelessWidget {
  const CustomerHistoryDialog({super.key, required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(customer.name),
      content: SizedBox(
        width: 420,
        child: customer.transactionHistory.isEmpty
            ? const Text('No transactions recorded yet.')
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final tx in customer.transactionHistory)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(tx.description),
                                Text(
                                  dateFormat.format(tx.date),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          Text(
                            currencyFormat.format(tx.amount),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: tx.amount >= 0
                                  ? Theme.of(context).colorScheme.error
                                  : const Color(0xFF2F8F5B),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
