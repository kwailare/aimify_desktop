import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Manual light/dark toggle for the whole app. Starts following the OS
/// setting; flipping the switch in the sidebar pins it explicitly.
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
