import 'package:flutter/material.dart';

import '../../parties/domain/party.dart';
import '../../parties/presentation/parties_screen.dart';

/// The customers list — see [PartiesScreen].
class CustomersScreen extends StatelessWidget {
  const CustomersScreen({super.key});

  @override
  Widget build(BuildContext context) => const PartiesScreen(type: PartyType.customer);
}
