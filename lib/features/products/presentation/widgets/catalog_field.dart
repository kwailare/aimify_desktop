import 'package:flutter/material.dart';

/// A text field that suggests the organization's existing categories or
/// units as you type but accepts anything — the API adds a new value to the
/// list automatically the first time a product uses it.
class CatalogField extends StatefulWidget {
  const CatalogField({
    super.key,
    required this.controller,
    required this.label,
    required this.options,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final List<String> options;
  final String? Function(String?)? validator;

  @override
  State<CatalogField> createState() => _CatalogFieldState();
}

class _CatalogFieldState extends State<CatalogField> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsBuilder: (value) {
        final query = value.text.trim().toLowerCase();
        return widget.options.where((o) => query.isEmpty || o.toLowerCase().contains(query));
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) => TextFormField(
        controller: controller,
        focusNode: focusNode,
        decoration: InputDecoration(
          labelText: widget.label,
          suffixIcon: const Icon(Icons.arrow_drop_down, size: 20),
        ),
        validator: widget.validator,
      ),
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220, maxWidth: 260),
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [
                  for (final option in options)
                    ListTile(
                      dense: true,
                      title: Text(option, overflow: TextOverflow.ellipsis),
                      onTap: () => onSelected(option),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
