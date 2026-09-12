import 'package:flutter/material.dart';

const _categoryPalette = [
  Color(0xFFD88B00),
  Color(0xFF6C63FF),
  Color(0xFF2F8F5B),
  Color(0xFFD1453B),
  Color(0xFF1E88E5),
  Color(0xFF8D6E63),
];

/// Deterministic color for a category name — the same string always gets
/// the same color, without needing a separate color field on the model.
Color colorForCategory(String category) {
  return _categoryPalette[category.hashCode.abs() % _categoryPalette.length];
}

/// Small colored tag for a product category, used anywhere a category
/// needs to be visually scannable at a glance in a table.
class CategoryTag extends StatelessWidget {
  const CategoryTag({super.key, required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    final color = colorForCategory(category);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        category,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11.5),
      ),
    );
  }
}
