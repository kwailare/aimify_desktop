import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the sidebar is open, toggled by the menu button in [AppShell].
/// On a wide window this docks/undocks a full panel; on a narrow window it
/// shows/hides an overlay drawer instead — see `app_shell.dart`.
final sidebarOpenProvider = StateProvider<bool>((ref) => true);
