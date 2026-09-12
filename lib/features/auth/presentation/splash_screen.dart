import 'package:flutter/material.dart';

/// Shown once, on app startup, while [AuthController] checks for a stored
/// token and (if present) validates it against `GET /api/v1/me`.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
