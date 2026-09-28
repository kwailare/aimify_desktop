import 'package:flutter/material.dart';

import '../../parties/domain/party.dart';
import '../../parties/presentation/parties_screen.dart';

/// The suppliers list — see [PartiesScreen].
class SuppliersScreen extends StatelessWidget {
  const SuppliersScreen({super.key});

  @override
  Widget build(BuildContext context) => const PartiesScreen(type: PartyType.supplier);
}
