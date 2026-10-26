import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/services/api_exception.dart';
import '../../shared/utils/formatters.dart';
import '../../shared/utils/friendly_error.dart';
import '../parties/data/parties_repository.dart';
import '../parties/domain/party.dart';
import 'document_data.dart';
import 'document_preview.dart';
import 'purchase_documents.dart';

enum StatementPeriod { thisMonth, lastMonth, last3Months, thisYear, allTime, custom }

extension StatementPeriodX on StatementPeriod {
  String get label => switch (this) {
        StatementPeriod.thisMonth => 'This month',
        StatementPeriod.lastMonth => 'Last month',
        StatementPeriod.last3Months => 'Last 3 months',
        StatementPeriod.thisYear => 'This year',
        StatementPeriod.allTime => 'Everything',
        StatementPeriod.custom => 'Choose dates…',
      };

  /// The period as [from, to): `from` null means from the first entry, `to`
  /// is the start of the day after the last one included.
  ({DateTime? from, DateTime to}) range(DateTime now, {DateTimeRange? custom}) {
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    return switch (this) {
      StatementPeriod.thisMonth => (from: DateTime(now.year, now.month), to: tomorrow),
      StatementPeriod.lastMonth => (from: DateTime(now.year, now.month - 1), to: DateTime(now.year, now.month)),
      StatementPeriod.last3Months => (from: DateTime(now.year, now.month - 2), to: tomorrow),
      StatementPeriod.thisYear => (from: DateTime(now.year), to: tomorrow),
      StatementPeriod.allTime => (from: null, to: tomorrow),
      StatementPeriod.custom => (
          from: custom == null ? DateTime(now.year, now.month) : DateTime(custom.start.year, custom.start.month, custom.start.day),
          to: custom == null ? tomorrow : DateTime(custom.end.year, custom.end.month, custom.end.day + 1),
        ),
    };
  }
}

/// Picks the period for a customer or supplier statement, reads that part
/// of their ledger from the server and opens the statement.
class StatementDialog extends ConsumerStatefulWidget {
  const StatementDialog({super.key, required this.party});

  final Party party;

  @override
  ConsumerState<StatementDialog> createState() => _StatementDialogState();
}

class _StatementDialogState extends ConsumerState<StatementDialog> {
  StatementPeriod _period = StatementPeriod.last3Months;
  DateTimeRange? _custom;
  bool _loading = false;
  String? _error;

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _custom ?? DateTimeRange(start: DateTime(now.year, now.month), end: now),
    );
    if (picked != null) {
      setState(() {
        _custom = picked;
        _period = StatementPeriod.custom;
      });
    }
  }

  Future<void> _generate() async {
    final range = _period.range(DateTime.now(), custom: _custom);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ledger = await ref
          .read(partiesRepositoryProvider)
          .ledgerForPeriod(widget.party.type, widget.party.id, from: range.from, to: range.to);
      final statement = buildStatement(
        from: range.from,
        to: range.to,
        openingBalance: ledger.openingBalance,
        entries: ledger.entries,
      );
      if (!mounted) return;
      final navigator = Navigator.of(context);
      final opener = ref.read(documentOpenerProvider);
      final name = widget.party.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-');
      navigator.pop();
      await opener.open(
        navigator.context,
        ref,
        title: 'Statement · ${widget.party.name}',
        fileName: 'Statement-$name.pdf',
        build: (kit) => buildPartyStatement(kit, widget.party, statement),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is NetworkException
            ? "You're offline. A statement is read fresh from the server, so it needs a connection."
            : friendlyError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final custom = _custom;
    return AlertDialog(
      title: Text('Statement for ${widget.party.name}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Every purchase, payment and adjustment in the period, with the balance after each.'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in StatementPeriod.values)
                  ChoiceChip(
                    key: Key('statement-${p.name}'),
                    label: Text(
                      p == StatementPeriod.custom && custom != null
                          ? '${dateFormat.format(custom.start)} – ${dateFormat.format(custom.end)}'
                          : p.label,
                    ),
                    selected: _period == p,
                    onSelected: _loading
                        ? null
                        : (_) => p == StatementPeriod.custom ? _pickCustom() : setState(() => _period = p),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, key: const Key('statement-error'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _loading ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton.icon(
          key: const Key('statement-generate'),
          onPressed: _loading ? null : _generate,
          icon: _loading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.description_outlined, size: 18),
          label: const Text('Create statement'),
        ),
      ],
    );
  }
}
