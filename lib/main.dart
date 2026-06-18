// FieldWorker v1.10 — placeholder entry point
// Replace this file with the actual source code from your local Flutter project.
// Push the full source to this repository to enable CI/CD builds.

import 'package:flutter/material.dart';

void main() {
  runApp(const FieldWorkerApp());
}

class FieldWorkerApp extends StatelessWidget {
  const FieldWorkerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FieldWorker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: Center(
          child: Text(
            'FieldWorker\nSource code pending upload.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18),
          ),
        ),
      ),
    );
  }
}
