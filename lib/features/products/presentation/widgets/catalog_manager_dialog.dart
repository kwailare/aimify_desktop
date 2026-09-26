import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/utils/friendly_error.dart';
import '../../../auth/domain/permissions.dart';
import '../../../auth/presentation/permissions_provider.dart';
import '../../data/catalog_repository.dart';

/// Manage the organization's product categories and units (`catalog.write`
/// to change them; everyone can read). Removing one that products still
/// use is refused by the server with a message saying how many.
class CatalogManagerDialog extends ConsumerWidget {
  const CatalogManagerDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: AlertDialog(
        title: const Text('Categories and units'),
        content: const SizedBox(
          width: 460,
          height: 420,
          child: Column(
            children: [
              TabBar(tabs: [Tab(text: 'Categories'), Tab(text: 'Units')]),
              SizedBox(height: 12),
              Expanded(
                child: TabBarView(
                  children: [
                    _CatalogList(kind: CatalogKind.category, noun: 'category'),
                    _CatalogList(kind: CatalogKind.unit, noun: 'unit'),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
        ],
      ),
    );
  }
}

class _CatalogList extends ConsumerStatefulWidget {
  const _CatalogList({required this.kind, required this.noun});

  final CatalogKind kind;
  final String noun;

  @override
  ConsumerState<_CatalogList> createState() => _CatalogListState();
}

class _CatalogListState extends ConsumerState<_CatalogList> {
  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    await _run(() async {
      await ref.read(catalogProvider(widget.kind).notifier).add(name);
      _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canEdit = hasPermission(ref, Permissions.catalogWrite);
    final options = ref.watch(catalogProvider(widget.kind));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canEdit)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  maxLength: 60,
                  decoration: InputDecoration(
                    labelText: 'New ${widget.noun}',
                    counterText: '',
                  ),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _busy ? null : _add,
                child: const Text('Add'),
              ),
            ],
          )
        else
          Text(
            "Your role can view these but can't change them.",
            style: theme.textTheme.bodySmall,
          ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 8),
        Expanded(
          child: options.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text(friendlyError(e))),
            data: (items) => items.isEmpty
                ? Center(
                    child: Text(
                      'No ${widget.noun}s yet — they are added automatically when you use one on a product.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView(
                    children: [
                      for (final item in items)
                        ListTile(
                          dense: true,
                          title: Text(item.name),
                          trailing: canEdit
                              ? IconButton(
                                  tooltip: 'Remove',
                                  icon: const Icon(Icons.delete_outline, size: 18),
                                  onPressed: _busy
                                      ? null
                                      : () => _run(
                                            () => ref
                                                .read(catalogProvider(widget.kind).notifier)
                                                .remove(item.id),
                                          ),
                                )
                              : null,
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
